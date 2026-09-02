# GitHub 저장소 유지관리

평일마다 본인 소유 GitHub 공개·비공개 저장소 전체를 점검하고, 저장소별 검토 문서를 실제 커밋으로 남기는 자동화입니다.

## 하는 일

- `alswhitetiger`가 소유한 공개·비공개 저장소 전체의 기본 브랜치 파일 트리 확인
- 저장소별 `REPOSITORY_REVIEW.md`에 필요한 구성, 추가 기능, 정리 후보 기록
- 일반 저장소는 기본 브랜치에 검토 문서를 커밋하고 포크는 업스트림 동기화만 시도
- 공개 결과는 `reports/repository-status.md`, 비공개 상세 결과는 `.local/`에 기록
- 커밋 메시지에 `[skip ci]`를 사용하여 불필요한 GitHub Actions 실행 최소화

## 실행

```powershell
pwsh -NoProfile -File .\Update-AllGitHubRepositories.ps1
```

Windows 자격 증명 관리자에 저장된 GitHub 로그인을 사용하며, 토큰은 파일에 저장하지 않습니다.
