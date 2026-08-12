import Foundation

/// 프로세스 시작 시각 표시용 포맷터. 메뉴(상대 시간)와 상세(절대 시각)에 공용.
enum TimeFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .full        // "2시간 전"
        return f
    }()

    private static let exactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true   // 오늘/어제는 "오늘 오전 9:15" 로
        return f
    }()

    /// "2시간 전", "방금 전" 같은 상대 표현.
    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "방금 전" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// "오늘 오전 9:15", "2026. 8. 11. 오후 3:20" 같은 절대 표현.
    static func exact(_ date: Date) -> String {
        exactFormatter.string(from: date)
    }
}
