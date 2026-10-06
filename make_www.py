#!/usr/bin/env python3
"""Rebuild www/ (the web bundle the iOS app wraps) from the live site's static/ directory.

    python3 make_www.py            # ~/halacha_yomit/static  ->  ./www, then `npx cap sync ios`
    python3 make_www.py --no-sync  # just rebuild www/

What differs from the website (and WHY — see HANDOFF_README.md):
  1. sw.js: the activate-time cache wipe is scoped to this app's own "hy-cache-*" caches
     (`caches` is origin-wide; a blanket delete would hit a host site's caches).
  2. Firebase live counters ("מחוברים כעת" / "מכשירים") are KEPT — the owner wants the app
     counted together with the website. The website's code switches them off on localhost
     (dev copies inflated the counters); the native app's origin is capacitor://localhost,
     so the guard is widened to let a real Capacitor build through.
  3. A native-shell block is appended: the daily 07:30 local notification, plus a
     "don't lose your streak" evening reminder that only fires if today's halacha is
     still unmarked — both via @capacitor/local-notifications, the real native feature
     of the app (see the streak feature in index.html: learnedToday()/currentStreak()).
  4. A Content-Security-Policy meta tag is added (app bundle only — the live site doesn't
     get it from here). Defense-in-depth: the inline-script app still needs 'unsafe-inline'
     for script-src/style-src (everything is one bundled file, no nonces), so this mainly
     blocks exfiltration to new hosts and loading of any THIRD-PARTY script/host beyond the
     ones the app actually uses (fonts, Firebase, html2canvas CDN, Sefaria API) — not inline
     injection, which the app instead avoids by escaping everywhere user/content text is
     inserted (see esc()/hiTerms() in index.html).
  5. iOS-only native chrome bridge (CHROME_HEAD_BLOCK): on iOS (not Android, not the website),
     the HTML bottom tab bar, the reader's back/share buttons, and the search box are hidden
     in favor of native UIKit controls (Liquid Glass on iOS 26+, standard bar material on
     15-25) added by ios/App/App/LiquidGlassChrome.swift. index.html calls a tiny
     notifyNativeChrome() helper (defined in this block, safe to call unconditionally —
     no-ops on web/Android) from 5 existing spots (setActiveTab, enterReaderView, the #rBack
     handler, applyTheme, and the #rChk "mark as learned" handler) so the native bars/haptics
     stay in sync with tab/reader/theme state and fire on the right moments. See
     LiquidGlassChrome.swift for the native side and the message protocol it expects.
Everything else (content, CSS, versions) is byte-identical to the site, so a content update
is: deploy the site, run this script, bump CFBundleVersion in Xcode, archive.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.expanduser("~/halacha_yomit/static")
DST = os.path.join(HERE, "www")

NATIVE_BLOCK = r'''
<script>
/* Native shell integration (iOS/Android app build only — no-op on the plain website).
   Two real native features the App Store wants to see beyond a bare WebView, both fully
   offline (no server, no push infra):
   1. A fixed daily 07:30 notification that today's halacha is ready — scheduled once with a
      fixed id, so rescheduling on every launch just overwrites the same notification.
   2. A "don't lose your streak" evening reminder (id 2), rescheduled fresh on every launch:
      cancelled outright if today's learning is already logged (see learnedToday() in the page
      itself — index.html's streak feature), otherwise scheduled for this evening (or a few
      minutes from now if it's already past that time), worded from the current streak length. */
(function(){
  function whenCapacitorReady(cb){
    if(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) cb();
    else document.addEventListener("DOMContentLoaded", ()=>{
      if(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) cb();
    });
  }
  whenCapacitorReady(async function(){
    try{
      const { LocalNotifications } = window.Capacitor.Plugins;
      if(!LocalNotifications) return;
      const perm = await LocalNotifications.checkPermissions();
      if(perm.display !== "granted"){
        const req = await LocalNotifications.requestPermissions();
        if(req.display !== "granted") return;
      }
      await LocalNotifications.schedule({
        notifications: [{
          id: 1,
          title: "הלכה יומית",
          body: "ההלכה של היום מוכנה — לחצו לקריאה",
          schedule: { on: { hour: 7, minute: 30 }, repeats: true, allowWhileIdle: true }
        }]
      });

      await LocalNotifications.cancel({ notifications: [{ id: 2 }] });
      const alreadyLearnedToday = typeof learnedToday === "function" && learnedToday();
      if(!alreadyLearnedToday){
        const now = new Date();
        let at = new Date(); at.setHours(20, 30, 0, 0);
        if(at <= now) at = new Date(now.getTime() + 5 * 60 * 1000);   // already past 20:30 — nudge shortly instead
        const streak = typeof currentStreak === "function" ? currentStreak() : 0;
        const title = streak > 0 ? "🔥 אל תפסידו את הרצף" : "הלכה יומית";
        const body = streak > 0
          ? streak + " ימים ברצף — היום עוד לא למדתם! לחצו לשמור על הרצף"
          : "ההלכה של היום מחכה לכם — לחצו לקריאה";
        await LocalNotifications.schedule({
          notifications: [{ id: 2, title, body, schedule: { at, allowWhileIdle: true } }]
        });
      }
    }catch(e){ /* permission denied or plugin unavailable — app works fine without it */ }
  });
})();
</script>
'''

# A fixed, hand-enumerated allowlist — every external host index.html actually fetches from
# (checked against the live source each time this script runs the main() below, which will
# start failing replace_once calls the day a new external host is added and this list isn't).
# frame-ancestors is deliberately NOT included: it's a no-op (silently ignored by browsers,
# with a console warning) on a meta-tag CSP — it only works as a real HTTP response header,
# which a bundled static file never has — so it would be a false sense of protection.
CSP_META = ('<meta http-equiv="Content-Security-Policy" content="'
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' https://www.gstatic.com https://cdn.jsdelivr.net; "
            "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
            "font-src 'self' https://fonts.gstatic.com; "
            "img-src 'self' data: blob:; "
            "connect-src 'self' https://www.gstatic.com https://www.sefaria.org "
            "https://*.firebaseio.com wss://*.firebaseio.com; "
            "object-src 'none'; base-uri 'self'; form-action 'self'"
            '">')

# iOS-only: hides the HTML bottom tab bar + reader back/share buttons (native Swift bars take
# over, see LiquidGlassChrome.swift) and bridges 4 existing JS call sites to the native side via
# window.webkit.messageHandlers.nativeChrome. No-op on the website and on a future Android build
# (gated on Capacitor.getPlatform()==="ios", not just isNativePlatform()).
#
# Injected right after the early theme-bootstrap script in <head> (NOT at the end of <body>,
# where NATIVE_BLOCK lives): applyTheme(getTheme()) runs synchronously near the top of the
# page's main script, well before </body>, and it calls notifyNativeChrome() — so the function
# must already exist by then, or that's an uncaught "notifyNativeChrome is not defined" at
# page load. Defining it this early costs nothing (it's a 3-line function) and sidesteps any
# dependency on script execution order entirely.
CHROME_HEAD_BLOCK = r'''
<style>
/* Liquid Glass native chrome (iOS app only) replaces these — see LiquidGlassChrome.swift. */
html.ios-native-chrome .tabbar,
html.ios-native-chrome #rBack,
html.ios-native-chrome #rShareBtn,
html.ios-native-chrome .search-box{display:none !important;}
</style>
<script>
(function(){
  var isIOSNative = !!(window.Capacitor && window.Capacitor.getPlatform && window.Capacitor.getPlatform()==="ios");
  document.documentElement.classList.toggle("ios-native-chrome", isIOSNative);
  // Safe to call from anywhere, anytime, including synchronously during the earliest page
  // script — no-ops instantly on web/Android, or if the native side hasn't registered the
  // message handler yet for any reason.
  window.notifyNativeChrome = function(msg){
    try{
      if(isIOSNative && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeChrome){
        window.webkit.messageHandlers.nativeChrome.postMessage(msg);
      }
    }catch(e){}
  };
  // The other direction: the native UISearchBar (search tab only, see LiquidGlassChrome.swift)
  // drives the existing #searchInput + its debounced "input" listener, rather than
  // duplicating the search-triggering logic natively.
  window.nativeSetSearchQuery = function(q){
    var el = document.getElementById("searchInput");
    if(el){ el.value = q; el.dispatchEvent(new Event("input")); }
  };
})();
</script>
'''


def replace_once(text: str, old: str, new: str, what: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{what}: expected exactly one match, found {n} — the site changed; update make_www.py")
    return text.replace(old, new)


def main() -> int:
    if not os.path.isdir(SRC):
        raise SystemExit(f"missing {SRC}")
    if os.path.isdir(DST):
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST, ignore=shutil.ignore_patterns(".DS_Store"))

    # 1. sw.js — prefix-scoped cache cleanup
    p = os.path.join(DST, "sw.js")
    sw = open(p, encoding="utf-8").read()
    sw = replace_once(sw, 'const CACHE_NAME = "hy-cache-" + CACHE_VERSION;',
                      'const CACHE_PREFIX = "hy-cache-";\nconst CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;', "sw.js CACHE_NAME")
    sw = replace_once(sw, 'await Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)));',
                      '// Only ever drop OUR OWN old caches. `caches` is shared across the whole origin, so a\n'
                      '    // blanket delete would wipe the host site\'s caches when this app is embedded in it.\n'
                      '    await Promise.all(\n'
                      '      names.filter((n) => n.startsWith(CACHE_PREFIX) && n !== CACHE_NAME).map((n) => caches.delete(n))\n'
                      '    );', "sw.js cache delete")
    open(p, "w", encoding="utf-8").write(sw)

    # 2. index.html — Firebase counters stay on inside the native app; 3. native block;
    #    4. CSP meta tag; 5. iOS native-chrome bridge (4 call sites + appended block)
    p = os.path.join(DST, "index.html")
    html = open(p, encoding="utf-8").read()
    html = replace_once(html, "  if(IS_LOCAL) return;                       // chips just stay at their \"–\" placeholder",
                        "  // The native app runs from capacitor://localhost — a real user, not a dev copy — so it\n"
                        "  // is counted together with the website (owner's decision, 2026-09-23).\n"
                        "  const IS_NATIVE_APP = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());\n"
                        "  if(IS_LOCAL && !IS_NATIVE_APP) return;     // chips just stay at their \"–\" placeholder",
                        "index.html IS_LOCAL guard")
    html = replace_once(html, '<meta charset="UTF-8">',
                        '<meta charset="UTF-8">\n' + CSP_META, "index.html CSP meta")
    html = replace_once(html,
                        '  if(m) m.setAttribute("content", dark ? "#10161A" : "#E3F1F2");\n'
                        '})();\n'
                        '</script>\n'
                        '<link rel="manifest" href="manifest.json">',
                        '  if(m) m.setAttribute("content", dark ? "#10161A" : "#E3F1F2");\n'
                        '})();\n'
                        '</script>\n'
                        + CHROME_HEAD_BLOCK +
                        '<link rel="manifest" href="manifest.json">',
                        "index.html chrome head block")
    html = replace_once(html,
                        '  ["segWeek","segTopics","segPicker","segSearch"].forEach(x=>document.getElementById(x).classList.toggle("active",x===id));\n'
                        '}',
                        '  ["segWeek","segTopics","segPicker","segSearch"].forEach(x=>document.getElementById(x).classList.toggle("active",x===id));\n'
                        '  notifyNativeChrome({type:"tab", id:id});\n'
                        '}', "index.html setActiveTab bridge")
    html = replace_once(html, "function enterReaderView(title){",
                        "function enterReaderView(title){\n"
                        '  notifyNativeChrome({type:"reader", open:true, title:title||""});',
                        "index.html enterReaderView bridge")
    html = replace_once(html,
                        'document.getElementById("rBack").addEventListener("click", ()=>{\n'
                        '  document.getElementById("readerView").classList.add("hidden");',
                        'document.getElementById("rBack").addEventListener("click", ()=>{\n'
                        '  document.getElementById("readerView").classList.add("hidden");\n'
                        '  notifyNativeChrome({type:"reader", open:false});',
                        "index.html rBack bridge")
    html = replace_once(html,
                        'function applyTheme(pref){\n'
                        '  const dark = pref==="dark" || (pref==="auto" && systemPrefersDark());',
                        'function applyTheme(pref){\n'
                        '  const dark = pref==="dark" || (pref==="auto" && systemPrefersDark());\n'
                        '  notifyNativeChrome({type:"theme", dark:dark});',
                        "index.html applyTheme bridge")
    html = replace_once(html,
                        '      const st=bumpStreak();\n'
                        '      renderStreakBadge();\n'
                        '      if(st.justHitMilestone) setTimeout(()=>showToast("🔥 "+st.count+" ימים ברצף! כל הכבוד"), 650);',
                        '      const st=bumpStreak();\n'
                        '      renderStreakBadge();\n'
                        '      notifyNativeChrome({type:"haptic", style: st.justHitMilestone ? "success" : "light"});\n'
                        '      if(st.justHitMilestone) setTimeout(()=>showToast("🔥 "+st.count+" ימים ברצף! כל הכבוד"), 650);',
                        "index.html mark-as-learned haptic bridge")
    html = replace_once(html, "</body>", NATIVE_BLOCK + "</body>", "index.html </body>")
    open(p, "w", encoding="utf-8").write(html)

    n_files = sum(len(f) for _, _, f in os.walk(DST))
    print(f"www/ rebuilt from {SRC}: {n_files} files")
    if "--no-sync" not in sys.argv:
        subprocess.run(["npx", "cap", "sync", "ios"], cwd=HERE, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
