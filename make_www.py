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
  6. Share-the-app (SHARE_BLOCK), app-bundle only, NOT platform-gated (Web Share API + Canvas
     work the same on web/iOS/Android): a "שיתוף" section in Settings with a plain text share
     and a "share QR" that draws a branded PNG (app icon + title + QR code) entirely on
     <canvas>, offline — vendor/qrcode.js (the MIT-licensed kazuhikoarase QR generator,
     checked into this repo) is copied into www/ by this script, rather than fetching a QR
     from an external image API like some other apps' web code does, which would silently
     fail offline and isn't worth the CSP connect-src hole for an app this deliberately
     offline-first. APP_STORE_URL below needs to be the app's real App Store link.
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

  // Edge-swipe back (like Android's back gesture) + status-bar tap scroll-to-top. iOS app only.
  window.betelAppBack = function(){
    var pb = document.getElementById("pickerBack");
    if(pb && pb.offsetParent !== null){ pb.click(); return true; }
    var rv = document.getElementById("readerView"), rb = document.getElementById("rBack");
    if(rv && !rv.classList.contains("hidden") && rb){ rb.click(); return true; }
    return false;
  };
  window.betelCanGoBack = function(){
    var pb=document.getElementById("pickerBack");
    if(pb && pb.offsetParent!==null) return true;
    var rv=document.getElementById("readerView");
    return !!(rv && !rv.classList.contains("hidden") && document.getElementById("rBack"));
  };
  window.betelScrollTop = function(){
    try{ window.scrollTo({top:0, behavior:"smooth"}); }catch(e){ window.scrollTo(0,0); }
  };
  if(isIOSNative && false){   // native UIScreenEdgePanGestureRecognizer handles this now
    var sx=0, sy=0, st=0, edge=false;
    document.addEventListener("touchstart", function(e){
      var t=e.touches[0]; sx=t.clientX; sy=t.clientY; st=Date.now();
      edge = e.touches.length===1 && (sx<=22 || sx>=window.innerWidth-22);
    }, {passive:true});
    document.addEventListener("touchend", function(e){
      if(!edge) return; edge=false;
      var t=e.changedTouches[0], dx=t.clientX-sx, dy=t.clientY-sy;
      var inward = sx<=22 ? dx : -dx;
      if(inward>70 && Math.abs(dy)<0.6*inward && Date.now()-st<700) window.betelAppBack();
    }, {passive:true});
  }

  // Pull-down-to-refresh (re-renders the open tab), tap-the-active-tab-again scrolls to top,
  // and a long-press menu on parasha tiles that opens the real iOS action sheet (Liquid Glass on
  // iOS 26) via the native side. iOS app only.
  window.betelTabReselect = function(id){
    var b = document.getElementById(id);
    if(!b || !b.classList.contains("active")) return false;
    if((window.scrollY||document.documentElement.scrollTop||0) > 8){ window.betelScrollTop(); return true; }
    return false;
  };
  var __actCb = {};
  window.__betelActionDone = function(cb, id){ var f = __actCb[cb]; delete __actCb[cb]; if(f) f(id); };
  function nativeSheet(title, actions, cancel, cb){
    var n = String(Date.now()); __actCb[n] = cb;
    window.notifyNativeChrome({type:"actionSheet", title:title, actions:actions, cancel:cancel, cb:n});
  }
  if(isIOSNative){
    // (pull-to-refresh is Apple's native UIRefreshControl now - see LiquidGlassChrome.swift)

    // ---- long-press on a parasha tile -> system action sheet ----
    var lpTimer=null, lpx=0, lpy=0, lpFired=0;
    document.addEventListener("touchstart", function(e){
      var tile = e.target.closest && e.target.closest(".btile[data-key]");
      if(!tile || e.touches.length!==1) return;
      var t=e.touches[0]; lpx=t.clientX; lpy=t.clientY;
      clearTimeout(lpTimer);
      lpTimer=setTimeout(function(){
        lpFired=Date.now();
        window.notifyNativeChrome({type:"haptic", style:"light"});
        var nm = (tile.querySelector(".bn,.bt,.name")||tile).textContent.trim().split("\n")[0].slice(0,40);
        nativeSheet(nm, [{id:"open",title:"פתיחה"},{id:"share",title:"שיתוף"}], "ביטול", function(id){
          if(id==="open") tile.click();
          else if(id==="share"){
            var txt = "הלכות הבן איש חי — " + nm;
            try{ if(typeof APP_STORE_URL==="string" && APP_STORE_URL.indexOf("REPLACE")<0) txt += "\n" + APP_STORE_URL; }catch(_){}
            if(navigator.share) navigator.share({title:"הלכות הבן איש חי", text:txt}).catch(function(){});
            else if(navigator.clipboard) navigator.clipboard.writeText(txt);
          }
        });
      }, 480);
    }, {passive:true});
    document.addEventListener("touchmove", function(e){
      var t=e.touches[0]; if(lpTimer && (Math.abs(t.clientX-lpx)>8 || Math.abs(t.clientY-lpy)>8)){ clearTimeout(lpTimer); lpTimer=null; }
    }, {passive:true});
    ["touchend","touchcancel"].forEach(function(ev){ document.addEventListener(ev, function(){ clearTimeout(lpTimer); lpTimer=null; }, {passive:true}); });
    document.addEventListener("click", function(e){ if(Date.now()-lpFired<700){ e.stopPropagation(); e.preventDefault(); } }, true);
  }
  window.nativeSetSearchQuery = function(q){
    var el = document.getElementById("searchInput");
    if(el){ el.value = q; el.dispatchEvent(new Event("input")); }
  };
  // Pushes the streak + today's parasha into the HalachaWidget's shared App Group storage
  // (see ios/App/App/HalachaWidgetBridge.swift) so the home-screen widget reflects the
  // learner's real state. No-ops on web/Android or before the native target exists. Called
  // from the streak badge, the theme switcher and the weekly-home render (see their call
  // sites below) — never from here, so it always runs after the real DOM/localStorage state
  // it reads is already up to date.
  window.syncWidgetData = function(){
    try{
      var plugin = isIOSNative && window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.HalachaWidgetBridge;
      if(!plugin) return;
      var titleEl = document.getElementById("wParasha");
      var candle = typeof nextCandleLightingInfo === "function" ? nextCandleLightingInfo() : null;
      plugin.updateSharedData({
        streakCount: typeof currentStreak === "function" ? currentStreak() : 0,
        streakBest: typeof bestStreak === "function" ? bestStreak() : 0,
        learnedToday: typeof learnedToday === "function" ? learnedToday() : false,
        theme: (typeof getTheme === "function" && getTheme() === "auto") ? (systemPrefersDark() ? "dark" : "light") : getTheme(),
        parashaHe: titleEl ? titleEl.textContent : "",
        candleTimeISO: candle ? candle.iso : null,
        candleLabel: candle ? candle.label : null,
        candleWeekday: candle ? candle.weekday : null
      });
    }catch(e){}
  };
})();
</script>
'''

# TODO(david): replace with the app's real App Store link before shipping this feature —
# https://apps.apple.com/app/<slug>/id<numeric id>. Deliberately left as an obvious
# placeholder (not a guess) so this is impossible to ship by accident.
APP_STORE_URL = "https://apps.apple.com/app/REPLACE_WITH_REAL_SLUG/idREPLACE_WITH_REAL_ID"

SHARE_SETTINGS_SECTION = '''      <section class="settings-sec">
        <h3>שיתוף</h3>
        <button class="tool-btn" id="shareAppBtn" style="width:100%;justify-content:center;margin-bottom:8px;">''' + \
    '<svg viewBox="0 0 24 24"><circle cx="18" cy="5" r="2.6"/><circle cx="6" cy="12" r="2.6"/><circle cx="18" cy="19" r="2.6"/><path d="M8.3 10.7l7.4-4.2M8.3 13.3l7.4 4.2"/></svg>' + '''<span>שתפו את האפליקציה</span></button>
        <button class="tool-btn" id="shareQrBtn" style="width:100%;justify-content:center;">''' + \
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3.5" y="3.5" width="6" height="6" rx="1"/><rect x="14.5" y="3.5" width="6" height="6" rx="1"/><rect x="3.5" y="14.5" width="6" height="6" rx="1"/><path d="M14.5 14.5h3v3h-3zM19.5 14.5v3M14.5 19.5h3M17.5 17.5h.01"/></svg>' + '''<span>שתפו קוד QR</span></button>
      </section>
