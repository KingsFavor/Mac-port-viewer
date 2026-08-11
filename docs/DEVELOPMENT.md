# 개발 문서

Port Killer 를 소스에서 빌드하고, 동작 원리를 이해하고, 릴리즈를 내보내는 방법입니다.

## 요구 사항

- macOS 13+
- Swift 5.9+ (Xcode 15+ 권장)

## 소스에서 빌드

```bash
# .app 번들 생성 (릴리즈 빌드 + 아이콘 + ad-hoc 서명)
./make_app.sh

# 실행
open "build/Port Killer.app"

# (선택) 로컬 설치
cp -R "build/Port Killer.app" /Applications/
```

실행하면 메뉴바에 🐟 아이콘이 나타납니다. `make_app.sh` 는 릴리즈 바이너리를 빌드하고 `Tools/GenerateIcon.swift` 로 아이콘을 만들어 번들에 넣습니다.

### GUI 없이 빠르게 확인

스캐너/필터 로직만 확인할 때는 CLI 모드가 편합니다.

```bash
swift build
./.build/debug/PortKiller --list        # 개발 포트만 (필터 적용)
./.build/debug/PortKiller --list --all   # 시스템/벤더 포함 전체
```

## 동작 방식

- `lsof -nP +c0 -iTCP -sTCP:LISTEN -F` 로 LISTEN 중인 TCP 소켓을 수집하고, IPv4/IPv6 중복을 제거합니다.
  - `+c0` 로 명령어 이름 9자 잘림을 방지하고, `-F` 필드 모드로 안정적으로 파싱합니다.
- 프로세스 이름 denylist(`PortScanner.systemProcessKeywords`)로 시스템·벤더·에디터 상주 프로세스를 걸러냅니다.
  숨기거나 보이고 싶은 항목이 있으면 이 목록에 키워드를 추가/삭제하세요.
- 종료는 `kill(2)` 시스템 콜(SIGTERM/SIGKILL)을 직접 호출합니다. 다른 사용자 소유 프로세스는 권한 부족으로 안내됩니다.
- 메뉴바 전용 동작을 위해 `NSApp.setActivationPolicy(.accessory)` 를 사용하고, 번들에는 `LSUIElement` 를 설정합니다.

## 프로젝트 구조

| 경로 | 역할 |
|------|------|
| `Sources/PortKiller/PortScanner.swift` | `lsof` 실행 · 파싱 · 시스템 포트 필터링 |
| `Sources/PortKiller/ProcessKiller.swift` | SIGTERM/SIGKILL 전송 및 결과 분류 |
| `Sources/PortKiller/AppDelegate.swift` | 메뉴바 상태 아이템 · 메뉴 구성 · 액션 |
| `Sources/PortKiller/Notifier.swift` | 종료 결과 시스템 알림 |
| `Sources/PortKiller/main.swift` | 진입점 · `--list` CLI 모드 |
| `Tools/GenerateIcon.swift` | 물고기 앱 아이콘(.icns) 생성 |
| `Tools/GenerateDMGBackground.swift` | DMG 배경 이미지 생성 |
| `Tools/make_dmg.sh` | 배경/레이아웃 적용 설치 DMG 빌드 |
| `make_app.sh` | `.app` 번들 빌드 + 아이콘 + 서명 |
| `.github/workflows/release.yml` | 태그 기반 서명·공증·릴리즈·배포 파이프라인 |

## 릴리즈 (CI)

**`v*` 태그를 푸시하면** GitHub Actions(`.github/workflows/release.yml`)가 릴리즈를 자동으로 진행합니다.

```bash
git tag v1.2.0
git push origin v1.2.0
```

파이프라인 단계:

1. 태그 커밋을 릴리즈 빌드 → `.app` 번들 생성 (물고기 아이콘 포함)
2. Developer ID 인증서로 코드 서명 (Hardened Runtime) — 아이덴티티는 키체인에서 자동 검출
3. `notarytool` 로 Apple 공증 → `stapler` 로 티켓 스테이플
4. 배경/레이아웃이 입혀진 설치용 **`.dmg`** + **`.zip`** 생성
5. 직전 태그 이후 커밋으로 **릴리즈 노트 자동 생성** → 해당 태그로 GitHub Release 발행
6. **Homebrew tap**(`KingsFavor/homebrew-tap`)의 Cask 를 새 버전으로 자동 갱신

- 버전은 태그 이름을 그대로 따릅니다 (`v1.2.0` → `1.2.0`).
- 시크릿이 없으면 해당 단계(서명·공증·탭 갱신)만 건너뛰고 파이프라인은 계속 진행합니다.
- Actions 탭의 **Run workflow**(workflow_dispatch)로 수동 실행하면 릴리즈 없이 빌드만 검증합니다.

### 태그를 다시 눌러야 할 때

빌드 실패 등으로 같은 버전을 재시도하려면 (아직 릴리즈가 발행되지 않은 경우에만):

```bash
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0
git tag v1.2.0
git push origin v1.2.0
```

이미 릴리즈가 발행된 태그는 재사용하지 말고 다음 버전으로 올리세요.

### 필요한 GitHub Secrets

Apple Developer 계정($99/년)이 필요합니다. **어디서 어떻게 발급받는지**는 👉 [SECRETS.md](SECRETS.md) 에 단계별로 정리했습니다.

| 그룹 | Secret | 용도 |
|------|--------|------|
| 서명 | `MACOS_CERTIFICATE_BASE64`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID 코드 서명 (개인 키 포함 `.p12`) |
| 서명(선택) | `MACOS_SIGN_IDENTITY`, `KEYCHAIN_PASSWORD` | 아이덴티티 자동 검출/임시 키체인 (없어도 됨) |
| 공증 | `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect API 키로 공증 |
| 배포 | `TAP_GITHUB_TOKEN` | Homebrew tap 리포 자동 갱신 |
