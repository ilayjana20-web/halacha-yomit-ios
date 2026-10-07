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
    private let scrollTopCatcher = ScrollTopCatcher()

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
        setupScrollToTop()
        setupEdgeSwipeBack()
        setupPullToRefresh()
        setupNativePicker()

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

    /// Tapping the status bar scrolls the page to top. UIKit only honours that for a lone
    /// `scrollsToTop` scroll view, so the web view opts out and a hidden catcher takes over.
    private func setupScrollToTop() {
        capVC.webView?.scrollView.scrollsToTop = false
        scrollTopCatcher.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        scrollTopCatcher.onScrollToTop = { [weak self] in
            self?.runJS("window.betelScrollTop && window.betelScrollTop()")
        }
        view.addSubview(scrollTopCatcher)
    }

    // MARK: Pull-to-refresh - Apple's own UIRefreshControl (this site scrolls on the window, so the
    // WKWebView's scroll view really scrolls and the system control works). Refreshing = re-tapping the
    // active tab; turned off while the reader is open.
    private let refreshControl = UIRefreshControl()

    private func setupPullToRefresh() {
        refreshControl.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.runJS("var a=document.querySelector('.tab-btn.active'); if(a) a.click();")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.refreshControl.endRefreshing() }
        }, for: .valueChanged)
        capVC.webView?.scrollView.refreshControl = refreshControl
    }

    // MARK: Native "All parshiyot" picker (UICollectionView + glass cards) - see NativePickerView below.
    private let pickerView = NativePickerView()

    private func setupNativePicker() {
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        pickerView.isHidden = true
        pickerView.bottomInset = { [weak self] in (self?.tabBar.frame.height ?? 90) + 12 }
        pickerView.perform = { [weak self] js in self?.runJS(js) }
        view.insertSubview(pickerView, belowSubview: tabBar)
        NSLayoutConstraint.activate([
            pickerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pickerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func showNativePicker(_ raw: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let st = try? JSONDecoder().decode(NPState.self, from: data) else { return }
        pickerView.isHidden = false
        pickerView.apply(st)
    }

    private func hidePicker() { pickerView.isHidden = true }

    // MARK: Interactive edge-swipe back (page follows the finger, like UINavigationController)
    private var edgeCanGoBack = false

    private func setupEdgeSwipeBack() {
        capVC.webView?.scrollView.keyboardDismissMode = .interactive
        for edge in [UIRectEdge.left, UIRectEdge.right] {
            let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
            g.edges = edge
            view.addGestureRecognizer(g)
        }
    }

    @objc private func edgePanned(_ g: UIScreenEdgePanGestureRecognizer) {
        guard let web = capVC.webView else { return }
        let w = view.bounds.width
        let fromLeft = g.edges == .left
        let sign: CGFloat = fromLeft ? 1 : -1
        let dist = max(0, sign * g.translation(in: view).x)
        switch g.state {
        case .began:
            edgeCanGoBack = false
            web.evaluateJavaScript("window.betelCanGoBack ? window.betelCanGoBack() : false") { [weak self] r, _ in
                self?.edgeCanGoBack = (r as? Bool) ?? false
            }
        case .changed:
            let d = edgeCanGoBack ? dist : min(dist, 60) * 0.35
            web.transform = CGAffineTransform(translationX: sign * d, y: 0)
        case .ended, .cancelled, .failed:
            let vx = sign * g.velocity(in: view).x
            if g.state == .ended && edgeCanGoBack && (dist > w * 0.35 || vx > 800) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
                    web.transform = CGAffineTransform(translationX: sign * w, y: 0)
                    web.alpha = 0.6
                }, completion: { _ in
                    web.evaluateJavaScript("window.betelAppBack && window.betelAppBack()") { _, _ in
                        web.transform = CGAffineTransform(translationX: -sign * w * 0.25, y: 0)
                        UIView.animate(withDuration: 0.22, delay: 0.05, options: .curveEaseOut, animations: {
                            web.transform = .identity
                            web.alpha = 1
                        })
                    }
                })
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8,
                               initialSpringVelocity: 0.5, options: [], animations: { web.transform = .identity })
            }
        default: break
        }
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
        // Tapping the already-active tab scrolls to top first (iOS convention); otherwise a normal tap.
        capVC.webView?.evaluateJavaScript("window.betelTabReselect ? window.betelTabReselect('\(id)') : false") { [weak self] r, _ in
            if (r as? Bool) != true {
                self?.runJS("var b=document.getElementById('\(id)'); if(b) b.click();")
            }
        }
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

    /// System action sheet (UIAlertController): real Liquid Glass on iOS 26, classic sheet before.
    /// Reports the tapped action id (or "cancel") back via window.__betelActionDone(cb, id).
    private func presentActionSheet(_ body: [String: Any]) {
        let cb = body["cb"] as? String ?? ""
        let sheet = UIAlertController(title: body["title"] as? String, message: nil, preferredStyle: .actionSheet)
        func done(_ id: String) {
            runJS("window.__betelActionDone && window.__betelActionDone('\(cb)','\(id)')")
        }
        for a in (body["actions"] as? [[String: Any]]) ?? [] {
            let id = a["id"] as? String ?? ""
            sheet.addAction(UIAlertAction(title: a["title"] as? String ?? "", style: .default) { _ in done(id) })
        }
        sheet.addAction(UIAlertAction(title: body["cancel"] as? String ?? "Cancel", style: .cancel) { _ in done("cancel") })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        (presentedViewController ?? self).present(sheet, animated: true)
    }

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
            capVC.webView?.scrollView.refreshControl = open ? nil : refreshControl
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
        case "settings":
            if (body["open"] as? Bool) ?? false { presentSettings(body) }
        case "stats":
            if (body["open"] as? Bool) ?? false { presentStats(body) }
        case "picker":
            if (body["open"] as? Bool) ?? false, let st = body["state"] { showNativePicker(st) } else { hidePicker() }
        case "toast":
            if let text = body["text"] as? String { presentToast(text) }
        case "actionSheet":
            presentActionSheet(body)
        default:
            break
        }
    }
}


