import Foundation

enum AppFormatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatStyle(style: .file)
            .locale(AppLanguage.current().locale)
            .format(value)
    }

    static func speed(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return L10n.tr("speed_per_second", bytes(Int64(value)))
    }

    static func remaining(bytes: Int64, speed: Double) -> String? {
        guard bytes > 0, speed > 1 else { return nil }
        let seconds = Int(Double(bytes) / speed)
        if seconds < 60 { return L10n.tr("remaining_seconds", max(1, seconds)) }
        if seconds < 3_600 { return L10n.tr("remaining_minutes", seconds / 60) }
        return L10n.tr("remaining_hours_minutes", seconds / 3_600, (seconds % 3_600) / 60)
    }

    static func releaseDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .locale(AppLanguage.current().locale)
        )
    }

    static func installTimestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM_dd_yy_HH_mm_ss"
        return formatter.string(from: date)
    }
}
