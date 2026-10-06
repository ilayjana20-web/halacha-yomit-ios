import WidgetKit

struct HalachaEntry: TimelineEntry {
    let date: Date
    let snapshot: HalachaSharedData.Snapshot
}

struct HalachaProvider: TimelineProvider {
    func placeholder(in context: Context) -> HalachaEntry {
        HalachaEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HalachaEntry) -> Void) {
        completion(HalachaEntry(date: Date(), snapshot: HalachaSharedData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HalachaEntry>) -> Void) {
        let entry = HalachaEntry(date: Date(), snapshot: HalachaSharedData.read())
        // The app itself calls WidgetCenter.reloadAllTimelines() the moment the streak or
        // today's parasha changes (see HalachaWidgetBridge), so this single entry only
        // needs a background-refresh safety net for the rare case the app isn't opened at
        // all — an hour out is a widget-friendly cadence that won't burn the refresh budget.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
