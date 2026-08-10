import SwiftUI
import WidgetKit

// MARK: - タイムライン

struct GomiEntry: TimelineEntry {
    let date: Date
    let payload: GomiPayload?
}

struct GomiProvider: TimelineProvider {
    func placeholder(in context: Context) -> GomiEntry {
        GomiEntry(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GomiEntry) -> Void) {
        completion(GomiEntry(date: Date(), payload: GomiPayload.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GomiEntry>) -> Void) {
        let now = Date()
        let payload = GomiPayload.load()

        // 表示が切り替わる時刻にだけ更新する。
        //
        // 切り替わるのは「日付が変わったとき」と「出す期限を過ぎたとき」の2つ。
        // それ以外の時刻に起こしてもらっても表示は変わらないので、
        // 節目だけをタイムラインに並べる。
        var moments: [Date] = []
        let calendar = Calendar.current
        if let payload {
            for day in payload.days.prefix(14) {
                if let deadline = day.deadline, deadline > now {
                    moments.append(deadline.addingTimeInterval(1))
                }
                if let midnight = day.day, midnight > now {
                    moments.append(midnight)
                }
            }
        }
        // 何も無くても、翌日の0時には一度起こしてもらう。
        if moments.isEmpty,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            moments.append(tomorrow)
        }
        moments.sort()

        let entries = [GomiEntry(date: now, payload: payload)]
            + moments.prefix(20).map { GomiEntry(date: $0, payload: payload) }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - 表示

/// 案A：分別の色で全面を塗る。
///
/// ホーム画面に並んだアイコンの中で、色だけで「今日は何の日か」が分かるようにする。
/// アプリの中は情報を読ませる場所なのでクリーム地にしているが、ウィジェットは
/// 読ませる前に気づかせる場所なので、性格が違う。
struct GomiWidgetView: View {
    var entry: GomiEntry
    @Environment(\.widgetFamily) private var family

    private var featured: (day: GomiDay, isToday: Bool)? {
        entry.payload?.featured(at: entry.date)
    }

    private var accent: Color {
        featured?.day.resolvedCategories.first?.color ?? Color(white: 0.42)
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumBody
            default: smallBody
            }
        }
        .containerBackground(accent, for: .widget)
    }

    // MARK: 小 2×2

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            if let featured {
                Image(systemName: featured.day.resolvedCategories.first?.symbol ?? "trash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                categoryNames(featured.day, size: 19)
                deadlineText(featured.day)
            } else {
                emptyText
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 中 4×2

    private var mediumBody: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 4)
                if let featured {
                    HStack(spacing: 9) {
                        Image(systemName: featured.day.resolvedCategories.first?.symbol ?? "trash")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                        categoryNames(featured.day, size: 20)
                    }
                    deadlineText(featured.day)
                } else {
                    emptyText
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let payload = entry.payload, !upcoming(payload).isEmpty {
                Divider().overlay(Color.white.opacity(0.28))
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(upcoming(payload), id: \.date) { day in
                        upcomingRow(day)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 部品

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(featured?.isToday == true ? "今日" : "明日")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
            if let featured {
                Text(dateLabel(featured.day))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private func categoryNames(_ day: GomiDay, size: CGFloat) -> some View {
        // 複数の分別が重なる日は改行して全部出す。片方だけ見て出し忘れないように。
        VStack(alignment: .leading, spacing: 1) {
            ForEach(day.resolvedCategories, id: \.id) { category in
                Text(category.name)
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.top, 5)
    }

    private func deadlineText(_ day: GomiDay) -> some View {
        Text("朝\(day.deadlineHour):\(String(format: "%02d", day.deadlineMinute))までに出す")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.top, 2)
    }

    private var emptyText: some View {
        Text("収集は\nありません")
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(.white.opacity(0.82))
    }

    private func upcoming(_ payload: GomiPayload) -> [GomiDay] {
        guard let featuredDate = featured?.day.day else { return [] }
        return payload.days
            .filter { ($0.day ?? .distantPast) > featuredDate }
            .prefix(3)
            .map { $0 }
    }

    private func upcomingRow(_ day: GomiDay) -> some View {
        HStack(spacing: 8) {
            Text(shortDateLabel(day))
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 46, alignment: .leading)
            if let category = day.resolvedCategories.first {
                HStack(spacing: 4) {
                    Image(systemName: category.symbol).font(.system(size: 9))
                    Text(shortName(category))
                        .font(.system(size: 10.5, weight: .heavy))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
    }

    /// 一覧では幅が足りないので短い名前にする。アプリの shortLabel と揃えてある。
    private func shortName(_ category: GomiCategory) -> String {
        switch category.id {
        case "burnable": return "もえる"
        case "nonBurnable": return "もえない"
        case "hazardous": return "有害危険"
        case "recyclable1": return "資源1"
        case "recyclable2": return "資源2"
        default: return category.name
        }
    }

    private func dateLabel(_ day: GomiDay) -> String {
        guard let date = day.day else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter.string(from: date)
    }

    private func shortDateLabel(_ day: GomiDay) -> String {
        guard let date = day.day else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d E"
        return formatter.string(from: date)
    }
}

// MARK: - 定義

struct GomiWidget: Widget {
    let kind = "GomiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GomiProvider()) { entry in
            GomiWidgetView(entry: entry)
        }
        .configurationDisplayName("次のごみ収集")
        .description("明日は何ごみかを表示します。収集日の朝は、出す期限を過ぎるまで今日を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct GomiWidgetBundle: WidgetBundle {
    var body: some Widget {
        GomiWidget()
    }
}
