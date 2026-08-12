import Foundation

/// GitHub Releases 에서 최신 버전을 조용히 확인한다.
///
/// UX 원칙:
/// - 백그라운드 비동기로만 확인하고, 실패하면 조용히 무시한다(에러 팝업 없음).
/// - 하루 한 번으로 제한해 네트워크/레이트리밋을 아끼고, 결과는 메뉴를 열 때만 노출한다.
/// - 앱이 스스로 교체하지 않는다(brew/직접설치 관리 대상). 감지 후 "안내"까지만.
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 릴리즈를 게시하는 리포지토리
    private let repo = "KingsFavor/Mac-port-viewer"
    /// 확인 간격 (24시간)
    private let checkInterval: TimeInterval = 60 * 60 * 24

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "update.lastCheck"
    private let latestVersionKey = "update.latestVersion"
    private let latestURLKey = "update.latestURL"

    /// Homebrew 업데이트 명령. `brew update` 를 포함해야 tap 캐시가 갱신되어
    /// "이미 최신 버전" 오판 없이 실제 새 버전으로 업그레이드된다.
    static let brewUpgradeCommand = "brew update && brew upgrade --cask port-killer"

    /// 실행 중인 프로세스의 버전. 앱 시작 시점의 Info.plist 값(메모리 캐시)이라,
    /// 실행 도중 brew 가 번들을 교체해도 이 값은 바뀌지 않는다.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 디스크에 설치된 .app 번들의 버전을 매번 새로 읽는다.
    /// brew 업그레이드로 번들이 교체되면 currentVersion 보다 높아진다 → "재실행 필요" 판별에 사용.
    static var installedVersion: String? {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist),
              let v = dict["CFBundleShortVersionString"] as? String else { return nil }
        return v
    }

    /// 확인/표시에 쓰는 실행 가능한 상태.
    enum CheckResult {
        case upToDate(current: String)                     // 최신
        case downloadable(version: String, url: URL)       // 새 버전 있음 (아직 미설치)
        case pendingRestart(version: String)               // 디스크엔 새 버전, 재실행하면 적용
        case failed                                        // 확인 실패
    }

    /// 현재 알려진 정보로 판단한 실행 가능한 상태 (네트워크 없이 캐시/디스크 기준).
    /// 메뉴·툴팁 표시에 사용한다.
    var actionableUpdate: CheckResult {
        resolvedResult(networkOK: true)
    }

    /// 디스크에 실행 중 버전보다 높은 번들이 설치돼 있으면 그 버전, 아니면 nil.
    /// (자동 재실행 판단용 — 네트워크 불필요)
    var pendingRestartVersion: String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        if let disk = Self.installedVersion, Self.isNewer(disk, than: Self.currentVersion) {
            return disk
        }
        return nil
    }

    /// 상태 판정: 디스크에 이미 새 버전이 있으면 재실행, 아니면 릴리즈 캐시로 다운로드 안내.
    private func resolvedResult(networkOK: Bool) -> CheckResult {
        let running = Self.currentVersion

        // 1) 디스크 번들이 실행 중 버전보다 높으면 → 재실행만 하면 적용됨
        if let disk = Self.installedVersion, Self.isNewer(disk, than: running) {
            return .pendingRestart(version: disk)
        }

        // 2) 릴리즈에 더 높은 버전이 있으면 → 업그레이드(다운로드) 안내
        if let v = defaults.string(forKey: latestVersionKey),
           let s = defaults.string(forKey: latestURLKey),
           let url = URL(string: s),
           Self.isNewer(v, than: running) {
            return .downloadable(version: v, url: url)
        }

        return networkOK ? .upToDate(current: running) : .failed
    }

    /// 간격이 지났을 때만 백그라운드에서 조용히 확인한다.
    /// 새 버전을 발견하면 `onNewVersion` 을 메인 스레드에서 호출한다.
    func checkIfDue(onNewVersion: (() -> Void)? = nil) {
        // 정식 번들로 실행될 때만 (swift run / CLI 모드에서는 skip)
        guard Bundle.main.bundleIdentifier != nil else { return }

        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < checkInterval {
            return
        }

        fetchLatest { result in
            switch result {
            case .downloadable, .pendingRestart:
                DispatchQueue.main.async { onNewVersion?() }
            case .upToDate, .failed:
                break
            }
        }
    }

    /// 사용자가 직접 요청한 강제 확인 (간격 무시). 결과를 메인 스레드로 전달한다.
    func checkNow(completion: @escaping (CheckResult) -> Void) {
        fetchLatest { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 최신 릴리즈를 조회해 캐시한 뒤, 디스크/캐시 기준의 실행 가능한 상태를 돌려준다.
    /// (완료 콜백은 임의 스레드)
    private func fetchLatest(_ done: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            done(resolvedResult(networkOK: false)); return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PortKiller", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self else { return }
            // 성공/실패와 무관하게 마지막 확인 시각을 갱신해 재시도 폭주를 막는다.
            self.defaults.set(Date(), forKey: self.lastCheckKey)

            guard let data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                // 네트워크 실패라도 디스크에 새 버전이 있으면 재실행 안내가 우선한다.
                done(self.resolvedResult(networkOK: false)); return
            }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let htmlURL = (json["html_url"] as? String)
                ?? "https://github.com/\(self.repo)/releases/latest"

            self.defaults.set(version, forKey: self.latestVersionKey)
            self.defaults.set(htmlURL, forKey: self.latestURLKey)

            done(self.resolvedResult(networkOK: true))
        }.resume()
    }

    /// 점(.)/하이픈(-) 으로 나눈 숫자 단위 비교. "1.2.0" > "1.10.0" 같은 오판을 피한다.
    /// 접두 `v` 는 호출 전에 제거된 상태를 가정한다.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { $0 == "." || $0 == "-" })
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
