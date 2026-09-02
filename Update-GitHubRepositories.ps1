[CmdletBinding()]
param(
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportDirectory = Join-Path $repositoryRoot 'reports'
$localDirectory = Join-Path $repositoryRoot '.local'
$publicReportPath = Join-Path $reportDirectory 'repository-status.md'
$privateReportPath = Join-Path $localDirectory 'private-repository-status.md'
$today = Get-Date -Format 'yyyy-MM-dd'

New-Item -ItemType Directory -Force -Path $reportDirectory, $localDirectory | Out-Null

function Get-GitHubToken {
    $credentialQuery = "protocol=https`nhost=github.com`n`n"
    $credentialLines = $credentialQuery | git credential fill 2>$null
    $passwordLine = $credentialLines | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if (-not $passwordLine) {
        throw 'Windows 자격 증명 관리자에서 GitHub 토큰을 찾지 못했습니다.'
    }
    return $passwordLine.Substring(9)
}

$token = Get-GitHubToken
$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

function Invoke-GitHubGet {
    param([Parameter(Mandatory)][string]$Uri)
    return Invoke-RestMethod -Headers $headers -Uri $Uri -Method Get
}

function Get-RepositoryRootNames {
    param([Parameter(Mandatory)]$Repository)

    if ([int64]$Repository.size -eq 0) {
        return @()
    }

    $encodedBranch = [uri]::EscapeDataString([string]$Repository.default_branch)
    $uri = "https://api.github.com/repos/$($Repository.full_name)/contents?ref=$encodedBranch"
    try {
        $items = @(Invoke-GitHubGet -Uri $uri)
        return @($items | ForEach-Object { [string]$_.name })
    }
    catch {
        return @('__ROOT_CHECK_FAILED__')
    }
}

function Get-Findings {
    param(
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RootNames
    )

    $findings = [System.Collections.Generic.List[string]]::new()
    if ($Repository.archived) { $findings.Add('보관된 저장소') }
    if ($Repository.fork) { $findings.Add('포크 저장소: 잔디용 자동 커밋 제외') }
    if ([int64]$Repository.size -eq 0) { $findings.Add('빈 저장소') }
    if ($RootNames -contains '__ROOT_CHECK_FAILED__') { $findings.Add('루트 파일 확인 실패') }

    $isStandaloneOwned = -not $Repository.fork -and -not $Repository.archived
    if ($isStandaloneOwned -and [int64]$Repository.size -gt 0) {
        if (-not ($RootNames | Where-Object { $_ -match '^README(?:\.|$)' })) {
            $findings.Add('README 없음')
        }
        if (-not ($RootNames | Where-Object { $_ -match '^\.gitignore$' })) {
            $findings.Add('.gitignore 없음')
        }
        if (-not $Repository.private -and -not ($RootNames | Where-Object { $_ -match '^(LICENSE|LICENCE)(?:\.|$)' })) {
            $findings.Add('공개 저장소 라이선스 없음')
        }
        if ([string]$Repository.default_branch -match '^(claude|codex)/') {
            $findings.Add("기본 브랜치가 작업 브랜치임: $($Repository.default_branch)")
        }
        $lastPush = [datetimeoffset]$Repository.pushed_at
        if ($lastPush -lt (Get-Date).AddDays(-90)) {
            $findings.Add('최근 90일 동안 푸시 없음')
        }
    }

    if ($findings.Count -eq 0) {
        $findings.Add('기본 점검 통과')
    }
    return @($findings)
}

function Update-KnownLocalRepositories {
    $paths = @(
        'C:\Users\UserK\Documents\GitHub\Code-Horizon-team',
        'C:\Users\UserK\Documents\쿠팡 자동화 시스템',
        'C:\Users\UserK\Documents\프로키베이프 화면 만들기'
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) {
            continue
        }
        $remote = git -C $path remote get-url origin 2>$null
        if (-not $remote) {
            continue
        }
        $dirtyCount = @(git -C $path status --porcelain).Count
        if ($dirtyCount -gt 0) {
            $results.Add([pscustomobject]@{ Path = $path; Result = "건너뜀: 미커밋 변경 $dirtyCount개" })
            continue
        }
        git -C $path fetch --prune origin *> $null
        if ($LASTEXITCODE -ne 0) {
            $results.Add([pscustomobject]@{ Path = $path; Result = '실패: fetch 오류' })
            continue
        }
        $upstream = git -C $path rev-parse --abbrev-ref '@{upstream}' 2>$null
        if (-not $upstream) {
            $results.Add([pscustomobject]@{ Path = $path; Result = '확인 완료: 추적 브랜치 없음' })
            continue
        }
        git -C $path merge --ff-only $upstream *> $null
        if ($LASTEXITCODE -eq 0) {
            $results.Add([pscustomobject]@{ Path = $path; Result = '최신화 완료' })
        }
        else {
            $results.Add([pscustomobject]@{ Path = $path; Result = '건너뜀: fast-forward 불가' })
        }
    }
    return @($results)
}

$me = Invoke-GitHubGet -Uri 'https://api.github.com/user'
$repositories = [System.Collections.Generic.List[object]]::new()
for ($page = 1; $page -le 10; $page++) {
    $batch = @(Invoke-GitHubGet -Uri "https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner,collaborator&sort=full_name")
    foreach ($repository in $batch) { $repositories.Add($repository) }
    if ($batch.Count -lt 100) { break }
}

