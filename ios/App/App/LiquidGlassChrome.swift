import Foundation
import UIKit
import SwiftUI
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

    // Swipe-from-left-edge to go back while the reader is open (RTL: "back" is the left edge,
    // since the back chevron sits on the right — see the forced RTL semantic content below).
    // Not a UINavigationController here, so there's no interactivePopGestureRecognizer to get
    // this for free; only enabled while the reader's nav bar is actually showing.
    private lazy var backEdgeSwipe: UIScreenEdgePanGestureRecognizer = {
        let gr = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(backEdgeSwiped))
        gr.edges = .left
        gr.isEnabled = false   // only while the reader is open — see the "reader" case below
        return gr
    }()
    private var pullToRefresh: UIRefreshControl!

    override func viewDidLoad() {
        super.viewDidLoad()

        // The app is Hebrew-only — force RTL regardless of the device's own language/locale or
        // whether Info.plist's localizations are configured in a way iOS would otherwise detect
        // automatically. Without this, the native bars (back chevron, tab order, search field)
        // can render left-to-right even on a Hebrew-reading device.
        view.semanticContentAttribute = .forceRightToLeft

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
        setupWebViewScrollBehaviors()

        view.addGestureRecognizer(backEdgeSwipe)

        topToViewTop = capVC.view.topAnchor.constraint(equalTo: view.topAnchor)
        topToNavBar = capVC.view.topAnchor.constraint(equalTo: navBar.bottomAnchor)
        topToSearchBar = capVC.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor)
        updateContentInset()

        UpdateCheck.checkAndPromptIfNeeded(from: self)
    }

    /// Two small standard-iOS behaviors on the web content's own UIScrollView: the keyboard
    /// dismisses as soon as the user starts scrolling (rather than staying up over the
    /// content), and pulling down past the top reloads the page — both expected affordances on
    /// a native-feeling screen that a plain WKWebView doesn't give you for free.
    private func setupWebViewScrollBehaviors() {
        guard let scrollView = capVC.webView?.scrollView else { return }
        scrollView.keyboardDismissMode = .onDrag
        pullToRefresh = UIRefreshControl()
        pullToRefresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        scrollView.refreshControl = pullToRefresh
    }

    @objc private func backEdgeSwiped(_ gr: UIScreenEdgePanGestureRecognizer) {
        guard gr.state == .ended else { return }
        backTapped()
    }

    @objc private func pulledToRefresh() {
        capVC.webView?.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.pullToRefresh.endRefreshing()
        }
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
        tabBar.semanticContentAttribute = .forceRightToLeft
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
        navBar.semanticContentAttribute = .forceRightToLeft
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
        searchBar.semanticContentAttribute = .forceRightToLeft
        searchBar.delegate = self
        searchBar.placeholder = "חפשו מילה, נושא או ביטוי…"
        searchBar.searchBarStyle = .minimal   // lets the bar's own background show through, not a boxed field
        searchBar.returnKeyType = .search     // a real labeled keyboard action ("חיפוש") to dismiss it, not a bare return
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

    // MARK: Native Settings / Stats sheets — real UISheetPresentationController (Liquid Glass
    // sheet chrome on iOS 26, standard sheet material before it, same "genuine system
    // component, zero custom glass code" reasoning as the tab/nav/search bars) replacing the
    // HTML #settingsOverlay/#statsOverlay. See openSettings()/openStats() in www/index.html.

    private func presentSettings(_ body: [String: Any]) {
        let theme = (body["theme"] as? String) ?? "auto"
        let fszIdx = (body["fszIdx"] as? Int) ?? 1
        let fszMax = (body["fszMax"] as? Int) ?? 3
        let view = NativeSettingsView(
            initialTheme: theme, initialFszIdx: fszIdx, fszMax: fszMax,
            runJS: { [weak self] js in self?.runJS(js) },
            onClose: { [weak self] in self?.dismiss(animated: true) }
        )
        presentSheet(UIHostingController(rootView: view))
    }

    private func presentStats(_ body: [String: Any]) {
        func track(_ key: String) -> StatsTrack {
            let d = body[key] as? [String: Any]
            return StatsTrack(done: (d?["done"] as? Int) ?? 0, total: (d?["total"] as? Int) ?? 0)
        }
        let view = NativeStatsView(
            year1: track("year1"), year2: track("year2"), grand: track("grand"),
            onClose: { [weak self] in self?.dismiss(animated: true) }
        )
        presentSheet(UIHostingController(rootView: view))
    }

    // MARK: Native toast — a blurred capsule, the standard non-sheet pattern for a transient
    // message (iOS has no public system "toast" component, unlike tab/nav bars or sheets, so a
    // real UIBlurEffect material is the closest "genuine system material" available). Replaces
    // the HTML #toast — see showToast() in www/index.html.

    private var activeToast: UIView?

    private func presentToast(_ text: String) {
        activeToast?.removeFromSuperview()

        let blur = UIBlurEffect(style: .systemMaterial)
        let container = UIVisualEffectView(effect: blur)
        container.layer.cornerRadius = 20
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -18),
        ])

        view.addSubview(container)
        activeToast = container
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -20),
            container.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
        ])

        container.alpha = 0
        UIView.animate(withDuration: 0.22) { container.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            UIView.animate(withDuration: 0.22, animations: { container.alpha = 0 }) { _ in
                container.removeFromSuperview()
                if self.activeToast === container { self.activeToast = nil }
            }
        }
    }

    private func presentSheet(_ hostingVC: UIViewController) {
        hostingVC.modalPresentationStyle = .pageSheet
        if let sheet = hostingVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            // Opens straight to full height. At the half-height (.medium) detent, SwiftUI's
            // Form draws its grouped-list background as a translucent/lighter material rather
            // than the solid dark background it uses at full height — on a dark-themed device
            // this reads as a washed-out, low-contrast sheet until the user manually drags it
            // up. Starting at .large avoids ever showing that state; .medium stays in the
            // detents list so the user can still drag it down by hand if they want to.
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        present(hostingVC, animated: true)
    }

    // MARK: WKScriptMessageHandler — the JS side is CHROME_HEAD_BLOCK in make_www.py.
    // Message shapes:
    //   {type:"tab", id:"segWeek"|"segTopics"|"segPicker"|"segSearch"}
    //   {type:"reader", open:true, title:"..."} / {type:"reader", open:false}
    //   {type:"theme", dark:true|false}
    //   {type:"haptic", style:"light"|"success"}
    //   {type:"settings", open:true, theme:"...", fszIdx:N, fszMax:N}
    //   {type:"stats", open:true, year1:{done,total}, year2:{done,total}, grand:{done,total}}
    //   {type:"toast", text:"..."}

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
            backEdgeSwipe.isEnabled = open
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
        case "settings":
            if (body["open"] as? Bool) ?? false { presentSettings(body) }
        case "stats":
            if (body["open"] as? Bool) ?? false { presentStats(body) }
        case "toast":
            if let text = body["text"] as? String { presentToast(text) }
        default:
            break
        }
    }
}
