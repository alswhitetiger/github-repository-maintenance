[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportDirectory = Join-Path $workspaceRoot 'reports'
$localDirectory = Join-Path $workspaceRoot '.local'
$publicReportPath = Join-Path $reportDirectory 'repository-status.md'
$privateReportPath = Join-Path $localDirectory 'all-repositories-report.md'
$statePath = Join-Path $localDirectory 'all-repositories-state.json'
$reviewPath = 'REPOSITORY_REVIEW.md'
$maintenanceReviewPath = Join-Path $workspaceRoot $reviewPath
$maintenanceRepository = 'alswhitetiger/github-repository-maintenance'
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

function Invoke-GitHubWrite {
    param(
        [Parameter(Mandatory)][ValidateSet('Put', 'Post')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)]$Body
    )
    $json = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Headers $headers -Uri $Uri -Method $Method -Body $json -ContentType 'application/json'
}

function Get-FeatureSuggestions {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Stacks
    )

    $lowerName = $Name.ToLowerInvariant()
    switch -Regex ($lowerName) {
        'ai-dept-meeting' { return @('회의 안건 템플릿과 참석자별 액션 아이템 관리', '캘린더 연동 및 마감 알림', '회의 결과 PDF·Markdown 내보내기') }
        'storyteller|llm-game' { return @('게임 진행 저장·불러오기와 분기 기록', '모델 호출 비용·속도 제한 설정', '유해 콘텐츠 필터와 연령별 안전 설정') }
        'brand-launch' { return @('브랜드 키트 버전 관리', '시안 승인·반려 워크플로', '채널별 이미지 규격 일괄 내보내기') }
        'business-command' { return @('핵심 지표 임계치 알림', 'CSV·PDF 보고서 내보내기', '사용자 역할별 접근 권한') }
        'code-horizon' { return @('GitHub 이슈·마일스톤 연동', '배포 미리보기 링크', '핵심 사용자 흐름 자동 테스트') }
        'creator-growth' { return @('콘텐츠 캘린더와 예약 발행', '제목·썸네일 A/B 성과 추적', '플랫폼 오류 재시도와 실패 큐') }
        'find_word' { return @('난이도와 제한 시간 단계', '사용자 진행 상황 저장', '키보드·스크린리더 접근성') }
        'integrated-product|marketplace' { return @('상품 중복 등록 방지와 사전 검증', '실행 전 미리보기(dry-run)', '실패 작업 재시도 및 감사 로그') }
        'jonghap|obsidian|memory' { return @('통합 검색과 태그 필터', '깨진 내부 링크 자동 검사', '복원 가능한 버전 백업') }
        'portfolio' { return @('프로젝트 기술·역할 필터', '모바일 성능 및 접근성 점검', '연락 양식 스팸 방지') }
        'emotional-analysis' { return @('모델 카드와 데이터 사용 범위 문서화', '정확도·편향 평가 리포트', '예측 신뢰도와 오분류 사례 화면') }
        'paper-trading' { return @('손실 한도와 포지션 크기 제한', '벤치마크 대비 성과 대시보드', '주문·체결 감사 로그') }
        'jarvis' { return @('도구별 권한과 실행 전 확인 설정', '오프라인·API 장애 시 대체 동작', '명령 실행 기록과 검색') }
        'prompt-for-quarterfull' { return @('프롬프트 버전 및 변경 이력', '입력·출력 회귀 테스트 예시', '모델별 결과 비교 템플릿') }
        'resume-portfolio' { return @('직무별 이력서 템플릿', 'PDF 내보내기 레이아웃 검증', '누락 항목 및 링크 유효성 검사') }
        'tarot' { return @('리딩 기록과 사용자 동의·삭제 기능', '결제 웹훅 중복 처리 방지', '관리자용 매출·사용 통계') }
        'travel-companion' { return @('오프라인 일정 열람', '지도 동선과 이동 시간 계산', '여행 경비 분담 및 통화 환산') }
        'voice-chat' { return @('자막과 음성 접근성 설정', '연결 끊김 자동 복구', '응답 지연 진단 화면') }
        'github-repository-maintenance' { return @('이전 점검 대비 변화만 알림', 'GitHub API 한도 및 실패 저장소 표시', '저장소별 권장사항 해결 상태 추적') }
        '^-$' { return @('저장소 목적에 맞는 이름과 설명으로 정리', '최소 사용 예시와 향후 계획 추가', '보관 또는 다른 저장소와 통합 여부 결정') }
        default {
            if ($Stacks -contains 'Python') { return @('재현 가능한 실행 환경과 설정 분리', '핵심 로직 자동 테스트', '구조화 로그와 오류 보고') }
            if ($Stacks -contains 'JavaScript/TypeScript') { return @('핵심 사용자 흐름 E2E 테스트', '접근성 및 모바일 화면 점검', '운영 오류 추적과 사용자 피드백 수집') }
            return @('핵심 사용 시나리오 자동 테스트', '변경 이력과 로드맵 문서', '오류 진단을 위한 구조화 로그')
        }
    }
}

