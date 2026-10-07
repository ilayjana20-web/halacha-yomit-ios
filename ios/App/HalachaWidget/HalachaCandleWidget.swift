import SwiftUI
import WidgetKit

/// Its own widget kind (separate from HalachaWidget's streak/parasha one), per the user's
/// own request for "a small widget, just about candle lighting" — same reasoning as the
/// user's other app's BetElCandleWidget. The time+label are computed app-side
/// (nextCandleLightingInfo() in www/index.html) and synced through the same App Group
/// snapshot as everything else — see HalachaSharedData.swift.
struct HalachaCandleEntry: TimelineEntry {
    let date: Date
    let candleTime: Date?
    let candleLabel: String?
}

struct HalachaCandleProvider: TimelineProvider {
    func placeholder(in context: Context) -> HalachaCandleEntry {
        HalachaCandleEntry(date: Date(), candleTime: nil, candleLabel: "הדלקת נרות")
    }

    func getSnapshot(in context: Context, completion: @escaping (HalachaCandleEntry) -> Void) {
        let s = HalachaSharedData.read()
        completion(HalachaCandleEntry(date: Date(), candleTime: s.candleTime, candleLabel: s.candleLabel))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HalachaCandleEntry>) -> Void) {
        let s = HalachaSharedData.read()
        let entry = HalachaCandleEntry(date: Date(), candleTime: s.candleTime, candleLabel: s.candleLabel)
        // Nothing more to compute locally once this week's candle time has passed — the
        // widget just keeps showing it until the app itself reopens and syncs the next one.
        // Reload right at that moment anyway (harmless no-op), and again after a day as a
        // fallback in case the app is opened but the OS is slow to deliver the reload signal.
        let now = Date()
        let fallback = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let reloadAfter = (entry.candleTime.map { $0 > now ? $0 : fallback }) ?? fallback
        completion(Timeline(entries: [entry], policy: .after(reloadAfter)))
    }
}

private struct HalachaCandleWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: HalachaCandleEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circularView
            case .accessoryRectangular: rectangularView
            case .accessoryInline: inlineView
            default: smallView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                Color(red: 0.08, green: 0.1, blue: 0.1)
            } else {
                Color.clear
            }
        }
    }

    private var label: String { entry.candleLabel ?? "הדלקת נרות" }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.75, green: 0.58, blue: 0.19))
            Spacer()
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            if let candle = entry.candleTime {
                Text(candle, style: .time)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("--:--")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.headline).widgetAccentable()
            if let candle = entry.candleTime {
                Text(candle, style: .time).font(.caption)
            } else {
                Text("--:--").font(.caption)
            }
        }
    }

    @ViewBuilder
    private var circularView: some View {
        if let candle = entry.candleTime, candle > entry.date {
            // Live, self-updating countdown ring — no extra timeline entries needed, the
            // system redraws this continuously on its own.
            ProgressView(timerInterval: entry.date...candle, countsDown: true) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(candle, style: .timer)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            Image(systemName: "flame.fill")
                .widgetAccentable()
        }
    }

    private var inlineView: some View {
        if let candle = entry.candleTime {
            return Label {
                Text(candle, style: .time)
            } icon: {
                Image(systemName: "flame.fill")
            }
        } else {
            return Label(label, systemImage: "flame.fill")
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
        .description("זמן הדלקת הנרות הקרוב, בלי לפתוח את האפליקציה.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
