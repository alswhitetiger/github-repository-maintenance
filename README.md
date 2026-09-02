# GitHub 저장소 유지관리

평일마다 GitHub 연결 저장소를 가볍게 점검하고, 공개 저장소의 상태 요약을 실제 커밋으로 남기는 자동화입니다.

## 하는 일

- `alswhitetiger` 소유 저장소와 공동작업 저장소 목록 확인
- 소유한 일반 저장소의 README, 라이선스, `.gitignore`, 기본 브랜치, 최근 활동 점검
- 확인된 로컬 복제본은 작업 내용이 없을 때만 `fetch` 및 fast-forward 동기화
- 공개 저장소 결과는 `reports/repository-status.md`에 기록
- 비공개 및 공동작업 저장소의 상세 결과는 Git에 올리지 않고 `.local/`에만 기록
- 하루에 한 번만 의미 있는 상태 보고서 커밋 생성

## 실행

```powershell
pwsh -NoProfile -File .\Update-GitHubRepositories.ps1
```

Windows 자격 증명 관리자에 저장된 GitHub 로그인을 사용하며, 토큰은 파일에 저장하지 않습니다.
