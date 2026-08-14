import Foundation

public enum RelativeTime {
    public static func format(_ date: Date, now: Date = Date(), chinese: Bool) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 45 {
            return chinese ? "刚刚" : "Just now"
        }
        if delta < 3600 {
            let minutes = max(1, Int(delta / 60))
            return chinese ? "\(minutes) 分钟前" : "\(minutes)m"
        }
        if delta < 86_400 {
            let hours = max(1, Int(delta / 3600))
            return chinese ? "\(hours) 小时前" : "\(hours)h"
        }
        if Calendar.current.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            return chinese ? "昨天" : "Yesterday"
        }
        if delta < 86_400 * 7 {
            let days = max(1, Int(delta / 86_400))
            return chinese ? "\(days) 天前" : "\(days)d"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = chinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    public static func meta(_ session: SessionRecord, now: Date = Date(), chinese: Bool) -> String {
        "\(format(session.updatedAt, now: now, chinese: chinese)) · \(session.cwdName)"
    }
}
