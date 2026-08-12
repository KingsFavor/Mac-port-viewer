<p align="center">
  <img src="assets/logo.png" alt="Port Killer" width="160" />
</p>

<h1 align="center">Port Killer 🐟</h1>

macOS 메뉴바에 살면서 **개발 서버가 점유 중인 포트**를 한눈에 보여주고, 클릭 한 번으로 종료하는 도구입니다.

`rapportd`·ControlCenter 같은 시스템 데몬과 VS Code·Figma 같은 에디터 헬퍼는 알아서 숨기고, `node:3000`·`python:8000`·`postgres:5432` 처럼 **내가 띄운 서버만** 깔끔하게 보여줍니다. "그 포트 누가 잡고 있지?" 를 터미널 없이 해결하세요.

## 기능

- 🐟 메뉴바 아이콘 클릭 → 지금 LISTEN 중인 개발 포트 목록 (열 때마다 자동 새로고침)
- 🏠 / 🌐 로 루프백 전용 / 외부 노출 포트 구분
- **종료(SIGTERM)** / **강제 종료(SIGKILL)** 로 프로세스 정리
- 포트 번호·PID 클립보드 복사
- "시스템·백그라운드 포트 표시" 토글 (기본은 숨김)
- Dock 에 뜨지 않는 순수 메뉴바 앱

## 요구 사항

- macOS 13 (Ventura) 이상

## 설치

### Homebrew (권장)

```bash
brew install --cask kingsfavor/tap/port-killer
```

### 직접 내려받기

[**Releases**](https://github.com/KingsFavor/Mac-port-viewer/releases/latest) 에서 최신 `.dmg` 를 받아 **Port Killer** 를 Applications 폴더로 드래그하세요.

> 배포본은 Apple 공증(notarized)을 받아, 별도 허용 절차 없이 바로 실행됩니다.

## 사용법

1. 메뉴바 오른쪽의 🐟 아이콘을 클릭합니다.
2. 포트 목록에서 항목에 마우스를 올리면 하위 메뉴가 열립니다.
   - **종료(SIGTERM)** — 정상 종료 요청
   - **강제 종료(SIGKILL)** — 응답 없을 때 강제로
   - **포트 번호 / PID 복사**
3. 시스템·벤더 프로세스까지 보려면 **"시스템·백그라운드 포트 표시"** 를 켜세요.
4. 목록은 메뉴를 열 때마다 새로고침되며, `⌘R` 로도 갱신됩니다.

## 업데이트

앱이 하루에 한 번 조용히 최신 릴리즈를 확인합니다(백그라운드, 실패 시 무시). 새 버전이 있으면 메뉴 하단에 **"새 버전 X.Y.Z 사용 가능"** 항목이 나타납니다.

- **릴리즈 노트 보기** — 변경 사항 페이지를 엽니다.
- **업데이트 명령 복사 (brew)** — `brew upgrade --cask port-killer` 를 클립보드에 복사합니다.

앱이 스스로 교체하지는 않습니다. Homebrew 로 설치했다면 위 명령으로, 직접 내려받았다면 최신 `.dmg` 로 교체하세요.

## 제거

```bash
brew uninstall --cask kingsfavor/tap/port-killer
```

직접 설치한 경우 `Applications` 에서 **Port Killer** 를 휴지통으로 옮기면 됩니다. 로그인 항목·백그라운드 서비스로 등록하지 않으므로 다른 잔여물은 없습니다.

## 기여 · 빌드

소스로 빌드하거나 릴리즈 파이프라인을 다루는 방법은 개발 문서를 참고하세요.

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — 소스 빌드 · 프로젝트 구조 · 릴리즈(CI)
- [docs/SECRETS.md](docs/SECRETS.md) — 코드 서명 · 공증 · 배포 시크릿 발급법

## 라이선스

MIT
