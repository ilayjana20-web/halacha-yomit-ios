import Foundation

/// Reads/writes the small JSON blob the main app pushes into the App Group's shared
/// UserDefaults, and that the widget's own TimelineProvider reads back. This file must be
/// added to BOTH the main app target and the HalachaWidget extension target (check both
/// boxes under File Inspector > Target Membership in Xcode) — the main app writes via
/// HalachaWidgetBridge (its own Capacitor plugin), the widget only ever reads.
enum HalachaSharedData {
    static let appGroupId = "group.com.benishchai.halachayomit"
    private static let key = "halacha_widget_data"

    struct Snapshot: Codable {
        var streakCount: Int
        var streakBest: Int
        /// Whether the nightfall-aware "learning day" has already been credited today
        /// (mirrors the app's own learnedToday(), see www/index.html's streak section).
        var learnedToday: Bool
        /// "dark" or "light" — already resolved from the app's "auto" theme setting
        /// before it reaches here, so the widget never has to guess system appearance.
        var theme: String
        /// Today's parasha/festival title exactly as shown on the app's home screen
        /// (e.g. "פרשת בראשית", or a festival's own title such as "הלכות סוכות").
        var parashaHe: String

        static let placeholder = Snapshot(
            streakCount: 0, streakBest: 0, learnedToday: false,
            theme: "light", parashaHe: "הלכות הבן איש חי"
        )
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// Called by HalachaWidgetBridge (main app target only).
    static func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    /// Called by the widget's Provider (widget extension target only). Falls back to
    /// .placeholder if the app hasn't written anything yet (e.g. right after install,
    /// before the app has ever been opened).
    static func read() -> Snapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}
