import Foundation

/// 하나의 LISTEN 중인 포트를 점유한 프로세스 정보.
struct PortProcess: Identifiable, Hashable {
    let pid: Int32
    let command: String      // 전체 실행 파일 이름 (예: node, python3.11)
    let user: String         // 로그인 사용자 이름
    let port: Int            // 포트 번호
    let bindHost: String     // 바인딩된 호스트 (예: 127.0.0.1, *, ::1)

    var id: String { "\(pid)-\(port)" }

    /// 시스템/백그라운드 데몬으로 추정되는지 여부.
    /// 개발자가 직접 띄운 서버(node, python, docker 등)와 macOS/벤더 상주 프로세스를 구분한다.
    var isLikelySystem: Bool {
        let lower = command.lowercased()
        for keyword in PortScanner.systemProcessKeywords {
            if lower.contains(keyword) { return true }
        }
        return false
    }

    /// 루프백에만 바인딩되었는지 (127.0.0.1 / ::1 / localhost).
    var isLoopbackOnly: Bool {
        bindHost == "127.0.0.1" || bindHost == "::1" || bindHost == "localhost"
    }
}

/// `lsof` 를 실행해 현재 LISTEN 중인 TCP 포트를 수집한다.
enum PortScanner {
    /// 시스템/상주 프로세스로 간주해 기본 화면에서 숨길 이름 키워드 (소문자, 부분 일치).
    static let systemProcessKeywords: Set<String> = [
        // Apple / macOS 코어 데몬
        "rapportd", "sharingd", "controlce", "controlcenter", "remoted",
        "identityservices", "mdnsresponder", "launchd", "cupsd", "netbiosd",
        "apsd", "trustd", "secd", "coreaudiod", "bluetoothd", "airplay",
        "spotlight", "nsurlsession", "com.apple", "sshd", "screensharing",
        "wifiagent", "locationd", "nehelper", "usernoted", "distnoted",
        // 흔한 벤더 상주 에이전트 (개발 서버가 아님)
        "rapport", "logioptions", "logioptionsplus", "logi", "magicline",
        "veraport", "raonk", "astx", "delfino", "wizvera", "nprotect",
        "touchen", "anysign", "ahnlab", "v3", "dropbox", "onedrive",
        "google drive", "backupd", "adobe", "creative cloud",
        // 에디터/디자인 툴의 백그라운드 헬퍼 (직접 띄운 서버가 아닌 IPC 포트)
        "code helper", "figma", "slack helper", "electron helper",
        "chrome helper", "cursor helper",
    ]

    /// 현재 LISTEN 중인 TCP 포트 목록을 수집한다. (IPv4/IPv6 중복은 제거)
    static func scan() -> [PortProcess] {
        guard let raw = runLsof() else { return [] }

        var results: [String: PortProcess] = [:]

        var pid: Int32 = -1
        var command = ""
        var user = ""

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())

            switch tag {
            case "p":
                pid = Int32(value) ?? -1
                command = ""
                user = ""
            case "c":
                command = value
            case "L":
                user = value
            case "n":
                // 네트워크 이름: "host:port" 또는 "*:port"
                guard let (host, port) = parseHostPort(value) else { continue }
                let key = "\(pid)-\(port)"
                if results[key] == nil, pid > 0 {
                    results[key] = PortProcess(
                        pid: pid,
                        command: command,
                        user: user,
                        port: port,
                        bindHost: host
                    )
                }
            default:
                break
            }
        }

        return results.values.sorted {
            $0.port == $1.port ? $0.command < $1.command : $0.port < $1.port
        }
    }

    /// "127.0.0.1:3000", "*:8080", "[::1]:5432" 등을 (host, port) 로 파싱.
    private static func parseHostPort(_ name: String) -> (String, Int)? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let portPart = name[name.index(after: colon)...]
        guard let port = Int(portPart) else { return nil }
        var host = String(name[..<colon])
        // IPv6 대괄호 제거: [::1] -> ::1
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host, port)
    }

    private static func runLsof() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -nP: 이름/포트 변환 안 함(빠름), +c0: 명령어 이름 잘림 방지
        // -iTCP -sTCP:LISTEN: LISTEN 중인 TCP만, -F pcuLPn: 기계 판독 필드 출력
        process.arguments = ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcuLPn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