function Get-RepositoryAnalysis {
    param(
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)]$Tree
    )

    $entries = @($Tree.tree)
    $paths = @($entries | ForEach-Object { [string]$_.path })
    $lowerPaths = @($paths | ForEach-Object { $_.ToLowerInvariant() })
    $fileEntries = @($entries | Where-Object { $_.type -eq 'blob' -and $_.path -ne $reviewPath })
    $filePaths = @($fileEntries | ForEach-Object { [string]$_.path })
    $stacks = [System.Collections.Generic.List[string]]::new()

    if ($lowerPaths -contains 'package.json' -or $lowerPaths | Where-Object { $_ -match '\.(js|jsx|ts|tsx)$' }) { $stacks.Add('JavaScript/TypeScript') }
    if ($lowerPaths | Where-Object { $_ -match '(^|/)(requirements\.txt|pyproject\.toml|setup\.py)$|\.py$' }) { $stacks.Add('Python') }
    if ($lowerPaths | Where-Object { $_ -match '\.(html|css|scss)$' }) { $stacks.Add('Web') }
    if ($lowerPaths | Where-Object { $_ -match '\.(ipynb)$' }) { $stacks.Add('Jupyter') }
    if ($lowerPaths | Where-Object { $_ -match '(^|/)dockerfile$|docker-compose' }) { $stacks.Add('Docker') }
    if ($lowerPaths | Where-Object { $_ -match '\.(md|mdx)$' }) { $stacks.Add('문서') }
    if ($stacks.Count -eq 0) { $stacks.Add('기타/확인 필요') }

    $needed = [System.Collections.Generic.List[string]]::new()
    $hasReadme = [bool]($lowerPaths | Where-Object { $_ -match '(^|/)readme(?:\.|$)' })
    $hasGitignore = $lowerPaths -contains '.gitignore'
    $hasLicense = [bool]($lowerPaths | Where-Object { $_ -match '(^|/)(license|licence)(?:\.|$)' })
    $hasTests = [bool]($lowerPaths | Where-Object { $_ -match '(^|/)(test|tests|spec|specs)/|\.(test|spec)\.' })
    $hasWorkflow = [bool]($lowerPaths | Where-Object { $_ -match '^\.github/workflows/.+\.ya?ml$' })
    $hasDependabot = $lowerPaths -contains '.github/dependabot.yml'
    $hasManifest = [bool]($lowerPaths | Where-Object { $_ -match '(^|/)(package\.json|requirements\.txt|pyproject\.toml|pom\.xml|build\.gradle|cargo\.toml)$' })

    if (-not $hasReadme) { $needed.Add('README에 목적, 설치 방법, 실행 예시 추가') }
    if (-not $hasGitignore) { $needed.Add('사용 기술에 맞는 .gitignore 추가') }
    if (-not $hasTests -and $fileEntries.Count -gt 3) { $needed.Add('핵심 기능을 보호하는 최소 자동 테스트 추가') }
    if (-not $hasWorkflow -and $fileEntries.Count -gt 3) { $needed.Add('테스트·문서 검사용 CI 워크플로 추가') }
    if (-not $Repository.private -and -not $hasLicense) { $needed.Add('공개 사용 범위를 명확히 하는 라이선스 선택') }
    if ($hasManifest -and -not $hasDependabot) { $needed.Add('의존성 보안 업데이트 자동화 검토') }
    if ($needed.Count -eq 0) { $needed.Add('현재 기본 구성에서 즉시 필요한 항목 없음') }

    $cleanup = [System.Collections.Generic.List[string]]::new()
    $trackedEnv = @($filePaths | Where-Object { $_ -match '(^|/)\.env($|\.)' -and $_ -notmatch '\.example$|\.sample$' })
    if ($trackedEnv.Count -gt 0) { $cleanup.Add("비밀정보 위험: 추적 중인 환경 파일 $($trackedEnv -join ', ')") }
    $generated = @($filePaths | Where-Object { $_ -match '(^|/)(node_modules|__pycache__|\.venv|venv|dist|build|coverage|\.cache)/' } | Select-Object -First 8)
    if ($generated.Count -gt 0) { $cleanup.Add("생성물 추적 여부 검토: $($generated -join ', ')") }
    $backups = @($filePaths | Where-Object { $_ -match '(^|/)(backups?|old|archive|temp|tmp|복사본)(/|$)|(_backup|-backup|_old|-old| copy)(\.|$)|\.(bak|old|tmp)$|~$' } | Select-Object -First 8)
    if ($backups.Count -gt 0) { $cleanup.Add("백업·사본 정리 후보: $($backups -join ', ')") }
    $runtimeData = @($filePaths | Where-Object { $_ -match '\.(log|sqlite|sqlite3|db)$' } | Select-Object -First 8)
    if ($runtimeData.Count -gt 0) { $cleanup.Add("실행 데이터의 Git 추적 필요성 검토: $($runtimeData -join ', ')") }
    $largeFiles = @($fileEntries | Where-Object { $_.size -and [int64]$_.size -ge 10485760 } | ForEach-Object { "$($_.path) ($([math]::Round([int64]$_.size / 1MB, 1)) MB)" } | Select-Object -First 8)
    if ($largeFiles.Count -gt 0) { $cleanup.Add("대용량 파일 또는 Git LFS 검토: $($largeFiles -join ', ')") }
    $lockFiles = @($lowerPaths | Where-Object { $_ -in @('package-lock.json', 'yarn.lock', 'pnpm-lock.yaml') })
    if ($lockFiles.Count -gt 1) { $cleanup.Add("JavaScript 패키지 잠금 파일을 하나로 통일: $($lockFiles -join ', ')") }
    if ($cleanup.Count -eq 0) { $cleanup.Add('파일명 기준으로 명확한 불필요 항목은 발견되지 않음') }

    $features = @(Get-FeatureSuggestions -Name ([string]$Repository.name) -Stacks @($stacks))
    return [pscustomobject]@{
        FileCount = $fileEntries.Count
        Stacks = @($stacks)
        Needed = @($needed)
        Features = $features
        Cleanup = @($cleanup)
    }
}

