import AppIntents

/// "Open today's halacha" — used by the Siri / Shortcuts / Spotlight app shortcut (see
/// HalachaShortcuts.swift) and by the interactive button in the Home Screen widget. Compiled
/// into BOTH the app and the widget extension. It only leaves a note in the shared App Group
/// ("pendingAction" = "today"); the app picks it up the next time it is in front
/// (HalachaWidgetBridge.takePendingAction, called by blocks/features.html) and opens the reader.
@available(iOS 16.0, *)
struct OpenTodayHalachaIntent: AppIntent {
    static var title: LocalizedStringResource = "הלכה של היום"
    static var description = IntentDescription("פותח את ההלכות של היום באפליקציה")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        HalachaSharedData.setPendingAction("today")
        return .result()
    }
}
