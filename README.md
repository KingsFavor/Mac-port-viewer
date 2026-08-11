# Port Killer

macOS 메뉴바에 상주하며 **개발 서버가 점유 중인 포트**를 한눈에 보여주고, 클릭 한 번으로 종료할 수 있는 개발자용 도구입니다.

시스템/백그라운드 데몬(rapportd, ControlCenter 등)과 에디터 헬퍼(VS Code, Figma 등)는 기본으로 숨겨, `node:3000`, `python:8000`, `postgres:5432` 같은 실제 내 서버만 깔끔하게 보여줍니다.

## 기능

- 🐟 메뉴바 아이콘 클릭 → 현재 LISTEN 중인 개발 포트 목록 (열 때마다 자동 새로고침)
- 🏠 / 🌐 로 루프백 전용 / 외부 노출 포트 구분
- **종료 (SIGTERM)** / **강제 종료 (SIGKILL)** 로 프로세스 정리
- 포트 번호 · PID 복사
- "시스템 · 백그라운드 포트 표시" 토글 (기본 숨김)
- Dock/앱 전환기에 뜨지 않는 순수 메뉴바 앱 (`LSUIElement`)

## 빌드 & 실행

```bash
# 앱 번들 생성 (릴리즈 빌드 + 코드사인)
./make_app.sh

# 실행
open "build/Port Killer.app"

# (선택) 설치
cp -R "build/Port Killer.app" /Applications/
```

실행하면 메뉴바 우측에 🐟(물고기) 아이콘이 나타납니다. 클릭해서 사용하세요.

### 개발 중 빠른 확인 (GUI 없이)

```bash
swift build
./.build/debug/PortKiller --list        # 개발 포트만
./.build/debug/PortKiller --list --all   # 시스템 포함 전체
```

## 동작 방식

- `lsof -nP +c0 -iTCP -sTCP:LISTEN -F` 로 LISTEN 중인 TCP 소켓을 수집하고, IPv4/IPv6 중복을 제거합니다.
- 프로세스 이름 denylist(`PortScanner.systemProcessKeywords`)로 시스템/벤더/에디터 상주 프로세스를 걸러냅니다. 숨기고 싶은 항목이 있으면 이 목록에 키워드를 추가하세요.
- 종료는 `kill(2)` 시스템 콜(SIGTERM/SIGKILL)을 직접 호출합니다. 다른 사용자 소유 프로세스는 권한 부족 안내가 표시됩니다.

## 자동 릴리즈 (CI)

`main` 브랜치에 푸시되면 GitHub Actions(`.github/workflows/release.yml`)가 자동으로:

1. 릴리즈 빌드 → `.app` 번들 생성
2. Developer ID 인증서로 코드 서명 (Hardened Runtime)
3. `notarytool` 로 Apple 공증 → `stapler` 로 티켓 스테이플
4. `.dmg` · `.zip` 생성 후 `v1.0.<run_number>` 태그로 GitHub Release 발행

서명/공증 시크릿이 없으면 서명 없는 빌드를 릴리즈하고 경고를 남깁니다(파이프라인은 실패하지 않음).

### 필요한 GitHub Secrets

Apple Developer 계정($99/년)이 있어야 하며, 리포지토리 **Settings → Secrets and variables → Actions** 에 등록합니다.

| Secret | 설명 | 얻는 법 |
|--------|------|---------|
| `MACOS_CERTIFICATE_BASE64` | Developer ID Application 인증서(.p12)를 base64 인코딩 | 키체인에서 인증서+개인키 내보내기 → `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | 위 .p12 내보낼 때 설정한 암호 | 직접 지정 |
| `MACOS_SIGN_IDENTITY` | 서명 아이덴티티 문자열 | 예: `Developer ID Application: 홍길동 (TEAMID123)` |
| `NOTARY_KEY_BASE64` | App Store Connect API 키(.p8)를 base64 인코딩 | [App Store Connect → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api) 에서 키 발급 후 `base64 -i AuthKey_XXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | API 키 ID | 위 페이지의 Key ID |
| `NOTARY_ISSUER_ID` | API 발급자(Issuer) ID | 위 페이지의 Issuer ID |
| `KEYCHAIN_PASSWORD` | (선택) 임시 키체인 암호 | 아무 값이나 지정 (미지정 시 자동 생성) |

> 인증서만 있고 공증 키가 없으면 서명만 하고 공증은 건너뜁니다.

## 구조

| 파일 | 역할 |
|------|------|
| `PortScanner.swift` | `lsof` 실행 · 파싱 · 시스템 포트 필터링 |
| `ProcessKiller.swift` | SIGTERM/SIGKILL 전송 및 결과 분류 |
| `AppDelegate.swift` | 메뉴바 상태 아이템 · 메뉴 구성 · 액션 |
| `Notifier.swift` | 종료 결과 시스템 알림 |
| `main.swift` | 진입점 · `--list` CLI 모드 |
