import SwiftUI
import WidgetKit

struct HalachaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: HalachaProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView
            default: smallView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(bg, for: .widget)
    }

    private var isDark: Bool { entry.snapshot.theme == "dark" }
    private var bg: Color { isDark ? Color(red: 0.08, green: 0.1, blue: 0.1) : Color(red: 0.96, green: 0.93, blue: 0.85) }
    private var ink: Color { isDark ? Color(white: 0.92) : Color(red: 0.17, green: 0.16, blue: 0.1) }
    private var gold: Color { Color(red: 0.75, green: 0.58, blue: 0.19) }
    private var good: Color { Color(red: 0.25, green: 0.52, blue: 0.54) }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.streakCount > 0 ? "🔥 \(entry.snapshot.streakCount)" : "📖")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(entry.snapshot.streakCount > 0 ? gold : ink)
            Text(entry.snapshot.streakCount > 0 ? "ימים ברצף" : "הלכות הבן איש חי")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink)
            Spacer()
            Text(entry.snapshot.parashaHe)
                .font(.system(size: 12))
                .foregroundStyle(ink.opacity(0.75))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot.streakCount > 0 ? "🔥 \(entry.snapshot.streakCount) ימים ברצף" : "עוד לא התחלתם רצף")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(entry.snapshot.streakCount > 0 ? gold : ink)
                if entry.snapshot.streakBest > entry.snapshot.streakCount {
                    Text("השיא שלך: \(entry.snapshot.streakBest)")
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.6))
                }
                Text(entry.snapshot.learnedToday ? "היום כבר למדתם ✓" : "עוד לא למדתם היום")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.snapshot.learnedToday ? good : ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("הלכה השבוע")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.55))
                Text(entry.snapshot.parashaHe)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct HalachaWidget: Widget {
    let kind: String = "HalachaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalachaProvider()) { entry in
            HalachaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("הלכות הבן איש חי")
        .description("הרצף שלכם והלכת השבוע, בלי לפתוח את האפליקציה.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