'''

# Appended before </body> alongside NATIVE_BLOCK. Not gated to any platform (Web Share API +
# <canvas> work identically on web/iOS/Android) — see point 6 in the module docstring above.
SHARE_BLOCK = r'''
<script>
const APP_STORE_URL = "''' + APP_STORE_URL + r'''";
async function _ensureQrLib(){ if(!window.qrcode) await _loadScript("qrcode.js"); }
function shareAppText(){
  const text="📖 הלכות הבן איש חי — הלכה אחת ביום, בדיוק לפי הסדר של הבן איש חי\n"+APP_STORE_URL;
  if(navigator.share){ navigator.share({title:"הלכות הבן איש חי", text}).catch(()=>{}); }
  else if(navigator.clipboard){ navigator.clipboard.writeText(text).then(()=>showToast("הקישור הועתק")).catch(()=>{}); }
}
// Fixed light/gold theme regardless of the viewer's in-app dark/light choice, so the shared
// image always looks the same no matter who sent it or what mode they were in — same reasoning
// Bet-El's app share image uses a fixed theme rather than tracking S.theme.
async function buildAppQrImage(){
  await _ensureQrLib();
  if(document.fonts && document.fonts.ready) await document.fonts.ready;
  const qr=qrcode(0,"M"); qr.addData(APP_STORE_URL); qr.make();

  const W=1080,H=1400;
  const cv=document.createElement("canvas"); cv.width=W; cv.height=H;
  const ctx=cv.getContext("2d");
  const bg1="#F5EEDA",bg2="#FCF8EC",navy="#0F314D",gold="#BF9530",goldDeep="#8A6A1E",ink="#2B2A1A";
  const g=ctx.createLinearGradient(0,0,W,H); g.addColorStop(0,bg2); g.addColorStop(1,bg1);
  ctx.fillStyle=g; ctx.fillRect(0,0,W,H);
  ctx.strokeStyle="rgba(191,149,48,.35)"; ctx.lineWidth=3; ctx.strokeRect(30,30,W-60,H-60);
  ctx.strokeStyle="rgba(191,149,48,.18)"; ctx.lineWidth=1; ctx.strokeRect(44,44,W-88,H-88);

  await new Promise(res=>{
    const im=new Image();
    im.onload=()=>{ const lw=200,lh=200; ctx.drawImage(im,(W-lw)/2,70,lw,lh); res(); };
    im.onerror=res; im.src="icon-512.png";
  });

  ctx.textAlign="center";
  ctx.fillStyle=navy; ctx.font='900 56px "Frank Ruhl Libre",serif';
  ctx.fillText("הלכות הבן איש חי", W/2, 350);
  ctx.fillStyle=ink; ctx.font='400 30px "Heebo",sans-serif';
  ctx.fillText("הלכה אחת ביום", W/2, 395);

  ctx.strokeStyle="rgba(191,149,48,.35)"; ctx.lineWidth=2;
  ctx.beginPath(); ctx.moveTo(150,430); ctx.lineTo(W-150,430); ctx.stroke();
  ctx.fillStyle=gold; ctx.font="30px serif"; ctx.fillText("✦", W/2, 440);

  // The QR itself is drawn module-by-module straight onto the canvas (no image request at
  // all) — fully offline, unlike a remote QR-image-generator API.
  const qrSize=560, qrX=(W-qrSize)/2, qrY=490;
  const count=qr.getModuleCount(), cell=qrSize/count;
  ctx.fillStyle="#FFFFFF"; ctx.fillRect(qrX,qrY,qrSize,qrSize);
  ctx.fillStyle=navy;
  for(let r=0;r<count;r++) for(let c=0;c<count;c++)
    if(qr.isDark(r,c)) ctx.fillRect(qrX+c*cell, qrY+r*cell, Math.ceil(cell), Math.ceil(cell));

  ctx.fillStyle=ink; ctx.font='500 30px "Heebo",sans-serif';
  ctx.fillText("סריקה תפתח את האפליקציה ב-App Store", W/2, qrY+qrSize+60);
  ctx.fillStyle=goldDeep; ctx.font='700 32px "Frank Ruhl Libre",serif';
  ctx.fillText("הלכות הבן איש חי", W/2, H-70);
  return cv;
}
async function shareAppQR(){
  showToast("מכין תמונה…");
  try{
    const cv=await buildAppQrImage();
    cv.toBlob(async blob=>{
      if(!blob){ showToast("שגיאה ביצירת תמונה"); return; }
      const file=new File([blob],"halacha-yomit-qr.png",{type:"image/png"});
      if(navigator.canShare && navigator.canShare({files:[file]})){
        try{ await navigator.share({files:[file], text:APP_STORE_URL}); }catch(e){}
      }else{
        const url=URL.createObjectURL(blob);
        const a=document.createElement("a"); a.href=url; a.download="halacha-yomit-qr.png";
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(()=>URL.revokeObjectURL(url),4000);
        showToast("התמונה נשמרה, אפשר לשתף אותה מהמכשיר");
      }
    },"image/png");
  }catch(e){ showToast("שגיאה ביצירת תמונה"); }
}
document.getElementById("shareAppBtn").addEventListener("click", shareAppText);
document.getElementById("shareQrBtn").addEventListener("click", shareAppQR);
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
    html = replace_once(html,
                        '        <div class="fsz-row">\n'
                        '          <button class="fsz-btn" id="fszDown">א־</button>\n'
                        '          <div class="fsz-label" id="fszLabel">רגיל</div>\n'
                        '          <button class="fsz-btn" id="fszUp">א+</button>\n'
                        '        </div>\n'
                        '      </section>\n'
                        '    </div>\n'
                        '  </div>\n'
                        '</div>\n'
                        '\n'
                        '<div class="modal-overlay hidden" id="statsOverlay">',
                        '        <div class="fsz-row">\n'
                        '          <button class="fsz-btn" id="fszDown">א־</button>\n'
                        '          <div class="fsz-label" id="fszLabel">רגיל</div>\n'
                        '          <button class="fsz-btn" id="fszUp">א+</button>\n'
                        '        </div>\n'
                        '      </section>\n'
                        + SHARE_SETTINGS_SECTION +
                        '    </div>\n'
                        '  </div>\n'
                        '</div>\n'
                        '\n'
                        '<div class="modal-overlay hidden" id="statsOverlay">',
                        "index.html share settings section")
    html = replace_once(html,
                        '  const d=new Date(now);\n'
                        '  if(shifted) d.setDate(d.getDate()+1);\n'
                        '  d.setHours(12,0,0,0);\n'
                        '  return {date:d, shifted};\n'
                        '}\n',
                        '  const d=new Date(now);\n'
                        '  if(shifted) d.setDate(d.getDate()+1);\n'
                        '  d.setHours(12,0,0,0);\n'
                        '  return {date:d, shifted};\n'
                        '}\n'
                        '\n'
                        '// Candle lighting: the standard 18 minutes before real sunset (hDeg=-0.833, not the -7.083\n'
                        '// tzeit used above) — the same default most Jewish calendars (incl. the hebcal library used\n'
                        '// by the user\'s other app) fall back to when no community-specific custom is configured.\n'
                        '// Reuses the same TZ_GEO table — still no location permission prompt.\n'
                        '//\n'
                        '// Covers both Shabbat AND Yom Tov (reusing YOM_TOV_IL/YOM_TOV_DIA + _hebMD, already defined\n'
                        '// below for the festival-week feature — same brute-force civil-day-scan approach, no separate\n'
                        '// Hebrew calendar library needed). Scans each candidate "eve" day E and checks whether E+1 is\n'
                        '// a day that needs candles (Shabbat, or a Hebrew date in the Yom Tov list) — this also\n'
                        '// correctly handles a multi-day Yom Tov\'s later days (lit from an existing flame at the same\n'
                        '// time), since E itself may already be a Yom Tov day.\n'
                        'function _yomTovName(md){\n'
                        '  const [m,d]=md;\n'
                        '  if(m==="Tishri"){\n'
                        '    if(d===1||d===2) return "ראש השנה";\n'
                        '    if(d===10) return "יום הכיפורים";\n'
                        '    if(d===15||d===16) return "סוכות";\n'
                        '    if(d===22||d===23) return "שמיני עצרת";\n'
                        '  }\n'
                        '  if(m==="Nisan"){\n'
                        '    if(d===15||d===16) return "פסח";\n'
                        '    if(d===21||d===22) return "פסח";\n'
                        '  }\n'
                        '  if(m==="Sivan" && (d===6||d===7)) return "שבועות";\n'
                        '  return "יום טוב";\n'
                        '}\n'
                        'const CANDLE_LIGHTING_MINS_BEFORE_SUNSET = 18;\n'
                        'function nextCandleLightingInfo(){\n'
                        '  try{\n'
                        '    const tzid=Intl.DateTimeFormat().resolvedOptions().timeZone;\n'
                        '    const geo=TZ_GEO[tzid]; if(!geo) return null;\n'
                        '    const diaspora = tzid!=="Asia/Jerusalem";\n'
                        '    const yomTov = diaspora ? YOM_TOV_DIA : YOM_TOV_IL;\n'
                        '    const now=new Date();\n'
                        '    for(let i=0;i<30;i++){\n'
                        '      const e=new Date(now); e.setDate(e.getDate()+i); e.setHours(12,0,0,0);\n'
                        '      const next=_addDays(e,1);\n'
                        '      const ytMatch = yomTov.find(md=>_sameMD(md,_hebMD(next)));\n'
                        '      const isShabbatEve = next.getDay()===6;\n'
                        '      if(!ytMatch && !isShabbatEve) continue;\n'
                        '      const sunset=_sunsetInstant(e, geo[0], geo[1], -0.833);\n'
                        '      if(!sunset) continue;\n'
                        '      const candle=new Date(sunset.getTime() - CANDLE_LIGHTING_MINS_BEFORE_SUNSET*60000);\n'
                        '      if(candle>now){\n'
                        '        const label = "הדלקת נרות " + (ytMatch ? _yomTovName(ytMatch) : "שבת");\n'
                        '        const weekday = e.toLocaleDateString("he-IL",{weekday:"long"});\n'
                        '        return {iso:candle.toISOString(), label, weekday};\n'
                        '      }\n'
                        '    }\n'
                        '  }catch(e){}\n'
                        '  return null;\n'
                        '}\n',
                        "index.html candle lighting calc")
    html = replace_once(html,
                        '  [...document.querySelectorAll("#themeSeg button")].forEach(b=>\n'
                        '    b.classList.toggle("on", b.dataset.themeChoice===pref));\n'
                        '  moveSegPill();\n'
                        '}',
                        '  [...document.querySelectorAll("#themeSeg button")].forEach(b=>\n'
                        '    b.classList.toggle("on", b.dataset.themeChoice===pref));\n'
                        '  moveSegPill();\n'
                        '  syncWidgetData();\n'
                        '}', "index.html applyTheme widget sync")
    html = replace_once(html,
                        '  const n=currentStreak();\n'
                        '  b.classList.toggle("hidden", n<=0);\n'
                        '  if(n>0) b.textContent="🔥"+n;\n'
                        '}',
                        '  const n=currentStreak();\n'
                        '  b.classList.toggle("hidden", n<=0);\n'
                        '  if(n>0) b.textContent="🔥"+n;\n'
                        '  syncWidgetData();\n'
                        '}', "index.html renderStreakBadge widget sync")
    html = replace_once(html,
                        '      lastHome="week";\n'
                        '      await openReader(keys, (rec.title_he||"פרשת השבוע")+" · "+trackName(tk), {startAt:"first-unread"});\n'
                        '    });\n'
                        '  });\n'
                        '}',
                        '      lastHome="week";\n'
                        '      await openReader(keys, (rec.title_he||"פרשת השבוע")+" · "+trackName(tk), {startAt:"first-unread"});\n'
                        '    });\n'
                        '  });\n'
                        '  syncWidgetData();\n'
                        '}', "index.html renderWeek widget sync")
    html = replace_once(html,
                        'function openSettings(){\n'
                        '  document.getElementById("settingsOverlay").classList.remove("hidden");\n'
                        '  applyFsz(getFszIdx());\n'
                        '  applyTheme(getTheme());       // reflect the current choice in the segmented control\n'
                        '}',
                        'function openSettings(){\n'
                        '  // On iOS, a real native Liquid Glass sheet (NativeSettingsView.swift) replaces this HTML\n'
                        '  // overlay entirely — same gating as the tab/nav/search bars (isIOSNative, see head script).\n'
                        '  // The native side calls back into the exact same setTheme()/applyFsz()/shareAppText()/\n'
                        '  // shareAppQR() used here, so there is only ever one implementation of each action.\n'
                        '  if(isIOSNative){\n'
                        '    notifyNativeChrome({type:"settings", open:true,\n'
                        '      theme:getTheme(), fszIdx:getFszIdx(), fszMax:FSZ_STEPS.length-1});\n'
                        '    return;\n'
                        '  }\n'
                        '  document.getElementById("settingsOverlay").classList.remove("hidden");\n'
                        '  applyFsz(getFszIdx());\n'
                        '  applyTheme(getTheme());       // reflect the current choice in the segmented control\n'
                        '}', "index.html openSettings native sheet")
    html = replace_once(html,
                        'async function renderStats(){\n'
                        '  const body=document.getElementById("statsBody");',
                        '// Same numbers renderStats() below computes for its HTML rings, as plain data — used by the\n'
                        '// native Stats sheet (NativeStatsView.swift) instead of rendering HTML at all. Kept as its own\n'
                        '// function (a little duplicated arithmetic) rather than refactoring renderStats() itself, so\n'
                        '// the existing, working web/Android HTML path is never touched by this native-only addition.\n'
                        'async function statsNumbersForNative(){\n'
                        '  if(!master) master=await getJson("content/parashot.json",true);\n'
                        '  const map=loadProgressMap();\n'
                        '  const out={};\n'
                        '  let grandTotal=0, grandDone=0;\n'
                        '  for(const tk of ["year1","year2"]){\n'
                        '    const rows=(master&&master[tk])||[];\n'
                        '    let total=0;\n'
                        '    for(const r of rows) total += r.chapters + (r.has_intro?1:0);\n'
                        '    let done=0;\n'
                        '    for(const k of Object.keys(map)){ if(k.startsWith(tk+"::")) done++; }\n'
                        '    total = Math.max(total, done);\n'
                        '    grandTotal+=total; grandDone+=done;\n'
                        '    out[tk]={done, total};\n'
                        '  }\n'
                        '  out.grand={done:grandDone, total:grandTotal};\n'
                        '  return out;\n'
                        '}\n'
                        'async function renderStats(){\n'
                        '  const body=document.getElementById("statsBody");', "index.html statsNumbersForNative")
    html = replace_once(html,
                        'function openStats(){\n'
                        '  document.getElementById("statsOverlay").classList.remove("hidden");\n'
                        '  renderStats();\n'
                        '}',
                        'async function openStats(){\n'
                        '  // Same native-sheet gating as openSettings() above — NativeStatsView.swift draws its own\n'
                        '  // rings from the real numbers, no HTML rendering on iOS at all.\n'
                        '  if(isIOSNative){\n'
                        '    const n = await statsNumbersForNative();\n'
                        '    notifyNativeChrome({type:"stats", open:true, year1:n.year1, year2:n.year2, grand:n.grand});\n'
                        '    return;\n'
                        '  }\n'
                        '  document.getElementById("statsOverlay").classList.remove("hidden");\n'
                        '  renderStats();\n'
                        '}', "index.html openStats native sheet")
    html = replace_once(html,
                        'function showToast(msg){\n'
                        '  const t=document.getElementById("toast");\n'
                        '  t.textContent=msg;\n'
                        '  t.classList.remove("hidden");\n'
                        '  clearTimeout(showToast._t);\n'
                        '  showToast._t=setTimeout(()=>t.classList.add("hidden"),2200);\n'
                        '}',
                        'function showToast(msg){\n'
                        '  // A real native toast (blurred capsule, see presentToast() in LiquidGlassChrome.swift)\n'
                        '  // replaces the HTML one on iOS — same fixed-position screen-edge chrome as the tab/nav bars,\n'
                        '  // so it\'s safe to fully hand off rather than duplicate.\n'
                        '  if(isIOSNative){ notifyNativeChrome({type:"toast", text:msg}); return; }\n'
                        '  const t=document.getElementById("toast");\n'
                        '  t.textContent=msg;\n'
                        '  t.classList.remove("hidden");\n'
                        '  clearTimeout(showToast._t);\n'
                        '  showToast._t=setTimeout(()=>t.classList.add("hidden"),2200);\n'
                        '}', "index.html showToast native toast")
    html = replace_once(html, "</body>", NATIVE_BLOCK + SHARE_BLOCK + "</body>", "index.html </body>")
    open(p, "w", encoding="utf-8").write(html)

    # 6. qrcode.js — the offline QR-code generator the share-QR feature above needs (see
    #    SHARE_BLOCK's _ensureQrLib(), which loads it lazily as "qrcode.js" next to index.html).
    shutil.copy(os.path.join(HERE, "vendor", "qrcode.js"), os.path.join(DST, "qrcode.js"))

    n_files = sum(len(f) for _, _, f in os.walk(DST))
    print(f"www/ rebuilt from {SRC}: {n_files} files")
    if "--no-sync" not in sys.argv:
        subprocess.run(["npx", "cap", "sync", "ios"], cwd=HERE, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