$auditRows = [System.Collections.Generic.List[object]]::new()
foreach ($repository in ($repositories | Sort-Object full_name)) {
    $rootNames = @(Get-RepositoryRootNames -Repository $repository)
    $auditRows.Add([pscustomobject]@{
        Name = [string]$repository.full_name
        Owner = [string]$repository.owner.login
        Private = [bool]$repository.private
        Fork = [bool]$repository.fork
        Archived = [bool]$repository.archived
        DefaultBranch = [string]$repository.default_branch
        PushedAt = ([datetimeoffset]$repository.pushed_at).ToString('yyyy-MM-dd')
        Findings = @(Get-Findings -Repository $repository -RootNames $rootNames)
    })
}

$localResults = @(Update-KnownLocalRepositories)
$ownedRows = @($auditRows | Where-Object { $_.Owner -eq $me.login })
$collaboratorRows = @($auditRows | Where-Object { $_.Owner -ne $me.login })
$ownedStandaloneRows = @($ownedRows | Where-Object { -not $_.Fork -and -not $_.Archived })
$publicRows = @($ownedStandaloneRows | Where-Object { -not $_.Private })
$privateRows = @($ownedStandaloneRows | Where-Object { $_.Private })
$problemRows = @($ownedStandaloneRows | Where-Object { $_.Findings -notcontains '기본 점검 통과' })

$publicLines = [System.Collections.Generic.List[string]]::new()
$publicLines.Add('# GitHub 공개 저장소 상태')
$publicLines.Add('')
$publicLines.Add("점검일: $today (Asia/Seoul)")
$publicLines.Add('')
$publicLines.Add("- 연결 저장소: $($auditRows.Count)개")
$publicLines.Add("- 개인 소유: $($ownedRows.Count)개")
$publicLines.Add("- 자동 점검 대상(소유·비포크·비보관): $($ownedStandaloneRows.Count)개")
$publicLines.Add("- 공개 상세 표시: $($publicRows.Count)개")
$publicLines.Add("- 비공개 상세: 로컬에만 $($privateRows.Count)개")
$publicLines.Add("- 공동작업 저장소: 읽기 전용 점검 $($collaboratorRows.Count)개")
$publicLines.Add('')
$publicLines.Add('| 저장소 | 기본 브랜치 | 최근 푸시 | 점검 결과 |')
$publicLines.Add('|---|---|---:|---|')
foreach ($row in $publicRows) {
    $shortName = $row.Name.Split('/', 2)[1]
    $url = "https://github.com/$($row.Name)"
    $findingText = $row.Findings -join '; '
    $publicLines.Add("| [$shortName]($url) | ``$($row.DefaultBranch)`` | $($row.PushedAt) | $findingText |")
}
$publicLines.Add('')
$publicLines.Add('> 이 보고서는 저장소 메타데이터와 루트 파일을 가볍게 확인합니다. 전체 코드 보안 감사나 테스트 실행을 대신하지 않습니다.')
$publicLines -join "`n" | Set-Content -LiteralPath $publicReportPath -Encoding utf8

$privateLines = [System.Collections.Generic.List[string]]::new()
$privateLines.Add('# 비공개 및 공동작업 저장소 점검 결과')
$privateLines.Add('')
$privateLines.Add("점검일: $today (Asia/Seoul)")
$privateLines.Add('')
$privateLines.Add('## 조치가 필요한 소유 저장소')
$privateLines.Add('')
foreach ($row in $problemRows) {
    $privateLines.Add("- $($row.Name): $($row.Findings -join '; ')")
}
if ($problemRows.Count -eq 0) { $privateLines.Add('- 없음') }
$privateLines.Add('')
$privateLines.Add('## 공동작업 저장소')
$privateLines.Add('')
foreach ($row in $collaboratorRows) {
    $privateLines.Add("- $($row.Name): 자동 변경 제외, $($row.Findings -join '; ')")
}
$privateLines.Add('')
$privateLines.Add('## 로컬 복제본 동기화')
$privateLines.Add('')
foreach ($result in $localResults) {
    $privateLines.Add("- $($result.Path): $($result.Result)")
}
$privateLines -join "`n" | Set-Content -LiteralPath $privateReportPath -Encoding utf8

if (-not $NoPush) {
    git -C $repositoryRoot config user.name ([string]$me.login)
    git -C $repositoryRoot config user.email "$($me.id)+$($me.login)@users.noreply.github.com"
    git -C $repositoryRoot add -- 'reports/repository-status.md'
    git -C $repositoryRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $repositoryRoot commit -m "chore: 저장소 상태 점검 $today"
        if ($LASTEXITCODE -ne 0) { throw '상태 보고서 커밋에 실패했습니다.' }
        git -C $repositoryRoot push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw '상태 보고서 푸시에 실패했습니다.' }
    }
}

[pscustomobject]@{
    Date = $today
    Connected = $auditRows.Count
    Owned = $ownedRows.Count
    Audited = $ownedStandaloneRows.Count
    Problems = $problemRows.Count
    CollaboratorReadOnly = $collaboratorRows.Count
    PublicReport = $publicReportPath
    PrivateReport = $privateReportPath
} | ConvertTo-Json -Compress

Remove-Variable token
