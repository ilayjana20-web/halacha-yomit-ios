import SwiftUI

/// Real native Liquid Glass sheet replacing the HTML #settingsOverlay on iOS (see
/// openSettings() in www/index.html / make_www.py). Presented via
/// MainContainerViewController.presentSettings(_:) in LiquidGlassChrome.swift.
///
/// This view holds NO state of its own beyond what it's given when opened — every action
/// (theme choice, font size, share) calls straight back into the exact same JS functions the
/// HTML version used (setTheme(), applyFsz(), shareAppText(), shareAppQR()), so there is only
/// ever one real implementation of each action and its persistence (localStorage stays the
/// single source of truth). `runJS` is the same `capVC.webView?.evaluateJavaScript` already
/// used by the tab/nav/search bars.
/// The reminder preferences as stored by the page (window.getReminderPrefs / setReminderPrefs in
/// blocks/features.html). Times are "HH:mm" strings.
struct ReminderPrefs {
    var morningOn: Bool
    var morning: String
    var eveningOn: Bool
    var evening: String
    static let defaults = ReminderPrefs(morningOn: true, morning: "07:30", eveningOn: true, evening: "20:30")
}

struct NativeSettingsView: View {
    let initialTheme: String       // "auto" | "light" | "dark"
    let initialFszIdx: Int         // 0...fszMax
    let fszMax: Int
    let runJS: (String) -> Void
    let onClose: () -> Void

    @State private var theme: String
    @State private var fszIdx: Int
    @State private var morningOn: Bool
    @State private var eveningOn: Bool
    @State private var morningTime: Date
    @State private var eveningTime: Date

    private static let fszLabels = ["קטן", "רגיל", "גדול", "גדול מאוד"]

    init(initialTheme: String, initialFszIdx: Int, fszMax: Int, initialReminders: ReminderPrefs = .defaults,
         runJS: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.initialTheme = initialTheme
        self.initialFszIdx = initialFszIdx
        self.fszMax = fszMax
        self.runJS = runJS
        self.onClose = onClose
        _theme = State(initialValue: initialTheme)
        _fszIdx = State(initialValue: initialFszIdx)
        _morningOn = State(initialValue: initialReminders.morningOn)
        _eveningOn = State(initialValue: initialReminders.eveningOn)
        _morningTime = State(initialValue: Self.date(fromHM: initialReminders.morning))
        _eveningTime = State(initialValue: Self.date(fromHM: initialReminders.evening))
    }

    private static func date(fromHM hm: String) -> Date {
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts.first ?? 7
        comps.minute = parts.count > 1 ? parts[1] : 30
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func hm(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private func pushReminders() {
        runJS("setReminderPrefs({morningOn:\(morningOn),morning:'\(Self.hm(from: morningTime))',eveningOn:\(eveningOn),evening:'\(Self.hm(from: eveningTime))'})")
    }

    private var fszLabel: String {
        let labels = Self.fszLabels
        return labels.indices.contains(fszIdx) ? labels[fszIdx] : labels[1]
    }

    var body: some View {
        // NavigationView (not NavigationStack, which needs iOS 16+) and the single-parameter
        // .onChange(of:perform:) (not the two-parameter iOS 17+ form) — this file compiles into
        // the main App target, whose deployment target is iOS 15, unlike the widget extension.
        NavigationView {
            Form {
                Section("מראה") {
                    Picker("", selection: $theme) {
                        Text("אוטומטי").tag("auto")
                        Text("בהיר").tag("light")
                        Text("כהה").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: theme) { newValue in
                        runJS("setTheme('\(newValue)')")
                    }
                }

                Section("גודל טקסט") {
                    HStack {
                        Button("א־") { step(-1) }
                            .disabled(fszIdx <= 0)
                        Spacer()
                        Text(fszLabel).foregroundStyle(.secondary)
                        Spacer()
                        Button("א+") { step(1) }
                            .disabled(fszIdx >= fszMax)
                    }
                    .buttonStyle(.bordered)
                }

                Section(header: Text("תזכורות"), footer: Text("תזכורת הערב לא נשלחת אם כבר למדתם היום.")) {
                    Toggle("תזכורת בוקר", isOn: $morningOn)
                        .onChange(of: morningOn) { _ in pushReminders() }
                    if morningOn {
                        DatePicker("שעה", selection: $morningTime, displayedComponents: .hourAndMinute)
                            .onChange(of: morningTime) { _ in pushReminders() }
                    }
                    Toggle("תזכורת ערב לשמירת הרצף", isOn: $eveningOn)
                        .onChange(of: eveningOn) { _ in pushReminders() }
                    if eveningOn {
                        DatePicker("שעה", selection: $eveningTime, displayedComponents: .hourAndMinute)
                            .onChange(of: eveningTime) { _ in pushReminders() }
                    }
                }

                Section("שיתוף") {
                    Button {
                        runJS("shareAppText()")
                    } label: {
                        Label("שתפו את האפליקציה", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        runJS("shareAppQR()")
                    } label: {
                        Label("שתפו קוד QR", systemImage: "qrcode")
                    }
                }
            }
            .navigationTitle("הגדרות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור", action: onClose)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func step(_ delta: Int) {
        let next = max(0, min(fszMax, fszIdx + delta))
        guard next != fszIdx else { return }
        fszIdx = next
        runJS("applyFsz(getFszIdx()\(delta > 0 ? "+1" : "-1"))")
    }
}