function New-ReviewContent {
    param(
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)]$Analysis
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# 저장소 점검 보고서')
    $lines.Add('')
    $lines.Add("점검일: $today (Asia/Seoul)")
    $lines.Add('')
    $lines.Add('이 문서는 저장소의 실제 파일 구조를 기준으로 자동 갱신됩니다. 코드 전체의 의미를 이해하는 수동 리뷰를 대체하지 않습니다.')
    $lines.Add('')
    $lines.Add('## 확인 범위')
    $lines.Add('')
    $lines.Add("- 기본 브랜치: ``$($Repository.default_branch)``")
    $lines.Add("- 분석한 파일: $($Analysis.FileCount)개")
    $lines.Add("- 감지 기술: $($Analysis.Stacks -join ', ')")
    $lines.Add('')
    $lines.Add('## 필요한 부분')
    $lines.Add('')
    foreach ($item in $Analysis.Needed) { $lines.Add("- $item") }
    $lines.Add('')
    $lines.Add('## 추가하면 좋은 기능')
    $lines.Add('')
    foreach ($item in $Analysis.Features) { $lines.Add("- $item") }
    $lines.Add('')
    $lines.Add('## 불필요하거나 정리할 후보')
    $lines.Add('')
    foreach ($item in $Analysis.Cleanup) { $lines.Add("- $item") }
    $lines.Add('')
    $lines.Add('> 삭제나 기능 제거는 자동으로 수행하지 않습니다. 실제 사용 여부를 확인한 뒤 결정하세요.')
    return $lines -join "`n"
}

