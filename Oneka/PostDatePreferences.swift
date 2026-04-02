import Foundation

enum HugoDateTimeFormat: String, CaseIterable, Identifiable {
    case dateOnly = "2006-01-02"
    case localDateTime = "2006-01-02T15:04:05"
    case rfc3339UTC = "2006-01-02T15:04:05Z"
    case rfc3339Offset = "2006-01-02T15:04:05-07:00"

    static let appStorageKey = "postDateTimeFormat"
    static let defaultFormat: HugoDateTimeFormat = .rfc3339Offset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateOnly:
            "Date only"
        case .localDateTime:
            "Local date and time"
        case .rfc3339UTC:
            "RFC 3339 (UTC)"
        case .rfc3339Offset:
            "RFC 3339 (time zone offset)"
        }
    }

    var sampleValue: String {
        switch self {
        case .dateOnly:
            "2026-03-20"
        case .localDateTime:
            "2026-03-20T14:30:45"
        case .rfc3339UTC:
            "2026-03-20T14:30:45Z"
        case .rfc3339Offset:
            "2026-03-20T14:30:45-05:00"
        }
    }

    var description: String {
        switch self {
        case .dateOnly:
            "Stores the calendar date without a time component."
        case .localDateTime:
            "Stores the date and time without an explicit time zone."
        case .rfc3339UTC:
            "Stores the date and time in UTC using the RFC 3339 format."
        case .rfc3339Offset:
            "Stores the date and time with the local UTC offset using the RFC 3339 format."
        }
    }

    static func from(appStorageValue value: String) -> HugoDateTimeFormat {
        HugoDateTimeFormat(rawValue: value) ?? defaultFormat
    }

    func format(_ date: Date) -> String {
        switch self {
        case .dateOnly:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case .localDateTime:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.string(from: date)
        case .rfc3339UTC:
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        case .rfc3339Offset:
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
    }
}

enum PostDatePreferences {
    static let autoUpdateLastModifiedKey = "autoUpdateLastModifiedOnSave"
    static let autoUpdateLastModifiedDefault = false
}
