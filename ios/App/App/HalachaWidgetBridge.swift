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
        CAPPluginMethod(name: "updateSharedData", returnType: CAPPluginReturnPromise)
    ]

    @objc func updateSharedData(_ call: CAPPluginCall) {
        let snapshot = HalachaSharedData.Snapshot(
            streakCount: call.getInt("streakCount") ?? 0,
            streakBest: call.getInt("streakBest") ?? 0,
            learnedToday: call.getBool("learnedToday") ?? false,
            theme: call.getString("theme") ?? "light",
            parashaHe: call.getString("parashaHe") ?? HalachaSharedData.Snapshot.placeholder.parashaHe
        )
        HalachaSharedData.write(snapshot)

        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        call.resolve()
    }
}
