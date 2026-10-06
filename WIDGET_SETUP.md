# Adding the HalachaWidget target in Xcode

All the code is already written and committed:
- `ios/App/App/HalachaSharedData.swift` — shared App Group data model
- `ios/App/App/HalachaWidgetBridge.swift` — Capacitor plugin the web app calls
- `ios/App/HalachaWidget/Provider.swift`, `HalachaWidget.swift`, `HalachaWidgetBundle.swift` — the widget itself
- `www/index.html` (and `make_www.py`, for the next content sync) already call `syncWidgetData()`
  whenever the streak changes, the theme changes, or the home screen renders.

What's left needs Xcode's UI (creating a new target can't be done by editing files). ~15 minutes.

## 1. Create the widget extension target

1. Open `ios/App/App.xcworkspace` in Xcode.
2. File > New > Target… > **Widget Extension**.
3. Product Name: `HalachaWidget` (must match exactly — the code already assumes this name).
4. Uncheck "Include Live Activity" and "Include Configuration App Intent" (not needed yet).
5. When Xcode asks to activate the new scheme, choose **Cancel** (keep building the App scheme).
6. Xcode will have generated placeholder files (`HalachaWidget.swift`, `HalachaWidgetBundle.swift`,
   `AppIntent.swift`, an Assets.xcassets, Info.plist) inside a new `HalachaWidget/` group —
   **delete the generated `HalachaWidget.swift` and `HalachaWidgetBundle.swift` and `AppIntent.swift`**
   (keep Assets.xcassets and Info.plist).
7. Drag the three already-written files from `ios/App/HalachaWidget/` on disk
   (`Provider.swift`, `HalachaWidget.swift`, `HalachaWidgetBundle.swift`) into that same
   `HalachaWidget` group in Xcode — check "Copy items if needed" OFF (they're already in place),
   and make sure **Target Membership** is the `HalachaWidget` extension only.

## 2. Share `HalachaSharedData.swift` with the widget

1. Select `ios/App/App/HalachaSharedData.swift` in the Project Navigator.
2. In the File Inspector (right panel), under **Target Membership**, check the box for
   `HalachaWidget` too (it should already be checked for `App`). Now both targets compile it.

## 3. Add the App Group capability (both targets)

1. Select the **App** target > Signing & Capabilities > **+ Capability** > **App Groups**.
2. Click **+** and add: `group.com.benishchai.halachayomit`
3. Select the **HalachaWidget** target > Signing & Capabilities > **+ Capability** > **App Groups**.
4. Check the *same* group `group.com.benishchai.halachayomit` (don't create a second one).

Xcode writes the entitlements files and provisioning automatically — no manual plist editing.

## 4. Set the widget's deployment target

1. Select the **HalachaWidget** target > General > Minimum Deployments > iOS **17.0**.
   (The widget UI uses `containerBackground(_:for:)`, which needs iOS 17+. The main app can
   stay on its current 15.0 minimum — widgets simply won't be offered to older devices.)

## 5. Build & test

1. Select the **HalachaWidget** scheme, run it — Xcode will ask which widget size to preview;
   pick small or medium. You should see the placeholder snapshot ("הלכות הבן איש חי").
2. Switch back to the **App** scheme, run the app, mark a halacha as learned or toggle the
   theme, then long-press the Home Screen > + > search "הלכות הבן איש חי" > add the widget.
   It should show your real streak and today's parasha within a second or two (the app calls
   `WidgetCenter.shared.reloadAllTimelines()` on every sync).

## What the widget shows (100% real data, no placeholders)

- **Small**: streak count (🔥 N) or a book icon if no streak yet, + today's parasha/festival title.
- **Medium**: streak count + personal best (if higher) + whether today is already learned,
  alongside today's parasha/festival title.

Both sizes read from the exact same fields the app's own home screen and streak badge use
(`currentStreak()`, `bestStreak()`, `learnedToday()`, the `#wParasha` title, the resolved
light/dark theme) — nothing in the widget is invented or hardcoded.

## Ideas not yet built (from looking at Bet-El's widget for reference)

Bet-El's widget also tracks candle-lighting time/location (zmanim) for a Shabbat-countdown
widget. halacha-yomit-ios has no zmanim/location feature today, so that wasn't ported — only
you can say whether that's wanted here. Also not built yet, pending your go-ahead: Dynamic
Island / Live Activities (would need a concrete "live" event to track — e.g. a reading-in-
progress session), and the FAB / native-modal / feedback-form patterns Bet-El also has.