function Get-ExistingBlobContent {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string]$Path
    )
    $entry = $Tree.tree | Where-Object { $_.path -eq $Path -and $_.type -eq 'blob' } | Select-Object -First 1
    if (-not $entry) { return $null }
    $blob = Invoke-GitHubGet -Uri "https://api.github.com/repos/$RepositoryName/git/blobs/$($entry.sha)"
    $content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$blob.content -replace '\s', '')))
    return [pscustomobject]@{ Sha = [string]$entry.sha; Content = $content }
}

$me = Invoke-GitHubGet -Uri 'https://api.github.com/user'
$author = @{ name = [string]$me.login; email = "$($me.id)+$($me.login)@users.noreply.github.com" }
$repositories = [System.Collections.Generic.List[object]]::new()
for ($page = 1; $page -le 10; $page++) {
    $batch = Invoke-GitHubGet -Uri "https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner&sort=full_name"
    foreach ($repository in $batch) { $repositories.Add($repository) }
    if ($batch.Count -lt 100) { break }
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($repository in ($repositories | Sort-Object full_name)) {
    $name = [string]$repository.full_name
    if ($repository.archived) {
        $results.Add([pscustomobject]@{ Name=$name; Private=[bool]$repository.private; Fork=[bool]$repository.fork; Status='건너뜀'; Detail='보관된 저장소'; Needed=@(); Features=@(); Cleanup=@() })
        continue
    }

    if ($repository.fork) {
        $detail = '포크 저장소: 잔디 집계 제외'
        if (-not $DryRun) {
            try {
                Invoke-GitHubWrite -Method Post -Uri "https://api.github.com/repos/$name/merge-upstream" -Body @{ branch = [string]$repository.default_branch } | Out-Null
                $detail = '업스트림과 동기화 완료(포크라 잔디 집계 제외)'
            }
            catch {
                $statusCode = [int]$_.Exception.Response.StatusCode
                if ($statusCode -eq 409) { $detail = '업스트림과 이미 동일하거나 자동 병합 불가' }
                else { $detail = "업스트림 동기화 실패: HTTP $statusCode" }
            }
        }
        $results.Add([pscustomobject]@{ Name=$name; Private=[bool]$repository.private; Fork=$true; Status=if($DryRun){'점검'}else{'동기화'}; Detail=$detail; Needed=@(); Features=@(); Cleanup=@() })
        continue
    }

    try {
        $encodedBranch = [uri]::EscapeDataString([string]$repository.default_branch)
        $tree = Invoke-GitHubGet -Uri "https://api.github.com/repos/$name/git/trees/${encodedBranch}?recursive=1"
        $analysis = Get-RepositoryAnalysis -Repository $repository -Tree $tree
        $reviewContent = New-ReviewContent -Repository $repository -Analysis $analysis
        $existing = Get-ExistingBlobContent -RepositoryName $name -Tree $tree -Path $reviewPath
        $changed = -not $existing -or $existing.Content.TrimEnd() -ne $reviewContent.TrimEnd()
        $status = if ($changed) { '변경 필요' } else { '최신' }
        $detail = if ($changed) { "$reviewPath 갱신 대상" } else { '오늘 점검 보고서가 이미 최신' }

        if ($changed -and -not $DryRun -and $name -ne $maintenanceRepository) {
            $body = @{
                message = "docs: 저장소 상태 점검 $today [skip ci]"
                content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($reviewContent + "`n"))
                branch = [string]$repository.default_branch
                author = $author
                committer = $author
            }
            if ($existing) { $body.sha = $existing.Sha }
            Invoke-GitHubWrite -Method Put -Uri "https://api.github.com/repos/$name/contents/$reviewPath" -Body $body | Out-Null
            $status = '최신화 완료'
            $detail = "$reviewPath 갱신 및 기본 브랜치 커밋"
        }
        elseif ($name -eq $maintenanceRepository -and -not $DryRun) {
            $reviewContent + "`n" | Set-Content -LiteralPath $maintenanceReviewPath -Encoding utf8
            $status = '최신화 완료'
            $detail = '저장소 검토 문서와 전체 요약 보고서로 갱신'
        }

        $results.Add([pscustomobject]@{
            Name=$name; Private=[bool]$repository.private; Fork=$false; Status=$status; Detail=$detail
            Needed=@($analysis.Needed); Features=@($analysis.Features); Cleanup=@($analysis.Cleanup)
        })
    }
    catch {
        $statusCode = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        $message = if ($statusCode) { "HTTP $statusCode" } else { $_.Exception.Message }
        $results.Add([pscustomobject]@{ Name=$name; Private=[bool]$repository.private; Fork=$false; Status='실패'; Detail=$message; Needed=@(); Features=@(); Cleanup=@() })
    }
}

