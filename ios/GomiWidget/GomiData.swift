import SwiftUI

/// App Groupの共有領域。アプリ側（AppDelegate.swift）が同じキーに書く。
enum GomiShared {
    static let suiteName = "group.io.github.ktakada42.saitamagomicalendar"
    static let payloadKey = "widget_payload"
}

/// 分別の見た目。5区分は変わらないので、ここだけはアプリと二重に持つ。
///
/// 収集日の計算はDartに一本化してあるが（WidgetPayload参照）、色と名前まで
/// 共有領域に載せると、データが増えるうえに配色を変えるたび書き直しが要る。
/// 区分そのものは市の制度なので、そう変わらない。
struct GomiCategory {
    let id: String
    let name: String
    let symbol: String
    let color: Color

    /// アプリの `lib/ui/category_style.dart` のライト側の色に合わせてある。
    static let all: [GomiCategory] = [
        .init(id: "burnable", name: "もえるごみ", symbol: "flame.fill",
              color: Color(red: 0.663, green: 0.220, blue: 0.047)),      // #A9380C
        .init(id: "nonBurnable", name: "もえないごみ", symbol: "hammer.fill",
              color: Color(red: 0.212, green: 0.310, blue: 0.780)),      // #364FC7
        .init(id: "hazardous", name: "有害危険ごみ", symbol: "exclamationmark.triangle.fill",
              color: Color(red: 0.651, green: 0.118, blue: 0.302)),      // #A61E4D
        .init(id: "recyclable1", name: "資源物1類", symbol: "arrow.3.trianglepath",
              color: Color(red: 0.027, green: 0.424, blue: 0.302)),      // #076C4D
        .init(id: "recyclable2", name: "資源物2類", symbol: "newspaper.fill",
              color: Color(red: 0.392, green: 0.220, blue: 0.902)),      // #6438E6
    ]

    static func find(_ id: String) -> GomiCategory? {
        all.first { $0.id == id }
    }
}

/// 収集のある1日。アプリが書き出したJSONをそのまま写したもの。
struct GomiDay: Decodable {
    let date: String          // "2026-08-10"
    let categories: [String]
    let deadlineHour: Int
    let deadlineMinute: Int

    /// 端末のカレンダーでの日付。時刻は持たない。
    var day: Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return Calendar.current.date(from: components)
    }

    /// この日の出す期限。
    var deadline: Date? {
        guard let day else { return nil }
        return Calendar.current.date(
            bySettingHour: deadlineHour, minute: deadlineMinute, second: 0, of: day
        )
    }

    var resolvedCategories: [GomiCategory] {
        categories.compactMap { GomiCategory.find($0) }
    }
}

struct GomiPayload: Decodable {
    let areaLabel: String
    let days: [GomiDay]

    static func load() -> GomiPayload? {
        guard
            let defaults = UserDefaults(suiteName: GomiShared.suiteName),
            let raw = defaults.string(forKey: GomiShared.payloadKey),
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(GomiPayload.self, from: data)
    }

    /// [now] の時点で大きく出すべき日。
    ///
    /// アプリのホーム画面と同じ規則にする。収集日の朝は、出す期限を過ぎるまで
    /// 「今日」を出す。まだ出しに行けるのに「明日」を出すと、その日の収集を逃す
    /// （lib/domain/collection_calendar.dart の featuredDay と対応）。
    func featured(at now: Date) -> (day: GomiDay, isToday: Bool)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        if let todayEntry = days.first(where: {
            guard let d = $0.day else { return false }
            return calendar.isDate(d, inSameDayAs: today)
        }), let deadline = todayEntry.deadline, now <= deadline {
            return (todayEntry, true)
        }

        // 期限を過ぎているか、今日は収集がない。次の収集日を出す。
        let next = days.first { day in
            guard let d = day.day else { return false }
            return d > today
        }
        return next.map { ($0, false) }
    }
}
