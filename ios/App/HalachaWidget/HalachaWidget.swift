import SwiftUI
import WidgetKit

/// Shared design tokens, mirroring the app's own gold/cream (light) and deep navy (dark)
/// palette — real SF Symbol flame everywhere (never an emoji glyph), so Lock Screen tinting
/// and vibrancy apply correctly, same reasoning as the user's other app's design tokens.
enum HalachaWidgetTheme {
    static func isDark(_ theme: String) -> Bool { theme == "dark" }

    static func gradient(for theme: String) -> LinearGradient {
        isDark(theme)
            ? LinearGradient(colors: [Color(red: 0.102, green: 0.125, blue: 0.125), Color(red: 0.047, green: 0.059, blue: 0.059)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.988, green: 0.973, blue: 0.925), Color(red: 0.918, green: 0.886, blue: 0.788)], startPoint: .top, endPoint: .bottom)
    }

    static func ink(for theme: String) -> Color {
        isDark(theme) ? Color(white: 0.94) : Color(red: 0.169, green: 0.165, blue: 0.102)
    }
    static func inkSoft(for theme: String) -> Color {
        isDark(theme) ? Color(white: 0.78) : Color(red: 0.169, green: 0.165, blue: 0.102).opacity(0.62)
    }
    static let gold = Color(red: 0.749, green: 0.584, blue: 0.188)
    static let goldBright = Color(red: 0.906, green: 0.773, blue: 0.431)
    static let good = Color(red: 0.247, green: 0.518, blue: 0.541)
    static func line(for theme: String) -> Color { gold.opacity(isDark(theme) ? 0.3 : 0.25) }
}

/// A flame SF Symbol + count in a rounded capsule — the one real "streak" element reused
/// across every size and every family, so it always reads the same.
private struct StreakBadge: View {
    let count: Int
    let large: Bool
    var theme: String = "light"
    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            Image(systemName: "flame.fill").font(.system(size: large ? 18 : 12))
            Text("\(count)").font(.system(size: large ? 20 : 13, weight: .bold))
        }
        .foregroundStyle(count > 0 ? HalachaWidgetTheme.gold : HalachaWidgetTheme.inkSoft(for: theme))
        .padding(.horizontal, large ? 14 : 9).padding(.vertical, large ? 7 : 4)
        .background(HalachaWidgetTheme.gold.opacity(0.15), in: Capsule())
    }
}

/// Strips the "פרשת " prefix the app's own #wParasha already includes for a plain week
/// (e.g. "פרשת בראשית" → "בראשית"), so the widget can show "פרשת" as its own label above
/// the bare name. A festival week's title (e.g. "הלכות סוכות") has no such prefix and is
/// shown as-is — the "פרשת" label above it is a small, accepted simplification.
private func bareParashaName(_ full: String) -> String {
    full.hasPrefix("פרשת ") ? String(full.dropFirst("פרשת ".count)) : full
}

struct HalachaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: HalachaProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView
            case .accessoryRectangular: rectangularView
            case .accessoryCircular: circularView
            default: smallView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                HalachaWidgetTheme.gradient(for: entry.snapshot.theme)
            } else {
                Color.clear
            }
        }
    }

    private var ink: Color { HalachaWidgetTheme.ink(for: entry.snapshot.theme) }
    private var inkSoft: Color { HalachaWidgetTheme.inkSoft(for: entry.snapshot.theme) }

    // MARK: Home Screen small — centered, not pinned to a corner.
    private var smallView: some View {
        VStack(spacing: 10) {
            Spacer()
            StreakBadge(count: entry.snapshot.streakCount, large: true, theme: entry.snapshot.theme)
            Spacer()
            VStack(spacing: 1) {
                Text("פרשת")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(inkSoft)
                Text(bareParashaName(entry.snapshot.parashaHe))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Home Screen medium
    private var mediumView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                StreakBadge(count: entry.snapshot.streakCount, large: true, theme: entry.snapshot.theme)
                if entry.snapshot.streakBest > entry.snapshot.streakCount {
                    Text("השיא שלך: \(entry.snapshot.streakBest)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(inkSoft)
                }
                if entry.snapshot.learnedToday {
                    Text("היום כבר למדתם ✓")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HalachaWidgetTheme.good)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(HalachaWidgetTheme.line(for: entry.snapshot.theme)).frame(width: 1).padding(.vertical, 10)

            VStack(spacing: 2) {
                Text("פרשת")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(inkSoft)
                Text(bareParashaName(entry.snapshot.parashaHe))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lock Screen — single line, real SF flame, no second line, no extra padding.
    private var rectangularView: some View {
        Label {
            Text("\(entry.snapshot.streakCount) ימים ברצף")
        } icon: {
            Image(systemName: "flame.fill")
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private var circularView: some View {
        Gauge(value: Double(min(entry.snapshot.streakCount, 30)), in: 0...30) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(entry.snapshot.streakCount)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
