import UIKit
import WebKit
import Capacitor

/// `WKUserContentController.add(_:name:)` always retains its handler strongly. The "real"
/// handler here is the view controller that in turn owns the web view whose controller this
/// is — a textbook retain cycle without this weak-forwarding proxy in between.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Hosts the web content (`CAPBridgeViewController`) with real native Apple bar chrome on top:
/// a standalone `UITabBar` (bottom) mirroring the web app's 4 tabs, and a standalone
/// `UINavigationBar` (top) for the reader's back/title/share. Both are genuine system
/// components, not a hand-rolled blur view — Apple renders them with Liquid Glass
/// automatically on iOS 26 and with the standard bar material on everything back to this
/// app's iOS 15 minimum, with no custom visual-effect code needed on our side either way, and
/// no `#available(iOS 26, *)` branching: the OS decides the look, we just use the API.
///
/// index.html (see CHROME_HEAD_BLOCK in make_www.py, applied as part of the normal
/// `npx cap sync ios` / `make_www.py` content pipeline) hides its own HTML tab bar and the
/// reader's back/share buttons ON iOS ONLY and reports tab/reader/theme state here through
/// `window.webkit.messageHandlers.nativeChrome` — see `userContentController(_:didReceive:)`
/// below for the exact message shapes it sends. The website and a future Android build are
/// untouched: that gating lives entirely in index.html, keyed off `Capacitor.getPlatform()`.
final class MainContainerViewController: UIViewController, WKScriptMessageHandler, UITabBarDelegate {

    private let capVC = CAPBridgeViewController()
    private let tabBar = UITabBar()
    private let navBar = UINavigationBar()

    // Order and ids match index.html's #segWeek/#segTopics/#segPicker/#segSearch exactly —
    // each tap below just clicks the corresponding existing web button, reusing all of its
    // existing click-handler logic unchanged.
    private let tabs: [(id: String, title: String, icon: String)] = [
        ("segWeek",   "השבוע",      "calendar"),
        ("segTopics", "לפי נושא",   "square.grid.2x2"),
        ("segPicker", "כל הפרשיות", "books.vertical"),
        ("segSearch", "חיפוש",      "magnifyingglass"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(capVC)
        view.addSubview(capVC.view)
        capVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            capVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            capVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            capVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            capVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        capVC.didMove(toParent: self)

        // capVC.view was just accessed above, which forces CAPBridgeViewController's (final,
        // so we can't override it) loadView() to run synchronously — by this point capVC.webView
        // is already set.
        capVC.webView?.configuration.userContentController.add(
            WeakScriptMessageHandler(target: self), name: "nativeChrome")

        setupTabBar()
        setupNavBar()
    }

    private func setupTabBar() {
        tabBar.delegate = self
        tabBar.items = tabs.enumerated().map { index, tab in
            UITabBarItem(title: tab.title, image: UIImage(systemName: tab.icon), tag: index)
        }
        tabBar.selectedItem = tabBar.items?.first

        view.addSubview(tabBar)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupNavBar() {
        let item = UINavigationItem(title: "")
        item.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"), style: .plain,
            target: self, action: #selector(backTapped))
        item.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
            target: self, action: #selector(shareTapped))
        navBar.items = [item]
        navBar.isHidden = true   // only the reader screen shows it — see the "reader" message below

        view.addSubview(navBar)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func runJS(_ js: String) {
        capVC.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func backTapped() {
        runJS("var b=document.getElementById('rBack'); if(b) b.click();")
    }

    @objc private func shareTapped() {
        runJS("var b=document.getElementById('rShareBtn'); if(b) b.click();")
    }

    // MARK: UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let id = tabs[item.tag].id
        runJS("var b=document.getElementById('\(id)'); if(b) b.click();")
    }

    // MARK: WKScriptMessageHandler — the JS side is CHROME_HEAD_BLOCK in make_www.py.
    // Message shapes:
    //   {type:"tab", id:"segWeek"|"segTopics"|"segPicker"|"segSearch"}
    //   {type:"reader", open:true, title:"..."} / {type:"reader", open:false}
    //   {type:"theme", dark:true|false}

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "tab":
            guard let id = body["id"] as? String, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
            tabBar.selectedItem = tabBar.items?[index]
        case "reader":
            let open = (body["open"] as? Bool) ?? false
            navBar.items?.first?.title = (body["title"] as? String) ?? ""
            // The reader is a full-screen drill-in, not a tab destination, so it swaps the tab
            // bar for the nav bar rather than showing both at once.
            UIView.animate(withDuration: 0.22) {
                self.navBar.isHidden = !open
                self.tabBar.isHidden = open
            }
        case "theme":
            // UITabBar/UINavigationBar already track light/dark automatically via the system
            // appearance — the one case that alone wouldn't catch is the app's own in-page
            // theme choice ("light"/"dark" as an explicit override, independent of the system
            // setting, vs. "auto" which just follows it), so force it to match here.
            let dark = (body["dark"] as? Bool) ?? false
            overrideUserInterfaceStyle = dark ? .dark : .light
        default:
            break
        }
    }
}
