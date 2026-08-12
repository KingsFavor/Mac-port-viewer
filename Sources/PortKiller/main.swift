import AppKit

// 디버그/CLI 모드: `--list` 로 실행하면 스캔 결과만 출력하고 종료한다.
if CommandLine.arguments.contains("--list") {
    let all = PortScanner.scan()
    let showSystem = CommandLine.arguments.contains("--all")
    let visible = showSystem ? all : all.filter { !$0.isLikelySystem }
    print("총 \(all.count)개 LISTEN 포트 (표시 \(visible.count)개, 시스템 숨김 \(all.count - visible.count)개)")
    for p in visible {
        let scope = p.isLoopbackOnly ? "🏠" : "🌐"
        let started = p.startedAt.map { " · 시작 \(TimeFormat.relative($0))" } ?? ""
        print("  \(scope) \(p.port)\t\(p.command) (PID \(p.pid), \(p.user))\(started)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
