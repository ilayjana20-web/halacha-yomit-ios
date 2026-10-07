# Adding the HalachaWidget target in Xcode

All the code is already written and committed:
- `ios/App/App/HalachaSharedData.swift` — shared App Group data model (streak, theme, today's
  parasha, and the next candle-lighting time + occasion label + weekday)
- `ios/App/App/HalachaWidgetBridge.swift` — Capacitor plugin the web app calls
- `ios/App/HalachaWidget/Provider.swift`, `HalachaWidget.swift`, `HalachaWidgetBundle.swift` —
  the streak/parasha widget (Home Screen small/medium + Lock Screen rectangular + circular)
- `ios/App/HalachaWidget/HalachaCandleWidget.swift` — a second, separate widget: next candle
  lighting, Shabbat or Yom Tov (Home Screen small + Lock Screen rectangular)
- `www/index.html` (and `make_www.py`, for the next content sync) already call `syncWidgetData()`
  — including the real candle-lighting time (`nextCandleLightingInfo()`) — whenever the streak
  changes, the theme changes, or the home screen renders.

`ios/App/App.xcodeproj/project.pbxproj` has also been updated so `HalachaSharedData.swift` and
`HalachaWidgetBridge.swift` are already registered in the **App** target's build — you do not
need to manually add them to Xcode (only the widget-extension files below, since creating the
extension *target* itself is the one thing that can't be done by editing files).

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
     slot under the clock. There are now exactly two Lock Screen widgets per kind: a
     rectangular one (top row, spans two slots) and, for the streak widget only, a small
     circular one. The candle widget has no circular/inline Lock Screen variant (removed per
     your feedback — it was a plain time readout, not worth a slot of its own there).
   Both should show your real streak/parasha/candle time within a second or two (the app calls
   `WidgetCenter.shared.reloadAllTimelines()` on every sync).

## What changed in this redesign pass (per your feedback on the mockup)

- Real gradient backgrounds (not flat fill) and a shared "streak badge" capsule component —
  mirrors the actual design pattern from your other app's (still-in-progress) widget code.
- A real SF Symbol flame (`Image(systemName: "flame.fill")`) everywhere, never a 🔥 emoji
  glyph — this is what lets Lock Screen apply its own tint/vibrancy correctly ("אש אמיתי").
- Home Screen small: centered, not pinned to one corner.
- Home Screen medium: "היום כבר למדתם ✓" now appears **only** when actually true — nothing
  shows if you haven't learned yet today (no nagging negative message).
- Parasha display: a small "פרשת" label above the bare name (e.g. "פרשת" / "בראשית"), not the
  full "פרשת בראשית" repeated under its own "הלכה השבוע" label.
- Lock Screen rectangular (streak): single line, "N ימים ברצף" + real flame icon — the second
  (parasha) line and the extra bottom gap are gone.
- **Removed, per your explicit instruction**: both accessoryInline widgets (streak and candle),
  and the candle widget's accessoryCircular (the one that only showed a plain time, "18:24" —
  not a real countdown presentation worth keeping as its own Lock Screen slot). What remains on
  the Lock Screen: 2 rectangular widgets (streak, candle) + 1 circular (streak only).

## Candle lighting now also covers Yom Tov, not just Shabbat

Extended since the widget redesign: `nextCandleLightingInfo()` now reuses the app's own
existing festival-calendar data (`YOM_TOV_IL`/`YOM_TOV_DIA`, already used for the festival-week
feature) to also catch Yom Tov eves, the same brute-force civil-day Hebrew-date scan the app
already does elsewhere — no new library. The label always names the occasion
("הדלקת נרות שבת", "הדלקת נרות סוכות", "הדלקת נרות ראש השנה", …) and a separate field names the
real weekday candles are lit on ("יום שישי" for Shabbat — always Friday — or whichever weekday
a Yom Tov eve actually falls on). Still 18 minutes before sunset for both — **tell me if Yom
Tov should use a different number than Shabbat**, some communities do.

## Explicitly not built (by request)

- **Dynamic Island / Live Activity** — skipped per your instruction.
- **Settings/Stats screens as a native Liquid Glass sheet** — see the separate note sent in
  chat: this is a larger, different-shaped task (a real native rebuild of each control, not an
  additive file like these widgets) and deserves its own pass rather than a blind, unverified one.
