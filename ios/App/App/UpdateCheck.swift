import UIKit

/// Soft update prompt: on launch, asks the App Store (the same public iTunes Lookup API
/// Apple's own docs and most apps use — no server of ours involved) whether a newer version
/// than the one installed is live, and if so shows a plain native alert with a button straight
/// to the App Store page. This is NOT a push notification and never appears on the iOS home
/// screen/springboard — Apple doesn't let apps post arbitrary system alerts there; this is an
/// in-app prompt shown when the app itself is opened, the same pattern virtually every app with
/// a "there's a new version" nudge uses.
///
/// Fully optional and silent on failure (no network, Apple's endpoint down, bad JSON, etc.) —
/// this app works offline by design, and an update check must never get in the way of that or
/// show an error for something the user did nothing wrong to cause. At most once per day, so a
/// user who dismisses it isn't nagged again within the same day.
enum UpdateCheck {
    private static let lastShownKey = "hy_update_prompt_last_shown"

    static func checkAndPromptIfNeeded(from presenter: UIViewController) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }

        if let last = UserDefaults.standard.object(forKey: lastShownKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }

        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)") else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data else { return }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                let info = results.first,
                let storeVersion = info["version"] as? String,
                let storeURLString = info["trackViewUrl"] as? String,
                let storeURL = URL(string: storeURLString)
            else { return }

            guard isVersion(storeVersion, newerThan: currentVersion) else { return }

            DispatchQueue.main.async {
                UserDefaults.standard.set(Date(), forKey: lastShownKey)
                let alert = UIAlertController(
                    title: "גרסה חדשה זמינה",
                    message: "גרסה \(storeVersion) של הלכות הבן איש חי זמינה ב-App Store.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "עדכן עכשיו", style: .default) { _ in
                    UIApplication.shared.open(storeURL)
                })
                alert.addAction(UIAlertAction(title: "מאוחר יותר", style: .cancel))
                presenter.present(alert, animated: true)
            }
        }.resume()
    }

    /// Dotted-numeric version compare ("1.10.0" > "1.9.0"), not a string compare (which would
    /// get that case backwards) — missing trailing components count as 0 (so "1.2" == "1.2.0").
    private static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
