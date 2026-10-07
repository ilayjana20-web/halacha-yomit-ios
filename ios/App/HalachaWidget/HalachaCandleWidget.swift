import SwiftUI
import WidgetKit

/// Its own widget kind (separate from HalachaWidget's streak/parasha one), per the user's
/// own request for "a small widget, just about candle lighting" — same reasoning as the
/// user's other app's BetElCandleWidget. The time+label+weekday are computed app-side
/// (nextCandleLightingInfo() in www/index.html, covering both Shabbat and Yom Tov) and
/// synced through the same App Group snapshot as everything else — see HalachaSharedData.swift.
struct HalachaCandleEntry: TimelineEntry {
    let date: Date
    let theme: String
    let candleTime: Date?
    let candleLabel: String?
    let candleWeekday: String?
}

struct HalachaCandleProvider: TimelineProvider {
    func placeholder(in context: Context) -> HalachaCandleEntry {
        HalachaCandleEntry(date: Date(), theme: "light", candleTime: nil, candleLabel: "הדלקת נרות שבת", candleWeekday: "יום שישי")
    }

    func getSnapshot(in context: Context, completion: @escaping (HalachaCandleEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HalachaCandleEntry>) -> Void) {
        let entry = makeEntry()
        // Nothing more to compute locally once this candle time has passed — the widget just
        // keeps showing it until the app itself reopens and syncs the next one. Reload right
        // at that moment anyway (harmless no-op), and again after a day as a fallback in case
        // the app is opened but the OS is slow to deliver the reload signal.
        let now = Date()
        let fallback = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let reloadAfter = (entry.candleTime.map { $0 > now ? $0 : fallback }) ?? fallback
        completion(Timeline(entries: [entry], policy: .after(reloadAfter)))
    }

    private func makeEntry() -> HalachaCandleEntry {
        let s = HalachaSharedData.read()
        return HalachaCandleEntry(date: Date(), theme: s.theme, candleTime: s.candleTime, candleLabel: s.candleLabel, candleWeekday: s.candleWeekday)
    }
}

private struct HalachaCandleWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: HalachaCandleEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangularView
            default: smallView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                HalachaWidgetTheme.gradient(for: entry.theme)
            } else {
                Color.clear
            }
        }
    }

    private var label: String { entry.candleLabel ?? "הדלקת נרות שבת" }
    private var ink: Color { HalachaWidgetTheme.ink(for: entry.theme) }
    private var inkSoft: Color { HalachaWidgetTheme.inkSoft(for: entry.theme) }

    // MARK: Home Screen small — occasion name big, weekday + time below.
    private var smallView: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if let wd = entry.candleWeekday {
                Text(wd)
                    .font(.system(size: 11.5))
                    .foregroundStyle(inkSoft)
            }
            Spacer()
            if let candle = entry.candleTime {
                Text(candle, style: .time)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(HalachaWidgetTheme.gold)
            } else {
                Text("--:--")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lock Screen — label + time, single compact block.
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1).widgetAccentable()
            if let candle = entry.candleTime {
                Text(candle, style: .time).font(.system(size: 11.5))
            } else {
                Text("--:--").font(.system(size: 11.5))
            }
        }
    }
}

struct HalachaCandleWidget: Widget {
    let kind: String = "HalachaCandleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalachaCandleProvider()) { entry in
            HalachaCandleWidgetView(entry: entry)
        }
        .configurationDisplayName("הדלקת נרות")
        .description("זמן הדלקת הנרות הקרוב (שבת או חג), בלי לפתוח את האפליקציה.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
