import Foundation
import UIKit
import WebKit
import StoreKit
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
final class MainContainerViewController: UIViewController, WKScriptMessageHandler, UITabBarDelegate, UISearchBarDelegate {

    private let capVC = CAPBridgeViewController()
    private let tabBar = UITabBar()
    private let navBar = UINavigationBar()
    private let searchBar = UISearchBar()
    private var searchDebounce: DispatchWorkItem?

    // Exactly one of these three is ever active: the web content's top edge sits flush under
    // the Dynamic Island when no native bar is showing (full bleed — the web page's own
    // `env(safe-area-inset-top)` padding handles that case), or flush under whichever native
    // bar *is* showing. Without this, the nav/search bar would float on top of the web view at
    // a fixed height while the web page *also* reserves its own top padding for the exact same
    // bar — either double-padding (a gap under the native bar) or the bar simply painting over
    // the first ~50pt of the page, depending on which one wins the race.
    private var topToViewTop: NSLayoutConstraint!
    private var topToNavBar: NSLayoutConstraint!
    private var topToSearchBar: NSLayoutConstraint!

    // Order and ids match index.html's #segWeek/#segTopics/#segPicker/#segSearch exactly —
    // each tap below just clicks the corresponding existing web button, reusing all of its
    // existing click-handler logic unchanged.
    private let tabs: [(id: String, title: String, icon: String)] = [
        ("segWeek",   "השבוע",      "calendar"),
        ("segTopics", "לפי נושא",   "square.grid.2x2"),
        ("segPicker", "כל הפרשיות", "books.vertical"),
        ("segSearch", "חיפוש",      "magnifyingglass"),
    ]
    private let searchTabId = "segSearch"

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(capVC)
        view.addSubview(capVC.view)
        capVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
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
        setupSearchBar()

        topToViewTop = capVC.view.topAnchor.constraint(equalTo: view.topAnchor)
        topToNavBar = capVC.view.topAnchor.constraint(equalTo: navBar.bottomAnchor)
        topToSearchBar = capVC.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor)
        updateContentInset()

        UpdateCheck.checkAndPromptIfNeeded(from: self)
    }

    /// Activates exactly one of the three top constraints above, matching whichever bar (if
    /// any) is currently visible, so the web content starts right below it with no gap and no
    /// overlap. Call this every time `navBar.isHidden` or `searchBar.isHidden` changes.
    private func updateContentInset() {
        topToViewTop.isActive = false
        topToNavBar.isActive = false
        topToSearchBar.isActive = false
        (!navBar.isHidden ? topToNavBar : (!searchBar.isHidden ? topToSearchBar : topToViewTop)).isActive = true
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

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "חפשו מילה, נושא או ביטוי…"
        searchBar.searchBarStyle = .minimal   // lets the bar's own background show through, not a boxed field
        searchBar.isHidden = true             // only the search tab shows it — see the "tab" message below

        view.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func runJS(_ js: String) {
        capVC.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Safely embeds an arbitrary string (Hebrew text, quotes, anything) as a JS string literal
    /// by round-tripping it through JSON encoding rather than hand-escaping characters: encode
    /// [s] as JSON (always valid JS, hence valid as a snippet of a larger JS expression too),
    /// then strip the wrapping "[" / "]" to get just the string literal itself.
    private func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8), json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
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

    // MARK: UISearchBarDelegate — drives the existing #searchInput + its debounced "input"
    // listener through nativeSetSearchQuery (CHROME_HEAD_BLOCK in make_www.py) rather than
    // duplicating the search logic natively. Debounced the same way the web side already
    // debounces its own typing, so this isn't firing evaluateJavaScript on every keystroke.

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.runJS("if(window.nativeSetSearchQuery) window.nativeSetSearchQuery(\(self.jsStringLiteral(searchText)));")
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: WKScriptMessageHandler — the JS side is CHROME_HEAD_BLOCK in make_www.py.
    // Message shapes:
    //   {type:"tab", id:"segWeek"|"segTopics"|"segPicker"|"segSearch"}
    //   {type:"reader", open:true, title:"..."} / {type:"reader", open:false}
    //   {type:"theme", dark:true|false}
    //   {type:"haptic", style:"light"|"success"}

    private var isReaderOpen = false

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "tab":
            guard let id = body["id"] as? String, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
            tabBar.selectedItem = tabBar.items?[index]
            if !isReaderOpen {
                let showSearch = (id == searchTabId)
                searchBar.isHidden = !showSearch
                if !showSearch { searchBar.resignFirstResponder() }
                updateContentInset()
            }
        case "reader":
            let open = (body["open"] as? Bool) ?? false
            isReaderOpen = open
            navBar.items?.first?.title = (body["title"] as? String) ?? ""
            // The reader is a full-screen drill-in, not a tab destination, so it swaps the tab
            // bar (and the search bar, if that's where the reader was opened from) for the nav
            // bar rather than showing any of them at once.
            navBar.isHidden = !open
            tabBar.isHidden = open
            if open {
                searchBar.isHidden = true
            } else if let tag = tabBar.selectedItem?.tag, tabs[tag].id == searchTabId {
                searchBar.isHidden = false
            }
            updateContentInset()
            UIView.animate(withDuration: 0.22) {
                self.view.layoutIfNeeded()
            }
        case "theme":
            // UITabBar/UINavigationBar already track light/dark automatically via the system
            // appearance — the one case that alone wouldn't catch is the app's own in-page
            // theme choice ("light"/"dark" as an explicit override, independent of the system
            // setting, vs. "auto" which just follows it), so force it to match here.
            let dark = (body["dark"] as? Bool) ?? false
            overrideUserInterfaceStyle = dark ? .dark : .light
        case "haptic":
            let style = (body["style"] as? String) ?? "light"
            if style == "success" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // A streak milestone (the only thing that sends "success", not every mark-as-
                // learned tap) is a good, infrequent, genuinely-happy moment to ask for a
                // review — StoreKit itself throttles how often this can actually show (a system
                // limit, a few times a year), so there's no need to track that here too.
                if let scene = view.window?.windowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        default:
            break
        }
    }
}
