# Native Settings / Stats / Toast — what's new and how to test it

No new Xcode target needed for any of this (unlike the widget) — every file is already
registered in `ios/App/App.xcodeproj/project.pbxproj` for the **App** target. Pull the branch,
open `ios/App/App.xcworkspace`, build and run. Nothing to drag into Xcode manually.

## What changed

**Settings (items 1–4 you asked for)** — `NativeSettingsView.swift`, presented as a real native
sheet (`UISheetPresentationController`, grabber, `.medium()`/`.large()` detents — genuine
Liquid Glass sheet chrome on iOS 26, standard sheet material before it) instead of the HTML
`#settingsOverlay`:
1. Theme segmented control (אוטומטי/בהיר/כהה)
2. Font size stepper (א־/א+), 4 levels
3. "שתפו את האפליקציה"
4. "שתפו קוד QR"

**Stats (item 5)** — `NativeStatsView.swift`, same native sheet, three animated progress rings
(שנה א׳/שנה ב׳/סה״כ). **Item 6 (the streak flame box) was intentionally left out** — you skipped
it when picking numbers, so it's still the HTML version's job for now; tell me if that was an
oversight and you want it too.

**Toast (item 7)** — `presentToast()` in `LiquidGlassChrome.swift`: a blurred capsule
(`UIBlurEffect(.systemMaterial)`) replacing the HTML `#toast`, same 2.2s duration.

**Not done (8, 9, 10)** — see "What I deliberately did not touch" below.

## How every action is wired (so you know exactly what to check)

Every native control calls back into the **exact same JS functions** the HTML version already
used and already works correctly (`setTheme()`, `applyFsz()`, `shareAppText()`, `shareAppQR()`)
via `capVC.webView?.evaluateJavaScript(...)` — the same mechanism the tab bar already uses to
click `#segWeek` etc. There is only one real implementation of each action; the native UI is a
thin remote control for it, not a second copy of the logic. This is specifically to avoid the
kind of bug you hit in "תמיד" (a second, separate implementation of font-size that didn't
actually work) — here there is no second implementation to get out of sync.

Data flows the other way (current theme, current font size index, the three ring counts) once,
at the moment the sheet opens — packaged into the `{type:"settings", ...}` / `{type:"stats",
...}` message JS already sends, and read in `LiquidGlassChrome.swift`'s
`presentSettings(_:)`/`presentStats(_:)`.

## Test checklist (please run this in the simulator — I have no way to run it myself)

**Settings:**
- [ ] Tap the gear icon → a native sheet slides up with a grabber (not the old HTML overlay).
- [ ] Tap "בהיר"/"כהה"/"אוטומטי" → the web content behind the sheet actually changes theme
      immediately (you'll see it change when you dismiss the sheet, or through the sheet's
      `.medium()` detent if the page is visible above it).
- [ ] Tap "א+" four times → button disables at the max step (גדול מאוד); tap "א־" four times →
      disables at the min step (קטן). Dismiss the sheet and open the reader — confirm text size
      actually changed.
- [ ] Tap "שתפו את האפליקציה" → the real iOS share sheet (or clipboard-copy toast) appears.
- [ ] Tap "שתפו קוד QR" → the real QR image share flow runs.
- [ ] Swipe the sheet down, or tap "סגור" → dismisses cleanly, app state unaffected.

**Stats:**
- [ ] Tap the stats icon → native sheet with 3 rings.
- [ ] Mark a halacha as learned, reopen stats → the rings' numbers actually increased (compare
      against what the old HTML version showed, if you can still trigger it on web/Android).
- [ ] With zero halachot marked, confirm the "עוד לא סימנת..." note still shows.

**Toast:**
- [ ] Trigger any `showToast(...)` call (e.g. the share-link-copied path on a device without
      the native share sheet) → a blurred capsule appears above the tab bar and fades out after
      ~2.2s, not the old flat HTML toast.

If ANY of these don't work exactly as described, it's a real bug in the Swift — tell me which
one and I'll fix it (I traced every call site by hand but, as discussed, I have no compiler or
simulator here to catch the kind of issue you ran into with Bet-El's font buttons).

## What I deliberately did not touch

- **Offline download banner (item 8)** — unlike everything above, this one is NOT
  fixed-position chrome; it sits inline in the normal page flow (only visible during the
  one-time initial content download, before any content is visible). Converting it to a native
  overlay means tracking where it currently sits on screen, which I can't verify without a
  simulator and is a rare, low-stakes screen to get subtly wrong. Flagging rather than guessing.
- **Wax-seal "mark as learned" control (item 9) and the favorite star (item 10)** — both sit
  *inside* the scrolling reader content, not in fixed screen-edge chrome like the tab/nav/search
  bars or these new sheets. A native version would have to track the control's on-screen
  position as the user scrolls, which is a meaningfully different (and riskier, less testable)
  problem than anything built so far. I'd like to scope this properly as its own pass rather
  than bolt it on here — let me know if you still want it and I'll think through the right
  approach (most likely: the web side reports the control's screen position on scroll, same
  direction as the existing bridge, but worth designing deliberately).
