# Adding the HalachaWidget target in Xcode

All the code is already written and committed:
- `ios/App/App/HalachaSharedData.swift` — shared App Group data model (streak, theme, today's
  parasha, and now the next Shabbat candle-lighting time + label)
- `ios/App/App/HalachaWidgetBridge.swift` — Capacitor plugin the web app calls
- `ios/App/HalachaWidget/Provider.swift`, `HalachaWidget.swift`, `HalachaWidgetBundle.swift` —
  the streak/parasha widget (Home Screen small/medium + Lock Screen rectangular/circular/inline)
- `ios/App/HalachaWidget/HalachaCandleWidget.swift` — a second, separate widget: next Shabbat
  candle-lighting time (Home Screen small + the same three Lock Screen families, with a live
  self-updating countdown ring on the circular one)
- `www/index.html` (and `make_www.py`, for the next content sync) already call `syncWidgetData()`
  — including the real candle-lighting time (`nextCandleLightingInfo()`) — whenever the streak
  changes, the theme changes, or the home screen renders.

What's left needs Xcode's UI (creating a new target can't be done by editing files). ~15 minutes.

## 1. Create the widget extension target

1. Open `ios/App/App.xcworkspace` in Xcode.
2. File > New > Target… > **Widget Extension**.
3. Product Name: `HalachaWidget` (must match exactly — the code already assumes this name).
4. Uncheck "Include Live Activity" and "Include Configuration App Intent" (not used — no Live
   Activity/Dynamic Island in this pass, by request).
5. When Xcode asks to activate the new scheme, choose **Cancel** (keep building the App scheme).
6. Xcode will have generated placeholder files (`HalachaWidget.swift`, `HalachaWidgetBundle.swift`,
   `AppIntent.swift`, an Assets.xcassets, Info.plist) inside a new `HalachaWidget/` group —
   **delete the generated `HalachaWidget.swift` and `HalachaWidgetBundle.swift` and `AppIntent.swift`**
   (keep Assets.xcassets and Info.plist).
7. Drag the already-written files from `ios/App/HalachaWidget/` on disk
   (`Provider.swift`, `HalachaWidget.swift`, `HalachaWidgetBundle.swift`, `HalachaCandleWidget.swift`)
   into that same `HalachaWidget` group in Xcode — check "Copy items if needed" OFF (they're
   already in place), and make sure **Target Membership** is the `HalachaWidget` extension only.

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
   (The widget UI uses `containerBackground(_:for:)` and the Lock Screen accessory families,
   both iOS 17+. The main app can stay on its current 15.0 minimum — widgets simply won't be
   offered to older devices.)

## 5. Build & test

1. Select the **HalachaWidget** scheme, run it — Xcode will ask which widget to preview; there
   are now two kinds ("הלכות הבן איש חי" and "הדלקת נרות"), each offering Home Screen and Lock
   Screen sizes. Pick each to preview it.
2. Switch back to the **App** scheme, run the app, mark a halacha as learned or toggle the
   theme, then:
   - **Home Screen**: long-press > + > search "הלכות הבן איש חי" or "הדלקת נרות" > add.
   - **Lock Screen**: on the lock screen, long-press > Customize > Lock Screen > tap a widget
     slot under the clock > you'll see both widgets listed (rectangular, circular, inline).
     This is exactly the "tap or drag to add widget" gallery you're picturing from the
     Kosher Switch reference screenshot — add both.
   Both should show your real streak/parasha/candle time within a second or two (the app calls
   `WidgetCenter.shared.reloadAllTimelines()` on every sync).

## What the widgets show (100% real data, no placeholders)

**HalachaWidget** (streak + parasha):
- Home Screen small: streak count (🔥 N) or a book icon if no streak yet, + today's parasha title.
- Home Screen medium: streak + personal best + whether today is already learned, + parasha title.
- Lock Screen rectangular/circular/inline: streak count, same real data.

**HalachaCandleWidget** (candle lighting — new):
- Shows the next Shabbat candle-lighting time, computed from the app's own real sunset
  calculation (`_sunsetInstant` — already existed in `www/index.html` for the nightfall-aware
  "today", reused here) minus **18 minutes**, the standard default most Jewish calendars use
  when no community-specific custom is set (the same default the hebcal library — used by
  your other app — falls back to). **If your minhag uses a different number, tell me and I'll
  change the one constant** (`CANDLE_LIGHTING_MINS_BEFORE_SUNSET` in `www/index.html` /
  `make_www.py`).
- No location permission needed — same timezone→city table the app already uses.
- Lock Screen circular shows a **live, self-updating countdown ring** (iOS does this natively
  via `ProgressView(timerInterval:)` — no polling, no extra battery cost).
- Shabbat only for now — no Yom Tov candle times yet (the festival-week data to compute those
  already exists in the app; ask if you want this extended).

## Explicitly not built (by request)

- **Dynamic Island / Live Activity** — skipped per your instruction. The candle-lighting
  countdown would have been the natural fit if you change your mind later.
- **Settings/Stats screens as a native Liquid Glass sheet** — see the separate note sent in
  chat: this is a larger, different-shaped task (a real native rebuild of each control, not an
  additive file like these widgets) and deserves its own pass rather than a blind, unverified one.
