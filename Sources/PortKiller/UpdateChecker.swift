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

    /// 현재 앱 버전 (Info.plist CFBundleShortVersionString)
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 새 버전이 있으면 (버전, 릴리즈 페이지 URL) 을 반환. 없으면 nil.
    /// 캐시된 최신 버전이 현재 버전보다 높을 때만 유효로 취급한다.
    var availableUpdate: (version: String, url: URL)? {
        guard let v = defaults.string(forKey: latestVersionKey),
              let urlString = defaults.string(forKey: latestURLKey),
              let url = URL(string: urlString),
              Self.isNewer(v, than: Self.currentVersion) else { return nil }
        return (v, url)
    }

    /// 확인 결과 (수동 확인 시 사용자에게 피드백을 주기 위한 값).
    enum CheckResult {
        case upToDate(current: String)
        case updateAvailable(version: String, url: URL)
        case failed
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
            if case .updateAvailable = result {
                DispatchQueue.main.async { onNewVersion?() }
            }
        }
    }

    /// 사용자가 직접 요청한 강제 확인 (간격 무시). 결과를 메인 스레드로 전달한다.
    func checkNow(completion: @escaping (CheckResult) -> Void) {
        fetchLatest { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 최신 릴리즈를 조회하고 결과를 캐시한다. (완료 콜백은 임의 스레드)
    private func fetchLatest(_ done: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            done(.failed); return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PortKiller", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self else { done(.failed); return }
            // 성공/실패와 무관하게 마지막 확인 시각을 갱신해 재시도 폭주를 막는다.
            self.defaults.set(Date(), forKey: self.lastCheckKey)

            guard let data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                done(.failed); return
            }

            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let htmlURL = (json["html_url"] as? String)
                ?? "https://github.com/\(self.repo)/releases/latest"

            self.defaults.set(version, forKey: self.latestVersionKey)
            self.defaults.set(htmlURL, forKey: self.latestURLKey)

            if Self.isNewer(version, than: Self.currentVersion),
               let url = URL(string: htmlURL) {
                done(.updateAvailable(version: version, url: url))
            } else {
                done(.upToDate(current: Self.currentVersion))
            }
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
