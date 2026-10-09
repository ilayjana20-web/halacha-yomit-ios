import Foundation
import Capacitor
import WidgetKit

/// Exposes `window.Capacitor.Plugins.HalachaWidgetBridge.updateSharedData(...)` to the web
/// app (see make_www.py's CHROME_HEAD_BLOCK — window.syncWidgetData()). Writes into the App
/// Group's shared UserDefaults via HalachaSharedData, then asks WidgetKit to reload the
/// widget's timelines so the change shows up promptly rather than waiting for the next
/// scheduled reload.
@objc(HalachaWidgetBridge)
public class HalachaWidgetBridge: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HalachaWidgetBridge"
    public let jsName = "HalachaWidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "updateSharedData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takePendingAction", returnType: CAPPluginReturnPromise)
    ]

    /// Returns {action: "today"} once if a Siri shortcut / widget button asked the app to open
    /// today's halacha while it wasn't in front, otherwise {action: null}.
    @objc func takePendingAction(_ call: CAPPluginCall) {
        if let action = HalachaSharedData.takePendingAction() {
            call.resolve(["action": action])
        } else {
            call.resolve(["action": NSNull()])
        }
    }

    @objc func updateSharedData(_ call: CAPPluginCall) {
        let snapshot = HalachaSharedData.Snapshot(
            streakCount: call.getInt("streakCount") ?? 0,
            streakBest: call.getInt("streakBest") ?? 0,
            learnedToday: call.getBool("learnedToday") ?? false,
            theme: call.getString("theme") ?? "light",
            parashaHe: call.getString("parashaHe") ?? HalachaSharedData.Snapshot.placeholder.parashaHe,
            candleTimeISO: call.getString("candleTimeISO"),
            candleLabel: call.getString("candleLabel"),
            candleWeekday: call.getString("candleWeekday")
        )
        HalachaSharedData.write(snapshot)

        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        call.resolve()
    }
}
