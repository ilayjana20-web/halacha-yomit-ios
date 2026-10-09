import AppIntents

/// Registers the app shortcut so it shows up in Siri, the Shortcuts app and Spotlight search
/// without the user having to set anything up. Phrases must contain the app name; the Hebrew
/// shortcut title is what the user sees in Spotlight / Shortcuts.
@available(iOS 16.0, *)
struct HalachaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayHalachaIntent(),
            phrases: [
                "Open today's halacha in \(.applicationName)",
                "Study in \(.applicationName)",
                "Today in \(.applicationName)"
            ],
            shortTitle: "הלכה של היום",
            systemImageName: "book.fill"
        )
    }
}
