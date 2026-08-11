import AppKit
import UserNotifications

/// 간단한 사용자 알림. 앱 번들로 실행될 때만 시스템 알림을 사용하고,
/// 번들 없이(예: `swift run`) 실행될 때는 콘솔 로그로 안전하게 대체한다.
enum Notifier {
    private static var didRequestAuth = false

    static func show(title: String, body: String) {
        // 번들 식별자가 없으면 UNUserNotificationCenter 사용 시 크래시하므로 방어.
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[PortKiller] \(title) — \(body)")
            return
        }

        let center = UNUserNotificationCenter.current()
        if !didRequestAuth {
            didRequestAuth = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}