/// Invisible scroll view that receives the status-bar tap and forwards it to the web page.
final class ScrollTopCatcher: UIScrollView, UIScrollViewDelegate {
    var onScrollToTop: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        alpha = 0.02
        isUserInteractionEnabled = false
        scrollsToTop = true
        contentSize = CGSize(width: 2, height: 4000)
        contentOffset = CGPoint(x: 0, y: 2000)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        onScrollToTop?()
        return false
    }
}


// MARK: - Native picker (books -> parshiyot): real UICollectionView with Liquid Glass cards

struct NPState: Decodable {
    struct Tab: Decodable { let id: String; let label: String; let active: Bool }
    struct Banner: Decodable { let label: String; let num: String; let pct: Int; let foot: String; let footPct: String }
    struct Item: Decodable {
        let id: String; let ord: String; let title: String; let meta: String
        let pct: Int; let full: Bool; let untouched: Bool
    }
    let level: Int
    let tabs: [Tab]
    let backLabel: String?
    let banner: Banner?
    let items: [Item]
}

private let npGold = UIColor(red: 0.83, green: 0.69, blue: 0.37, alpha: 1)

private func npGlass() -> UIVisualEffectView {
    if #available(iOS 26.0, *) { return UIVisualEffectView(effect: UIGlassEffect()) }
    return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
}

final class NPHeaderCell: UICollectionViewCell {
    static let reuseId = "NPHeaderCell"
    private let stack = UIStackView()
    var onTab: ((String) -> Void)?
    var onBack: (() -> Void)?
    private var tabIds: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ st: NPState) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.semanticContentAttribute = .forceRightToLeft
        if !st.tabs.isEmpty {
            tabIds = st.tabs.map { $0.id }
            let seg = UISegmentedControl(items: st.tabs.map { $0.label })
            seg.selectedSegmentIndex = st.tabs.firstIndex(where: { $0.active }) ?? 0
            seg.selectedSegmentTintColor = npGold
            seg.setTitleTextAttributes([.foregroundColor: UIColor(white: 0.12, alpha: 1)], for: .selected)
            seg.addTarget(self, action: #selector(segChanged(_:)), for: .valueChanged)
            stack.addArrangedSubview(seg)
        }
        if let back = st.backLabel {
            let b = UIButton(type: .system)
            var c: UIButton.Configuration
            if #available(iOS 26.0, *) { c = UIButton.Configuration.glass() } else { c = UIButton.Configuration.tinted() }
            c.title = back
            c.image = UIImage(systemName: "chevron.right")
            c.imagePlacement = .leading
            c.imagePadding = 6
            c.cornerStyle = .capsule
            c.baseForegroundColor = npGold
            b.configuration = c
            b.contentHorizontalAlignment = .leading
            b.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
            let wrap = UIStackView(arrangedSubviews: [b, UIView()])
            wrap.axis = .horizontal
            stack.addArrangedSubview(wrap)
        }
        if let bn = st.banner { stack.addArrangedSubview(makeBanner(bn)) }
    }

    @objc private func segChanged(_ s: UISegmentedControl) {
        guard s.selectedSegmentIndex < tabIds.count else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onTab?(tabIds[s.selectedSegmentIndex])
    }

    private func makeBanner(_ bn: NPState.Banner) -> UIView {
        let card = npGlass()
        card.layer.cornerRadius = 24
        card.clipsToBounds = true
        func label(_ t: String, _ style: UIFont.TextStyle, _ weight: UIFont.Weight, _ color: UIColor) -> UILabel {
            let l = UILabel(); l.text = t; l.textColor = color; l.numberOfLines = 0
            l.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            l.adjustsFontForContentSizeCategory = true
            return l
        }
        let top = label(bn.label, .footnote, .semibold, .secondaryLabel)
        let num = label(bn.num, .title2, .bold, .label)
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progress = Float(bn.pct) / 100
        bar.progressTintColor = npGold
        bar.trackTintColor = UIColor.tertiarySystemFill
        let foot = UIStackView(arrangedSubviews: [label(bn.foot, .footnote, .regular, .secondaryLabel),
                                                  label(bn.footPct, .footnote, .semibold, npGold)])
        foot.axis = .horizontal
        let v = UIStackView(arrangedSubviews: [top, num, bar, foot])
        v.axis = .vertical
        v.spacing = 8
        v.semanticContentAttribute = .forceRightToLeft
        v.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 16),
            v.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -16),
            v.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
        ])
        return card
    }
}

