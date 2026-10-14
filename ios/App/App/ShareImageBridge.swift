import Foundation
import UIKit
import Capacitor

/// `window.Capacitor.Plugins.ShareImageBridge.shareImages({images:[{name,data(base64 PNG)}], text})`
/// — presents the real iOS share sheet with the images as files. The Web Share API's `files`
/// support inside WKWebView is unreliable, so the web app's image shares go through here
/// (see `window.nativeShareImages` in make_www.py's CHROME_HEAD_BLOCK).
@objc(ShareImageBridge)
public class ShareImageBridge: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ShareImageBridge"
    public let jsName = "ShareImageBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "shareImages", returnType: CAPPluginReturnPromise)
    ]

    @objc func shareImages(_ call: CAPPluginCall) {
        guard let images = call.getArray("images") as? [[String: Any]], !images.isEmpty else {
            call.reject("no images")
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-images", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var urls: [URL] = []
        for (i, item) in images.enumerated() {
            guard let b64 = item["data"] as? String, let data = Data(base64Encoded: b64) else { continue }
            let rawName = (item["name"] as? String) ?? "image-\(i + 1).png"
            let name = rawName.replacingOccurrences(of: "/", with: "-")
            let url = dir.appendingPathComponent(name)
            do { try data.write(to: url); urls.append(url) } catch { continue }
        }
        guard !urls.isEmpty else {
            call.reject("could not write images")
            return
        }

        var items: [Any] = urls
        if let text = call.getString("text"), !text.isEmpty { items.append(text) }

        DispatchQueue.main.async { [weak self] in
            guard let self, let presenter = self.bridge?.viewController else {
                call.reject("no view controller")
                return
            }
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            vc.completionWithItemsHandler = { _, completed, _, _ in
                try? FileManager.default.removeItem(at: dir)
                call.resolve(["completed": completed])
            }
            if let pop = vc.popoverPresentationController {
                pop.sourceView = presenter.view
                pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            presenter.present(vc, animated: true)
        }
    }
}
