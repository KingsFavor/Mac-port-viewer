# 릴리즈 시크릿 구하는 법

CI가 **Apple 공증 빌드**를 만들고 **Homebrew tap**을 자동 갱신하려면 아래 시크릿이 필요합니다.
리포지토리 **Settings → Secrets and variables → Actions → New repository secret** 에 등록하세요.

> 시크릿이 없어도 CI는 실패하지 않습니다 — 서명/공증/탭 갱신 단계를 건너뛰고 "미공증" 빌드를 릴리즈합니다.

---

## A. 코드 서명 — Developer ID Application 인증서

> **전제**: [Apple Developer Program](https://developer.apple.com/programs/) 유료 멤버십($99/년). Developer ID 인증서는 팀의 **Account Holder** 권한만 발급할 수 있습니다.

### 1. 인증서 발급
1. <https://developer.apple.com/account/resources/certificates/list> 접속
2. **＋** → **Developer ID Application** 선택 → Continue
3. 안내에 따라 CSR(인증서 서명 요청) 업로드:
   - Mac의 **키체인 접근** 앱 → 메뉴 → 인증서 지원 → **인증 기관에서 인증서 요청**
   - 이메일 입력, "디스크에 저장" 선택 → `.certSigningRequest` 파일 생성 → 업로드
4. 발급된 `.cer` 다운로드 → 더블클릭해 키체인에 설치

### 2. `.p12` 로 내보내기 — ⚠️ **반드시 개인 키를 포함**해야 함
> `.p12` 에 **개인 키가 빠지면** CI 의 codesign 이 `0 valid identities found` 로 실패합니다.
> (이번에 발생한 원인이 이것입니다.)

1. **키체인 접근** → 로그인 키체인 → 왼쪽 카테고리에서 반드시 **"내 인증서(My Certificates)"** 선택
   - "인증서(Certificates)" 카테고리에서 내보내면 **개인 키가 빠집니다.**
2. `Developer ID Application: 이름 (팀ID)` 항목 왼쪽 **▶ 삼각형을 펼쳐** 그 아래 **개인 키가 있는지 확인**
   - 삼각형/개인 키가 **없으면** 이 Mac 에는 개인 키가 없는 것입니다 → CSR 을 만든(=인증서를 처음 발급받은) Mac 에서 내보내거나, 인증서를 폐기하고 재발급하세요.
3. 인증서 항목을 우클릭 → **내보내기** → 형식 `개인 정보 교환(.p12)` → 암호 지정 (→ `MACOS_CERTIFICATE_PASSWORD`)
4. **업로드 전 로컬 검증** (개인 키 포함 여부 확인):
   ```bash
   # 개인 키가 있으면 아래에 "PRIVATE KEY" 가 출력됨 (없으면 빈 출력 → 다시 내보내기)
   openssl pkcs12 -in Certificates.p12 -nocerts -nodes -passin pass:암호 2>/dev/null | grep -c "PRIVATE KEY"
   # 또는: 로컬 키체인에 아이덴티티가 보이는지
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
5. base64 인코딩:
   ```bash
   base64 -i Certificates.p12 | pbcopy   # 클립보드로 복사 → MACOS_CERTIFICATE_BASE64
   ```

| 시크릿 | 값 |
|--------|-----|
| `MACOS_CERTIFICATE_BASE64` | 위 2번에서 복사한 base64 (**개인 키 포함 필수**) |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 내보낼 때 지정한 암호 |
| `MACOS_SIGN_IDENTITY` | (선택) CI 가 키체인에서 아이덴티티를 자동 검출하므로 없어도 됨 |
| `KEYCHAIN_PASSWORD` | (선택) 아무 값. 미지정 시 자동 생성 |

---

## B. 공증 — App Store Connect API 키

`notarytool` 로 공증할 때 쓰는 **팀 API 키**입니다. (개인(Personal) 키는 공증에 사용 불가 — 반드시 **Team Key**, 권한은 **Developer** 이상)

### 발급
1. <https://appstoreconnect.apple.com/access/integrations/api> 접속
   (App Store Connect → **Users and Access → Integrations** 탭 → App Store Connect API → **Team Keys**)
2. **Generate API Key** (또는 ＋) → 이름 입력, Access = **Developer** → Generate
3. 생성된 키의 **`AuthKey_XXXXXXXXXX.p8` 파일 다운로드** — ⚠️ **단 한 번만** 받을 수 있음
4. 같은 화면에서 확인:
   - **Key ID**: 10자리 영숫자 → `NOTARY_KEY_ID`
   - **Issuer ID**: 페이지 상단의 UUID → `NOTARY_ISSUER_ID`
5. base64 인코딩:
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # → NOTARY_KEY_BASE64
   ```

| 시크릿 | 값 |
|--------|-----|
| `NOTARY_KEY_BASE64` | `.p8` 파일의 base64 |
| `NOTARY_KEY_ID` | Key ID (10자리) |
| `NOTARY_ISSUER_ID` | Issuer ID (UUID) |

---

## C. Homebrew tap 자동 갱신 토큰

릴리즈 때 CI가 별도 tap 리포(`KingsFavor/homebrew-tap`)의 Cask를 갱신하려면 push 권한 토큰이 필요합니다.

### 발급 (Fine-grained PAT 권장)
1. <https://github.com/settings/personal-access-tokens/new> 접속
2. **Repository access** → Only select repositories → `KingsFavor/homebrew-tap`
3. **Permissions** → Repository permissions → **Contents: Read and write**
4. Generate → 토큰 복사 → `TAP_GITHUB_TOKEN` 시크릿으로 등록

| 시크릿 | 값 |
|--------|-----|
| `TAP_GITHUB_TOKEN` | 위 fine-grained PAT |

> 이 토큰이 없으면 tap 자동 갱신만 건너뛰고, 릴리즈 자체는 정상 발행됩니다.

---

## 참고 문서
- [Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
- [notarytool man page](https://keith.github.io/xcode-man-pages/notarytool.1.html)
- [Customizing the notarization workflow (Apple)](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