final class NPTileCell: UICollectionViewCell {
    static let reuseId = "NPTileCell"
    private let glass = npGlass()
    private let ordLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let pctLabel = UILabel()
    private let bar = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.layer.cornerRadius = 22
        glass.clipsToBounds = true
        contentView.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: contentView.topAnchor),
            glass.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        ordLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        ordLabel.textColor = UIColor(white: 0.12, alpha: 1)
        ordLabel.textAlignment = .center
        ordLabel.backgroundColor = npGold
        ordLabel.layer.cornerRadius = 15
        ordLabel.clipsToBounds = true
        titleLabel.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        metaLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 2
        pctLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        pctLabel.textColor = npGold
        bar.progressTintColor = npGold
        bar.trackTintColor = UIColor.tertiarySystemFill
        for v in [ordLabel, titleLabel, metaLabel, pctLabel, bar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView.addSubview(v)
        }
        let c = glass.contentView
        NSLayoutConstraint.activate([
            ordLabel.widthAnchor.constraint(equalToConstant: 30), ordLabel.heightAnchor.constraint(equalToConstant: 30),
            ordLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            ordLabel.topAnchor.constraint(equalTo: c.topAnchor, constant: 14),
            pctLabel.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            pctLabel.centerYAnchor.constraint(equalTo: ordLabel.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: ordLabel.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: pctLabel.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: ordLabel.centerYAnchor),
            metaLabel.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            metaLabel.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            metaLabel.topAnchor.constraint(equalTo: ordLabel.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            bar.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ it: NPState.Item) {
        ordLabel.text = it.ord
        titleLabel.text = it.title
        metaLabel.text = it.meta
        pctLabel.text = it.full ? "✓" : "\(it.pct)%"
        bar.progress = Float(it.pct) / 100
        bar.progressTintColor = it.full ? UIColor.systemGreen : npGold
        glass.contentView.alpha = it.untouched ? 0.85 : 1
        accessibilityLabel = "\(it.title), \(it.meta)"
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }
}

final class NativePickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var perform: ((String) -> Void)?
    var bottomInset: (() -> CGFloat)?
    private var state: NPState?
    private let collectionView: UICollectionView

    override init(frame: CGRect) {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            if sectionIndex == 0 {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(200)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(200)), subitems: [item])
                let sec = NSCollectionLayoutSection(group: group)
                sec.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16)
                return sec
            }
            let two = (self?.state?.level ?? 1) == 2
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(two ? 0.5 : 1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .absolute(two ? 118 : 104)),
                subitem: item, count: two ? 2 : 1)
            if two { group.interItemSpacing = .fixed(12) }
            let sec = NSCollectionLayoutSection(group: group)
            sec.interGroupSpacing = 12
            sec.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16)
            return sec
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = .clear
        semanticContentAttribute = .forceRightToLeft
        collectionView.semanticContentAttribute = .forceRightToLeft
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(NPHeaderCell.self, forCellWithReuseIdentifier: NPHeaderCell.reuseId)
        collectionView.register(NPTileCell.self, forCellWithReuseIdentifier: NPTileCell.reuseId)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bottomInset?() ?? 100
        if abs(collectionView.contentInset.bottom - b) > 0.5 { collectionView.contentInset.bottom = b }
    }

    func apply(_ st: NPState) {
        let levelChanged = state?.level != st.level
        state = st
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
        if levelChanged { collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false) }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let st = state else { return 0 }
        return section == 0 ? 1 : st.items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let st = state else { return UICollectionViewCell() }
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NPHeaderCell.reuseId, for: indexPath) as! NPHeaderCell
            cell.configure(st)
            cell.onTab = { [weak self] id in self?.perform?("window.NativePickerHost.track('\(id)')") }
            cell.onBack = { [weak self] in self?.perform?("window.NativePickerHost.back()") }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NPTileCell.reuseId, for: indexPath) as! NPTileCell
        cell.configure(st.items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.section == 1, let st = state else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let id = st.items[indexPath.item].id.replacingOccurrences(of: "'", with: "")
        perform?("window.NativePickerHost.act('\(id)')")
    }
}
