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
  3. A native-shell block is appended: the daily local notification (07:30) via
     @capacitor/local-notifications — the one real native feature of the app.
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
   Adds the one piece of real native functionality the App Store wants to see beyond a
   bare WebView: a daily local notification reminding the user that today's halacha is
   ready, scheduled once and left to repeat — no server, no push infra, fully offline. */
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
      // Fixed id -> rescheduling on every launch just overwrites the same notification,
      // so this is safe to call unconditionally instead of tracking a "did we already
      // schedule this" flag in storage.
      await LocalNotifications.schedule({
        notifications: [{
          id: 1,
          title: "הלכה יומית",
          body: "ההלכה של היום מוכנה — לחצו לקריאה",
          schedule: { on: { hour: 7, minute: 30 }, repeats: true, allowWhileIdle: true }
        }]
      });
    }catch(e){ /* permission denied or plugin unavailable — app works fine without it */ }
  });
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

    # 2. index.html — Firebase counters stay on inside the native app; 3. native block
    p = os.path.join(DST, "index.html")
    html = open(p, encoding="utf-8").read()
    html = replace_once(html, "  if(IS_LOCAL) return;                       // chips just stay at their \"–\" placeholder",
                        "  // The native app runs from capacitor://localhost — a real user, not a dev copy — so it\n"
                        "  // is counted together with the website (owner's decision, 2026-09-23).\n"
                        "  const IS_NATIVE_APP = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());\n"
                        "  if(IS_LOCAL && !IS_NATIVE_APP) return;     // chips just stay at their \"–\" placeholder",
                        "index.html IS_LOCAL guard")
    html = replace_once(html, "</body>", NATIVE_BLOCK + "</body>", "index.html </body>")
    open(p, "w", encoding="utf-8").write(html)

    n_files = sum(len(f) for _, _, f in os.walk(DST))
    print(f"www/ rebuilt from {SRC}: {n_files} files")
    if "--no-sync" not in sys.argv:
        subprocess.run(["npx", "cap", "sync", "ios"], cwd=HERE, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