$publicResults = @($results | Where-Object { -not $_.Private })
$updated = @($results | Where-Object { $_.Status -eq '최신화 완료' })
$failed = @($results | Where-Object { $_.Status -eq '실패' })

$publicLines = [System.Collections.Generic.List[string]]::new()
$publicLines.Add('# GitHub 공개 저장소 유지관리 결과')
$publicLines.Add('')
$publicLines.Add("점검일: $today (Asia/Seoul)")
$publicLines.Add('')
$publicLines.Add("- 본인 소유 저장소: $($results.Count)개")
$publicLines.Add("- 최신화 완료: $($updated.Count)개")
$publicLines.Add("- 실패: $($failed.Count)개")
$publicLines.Add('')
$publicLines.Add('| 저장소 | 처리 결과 | 필요한 부분 | 추가 기능 제안 | 정리 후보 |')
$publicLines.Add('|---|---|---|---|---|')
foreach ($result in $publicResults) {
    $shortName = $result.Name.Split('/', 2)[1]
    $url = "https://github.com/$($result.Name)"
    $publicLines.Add("| [$shortName]($url) | $($result.Status): $($result.Detail) | $($result.Needed -join '<br>') | $($result.Features -join '<br>') | $($result.Cleanup -join '<br>') |")
}
$publicLines.Add('')
$publicLines.Add('> 비공개 저장소의 이름과 상세 결과는 공개 보고서에 기록하지 않습니다.')
$publicLines -join "`n" | Set-Content -LiteralPath $publicReportPath -Encoding utf8

$privateLines = [System.Collections.Generic.List[string]]::new()
$privateLines.Add('# 전체 GitHub 저장소 유지관리 결과')
$privateLines.Add('')
$privateLines.Add("점검일: $today (Asia/Seoul)")
$privateLines.Add('')
foreach ($result in $results) {
    $visibility = if ($result.Private) { '비공개' } else { '공개' }
    $privateLines.Add("## $($result.Name) ($visibility)")
    $privateLines.Add('')
    $privateLines.Add("- 처리: $($result.Status) — $($result.Detail)")
    if ($result.Needed.Count) { $privateLines.Add("- 필요한 부분: $($result.Needed -join '; ')") }
    if ($result.Features.Count) { $privateLines.Add("- 추가 기능: $($result.Features -join '; ')") }
    if ($result.Cleanup.Count) { $privateLines.Add("- 불필요·정리 후보: $($result.Cleanup -join '; ')") }
    $privateLines.Add('')
}
$privateLines -join "`n" | Set-Content -LiteralPath $privateReportPath -Encoding utf8

$state = @{}
foreach ($result in $results) {
    $state[$result.Name] = @{
        needed = @($result.Needed)
        features = @($result.Features)
        cleanup = @($result.Cleanup)
        status = $result.Status
    }
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8

if (-not $DryRun) {
    git -C $workspaceRoot config user.name ([string]$me.login)
    git -C $workspaceRoot config user.email "$($me.id)+$($me.login)@users.noreply.github.com"
    git -C $workspaceRoot add -- 'reports/repository-status.md' 'REPOSITORY_REVIEW.md'
    git -C $workspaceRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $workspaceRoot commit -m "docs: 전체 저장소 점검 $today [skip ci]"
        if ($LASTEXITCODE -ne 0) { throw '중앙 보고서 커밋에 실패했습니다.' }
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'Never'
        git -C $workspaceRoot push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw '중앙 보고서 푸시에 실패했습니다.' }
    }
}

[pscustomobject]@{
    Date = $today
    Owned = $results.Count
    Public = @($results | Where-Object { -not $_.Private }).Count
    Private = @($results | Where-Object { $_.Private }).Count
    Forks = @($results | Where-Object { $_.Fork }).Count
    Updated = $updated.Count
    Failed = $failed.Count
    DryRun = [bool]$DryRun
    FullReport = $privateReportPath
} | ConvertTo-Json -Compress

Remove-Variable token
