import Foundation
import Capacitor

/// `window.Capacitor.Plugins.CloudSyncBridge` — a tiny wrapper around iCloud key-value storage
/// (NSUbiquitousKeyValueStore) used to back up and sync the learner's progress, favourites and
/// streak across their devices. The web app owns the data format (a single JSON string, see the
/// "iCloud sync" section of blocks/features.html); this plugin only stores / returns it and tells
/// the page when another device changed it. Requires the iCloud "Key-value storage" capability
/// (com.apple.developer.ubiquity-kvstore-identifier in App.entitlements).
@objc(CloudSyncBridge)
public class CloudSyncBridge: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CloudSyncBridge"
    public let jsName = "CloudSyncBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getBlob", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setBlob", returnType: CAPPluginReturnPromise)
    ]

    private let store = NSUbiquitousKeyValueStore.default
    private let blobKey = "hy_progress_blob_v1"

    override public func load() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChangedExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        store.synchronize()
    }

    @objc private func storeChangedExternally(_ notification: Notification) {
        notifyListeners("cloudChanged", data: [:])
    }

    @objc func getBlob(_ call: CAPPluginCall) {
        store.synchronize()
        if let value = store.string(forKey: blobKey) {
            call.resolve(["value": value])
        } else {
            call.resolve(["value": NSNull()])
        }
    }

    @objc func setBlob(_ call: CAPPluginCall) {
        guard let value = call.getString("value") else {
            call.reject("value is required")
            return
        }
        store.set(value, forKey: blobKey)
        store.synchronize()
        call.resolve()
    }
}
