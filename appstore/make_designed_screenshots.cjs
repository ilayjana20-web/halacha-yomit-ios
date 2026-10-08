// Designed App Store screenshots from raw simulator/device screenshots.
//
//   npm i --no-save playwright          (once; uses your installed Google Chrome, no download)
//   node appstore/make_designed_screenshots.cjs <rawDir> <outDir>
//
// Two kinds of input PNGs:
//   * REAL SIMULATOR WINDOW captures (preferred): the whole Simulator window with Apple's real
//     iPhone bezel, e.g. `screencapture -o -l <windowId> week_framed.png` (transparent corners).
//     Put "framed" in the file name. It is placed as-is, no frame is drawn.
//   * Plain screen captures (`simctl io screenshot`, 1320x2868): a simple frame is drawn around them.
// <rawDir> is scanned recursively for PNGs. A file is a "dark" slide when its path
// or name contains "dark", otherwise "light". The slide copy is chosen by keyword in the file
// name (week|home, reader, topics, picker|parash, search, settings, stats) — see
// appstore/screenshot_copy.json. Output: JPEG (flattened, no alpha), 1320x2868.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const [rawDir, outDir] = process.argv.slice(2);
if (!rawDir || !outDir) { console.error("usage: node make_designed_screenshots.cjs <rawDir> <outDir>"); process.exit(1); }
const copy = JSON.parse(fs.readFileSync(path.join(__dirname, "screenshot_copy.json"), "utf8"));
const font = f => "file://" + path.join(__dirname, "fonts", f);

function walk(d) {
  return fs.readdirSync(d, { withFileTypes: true }).flatMap(e =>
    e.isDirectory() ? walk(path.join(d, e.name)) : /\.png$/i.test(e.name) ? [path.join(d, e.name)] : []);
}
function keyOf(file) {
  const n = path.basename(file).toLowerCase();
  if (/week|home/.test(n)) return "week";
  if (/stat/.test(n)) return "stats";
  if (/setting/.test(n)) return "settings";
  if (/topic/.test(n)) return "topics";
  if (/picker|parash/.test(n)) return "picker";
  if (/search/.test(n)) return "search";
  if (/reader|biur/.test(n)) return "reader";
  return null;
}
const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
const headlineHtml = lines => lines.map(l =>
  `<div class="hl-line">${esc(l).replace(/\{([^}]+)\}/g, '<em>$1</em>')}</div>`).join("");

const DIAMOND = c => `url("data:image/svg+xml;utf8,${encodeURIComponent(
  `<svg xmlns='http://www.w3.org/2000/svg' width='180' height='180' viewBox='0 0 180 180' fill='none' stroke='${c}' stroke-width='2'><path d='M90 12 168 90 90 168 12 90Z'/><path d='M90 44 136 90 90 136 44 90Z'/></svg>`)}")`;

function page({ dataUri, theme, c }) {
  const dark = true;   // slides always use the deep-navy + gold look; the app screen inside keeps its own light/dark theme
  const P = dark
    ? { bg: "radial-gradient(120% 62% at 100% 0%,rgba(190,150,58,.72) 0%,rgba(190,150,58,.18) 45%,transparent 70%),linear-gradient(180deg,#0C2A4F 0%,#0E3260 52%,#0A2446 100%)", ink: "#FFFFFF", gold1: "#F6DE96", gold2: "#D9AE45",
        sub: "#A9BBC4", pillBorder: "rgba(231,212,158,.45)", pillInk: "#E7D49E", pillBg: "rgba(231,212,158,.07)",
        glow1: "rgba(63,132,138,.0)", glow2: "rgba(217,174,69,.0)", pat: "rgba(231,212,158,.0)",
        shadow: "0 50px 110px rgba(0,0,0,.65), 0 0 0 2px rgba(231,212,158,.14)", bezel: "#05090D", edge: "rgba(255,255,255,.18)" }
    : { bg: "linear-gradient(172deg,#FFFDF6 0%,#F5EEDA 56%,#E8D6A0 100%)", ink: "#0F314D", gold1: "#C99A2B", gold2: "#8A6A1E",
        sub: "#5C6B72", pillBorder: "rgba(138,106,30,.45)", pillInk: "#8A6A1E", pillBg: "rgba(191,149,48,.10)",
        glow1: "rgba(63,132,138,.22)", glow2: "rgba(191,149,48,.20)", pat: "rgba(191,149,48,.10)",
        shadow: "0 50px 110px rgba(15,49,77,.38), 0 0 0 2px rgba(15,49,77,.10)", bezel: "#0E141A", edge: "rgba(255,255,255,.28)" };
  return `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><style>
@font-face{font-family:FRL;font-weight:900;src:url("${font("FrankRuhlLibre-Black.ttf")}")}
@font-face{font-family:FRL;font-weight:700;src:url("${font("FrankRuhlLibre-Bold.ttf")}")}
@font-face{font-family:Heebo;font-weight:500;src:url("${font("Heebo-Medium.ttf")}")}
@font-face{font-family:Heebo;font-weight:700;src:url("${font("Heebo-Bold.ttf")}")}
@font-face{font-family:Heebo;font-weight:800;src:url("${font("Heebo-ExtraBold.ttf")}")}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1320px;height:2868px;overflow:hidden}
body{background:${P.bg};position:relative;font-family:Heebo,sans-serif}
.glow1{position:absolute;width:1300px;height:1300px;left:-480px;top:-420px;border-radius:50%;background:radial-gradient(closest-side,${P.glow1},transparent)}
.glow2{position:absolute;width:1500px;height:1500px;right:-600px;bottom:-500px;border-radius:50%;background:radial-gradient(closest-side,${P.glow2},transparent)}
.pat{position:absolute;inset:0;background-image:${DIAMOND(P.pat)};background-size:180px 180px;background-position:center top;
  -webkit-mask-image:linear-gradient(180deg,#000 0%,#000 30%,transparent 62%);mask-image:linear-gradient(180deg,#000 0%,#000 30%,transparent 62%)}
.copy{position:absolute;top:64px;left:0;right:0;text-align:center;padding:0 70px}
.pill{display:inline-block;font-weight:700;font-size:34px;color:#C9A24A;opacity:.95}
.hl{margin-top:22px;font-family:Heebo,sans-serif;font-weight:800;font-size:124px;line-height:1.06;letter-spacing:-.01em;color:${P.ink}}
.hl em{font-style:normal;background:linear-gradient(100deg,${P.gold1},${P.gold2});-webkit-background-clip:text;background-clip:text;color:transparent}
.orn{display:none;align-items:center;justify-content:center;gap:22px;margin:22px 0 0}
.orn i{display:block;height:3px;width:120px;background:linear-gradient(90deg,transparent,${P.gold2})}
.orn i:last-child{transform:scaleX(-1)}
.orn b{display:block;width:16px;height:16px;transform:rotate(45deg);background:${P.gold2}}
.sub{margin-top:24px;font-weight:500;font-size:44px;line-height:1.32;color:${P.sub};white-space:pre-line}
.device{position:absolute;left:146px;top:${c.deviceTop}px;width:1028px;height:2203px;border-radius:138px;background:${P.bezel};
  box-shadow:${P.shadow};padding:14px}
.device:before{content:"";position:absolute;inset:0;border-radius:138px;box-shadow:inset 0 0 0 3px ${P.edge};pointer-events:none}
.screen{position:relative;width:1000px;height:2175px;border-radius:124px;overflow:hidden;background:#000}
.screen img{display:block;width:1000px;height:2175px}
.framed{position:absolute;left:40px;top:${c.deviceTop - 10}px;width:1240px;height:2230px;display:flex;align-items:flex-start;justify-content:center}
.framed img{max-width:100%;max-height:100%;display:block;filter:drop-shadow(0 50px 70px ${dark ? "rgba(0,0,0,.6)" : "rgba(15,49,77,.35)"})}
.island{position:absolute;left:50%;top:28px;width:270px;height:80px;margin-left:-135px;border-radius:46px;background:#000}
.sheen{position:absolute;inset:0;border-radius:124px;background:linear-gradient(115deg,rgba(255,255,255,.10),transparent 28%);pointer-events:none}
</style></head><body>
<div class="glow1"></div><div class="glow2"></div><div class="pat"></div>
<div class="copy">
  <div class="pill">${esc(c.eyebrow)}</div>
  <div class="hl">${headlineHtml(c.headline)}</div>
  <div class="sub">${esc(c.sub)}</div>
</div>
${c.framed ? `<div class="framed"><img src="${dataUri}"></div>` :
`<div class="device"><div class="screen"><img src="${dataUri}">${c.island ? '<div class="island"></div>' : ""}<div class="sheen"></div></div></div>`}
</body></html>`;
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const files = walk(rawDir).map(f => ({ f, key: keyOf(f), theme: /dark/i.test(f) ? "dark" : "light" })).filter(x => x.key);
  files.sort((a, b) => copy.order.indexOf(a.key) - copy.order.indexOf(b.key) || a.theme.localeCompare(b.theme));
  let browser;
  try { browser = await chromium.launch({ channel: "chrome" }); } catch (e) { browser = await chromium.launch(); }
  const ctx = await browser.newContext({ viewport: { width: 1320, height: 2868 }, deviceScaleFactor: 1 });
  const pg = await ctx.newPage();
  let n = 0;
  for (const { f, key, theme } of files) {
    const slide = copy.slides[key]; const c0 = slide[theme] || slide.light;
    const dataUri = "data:image/png;base64," + fs.readFileSync(f).toString("base64");
    // Draw our own Dynamic Island only if the raw screenshot has none AND the spot is empty
    // status-bar space (never on top of app content, e.g. screenshots taken without a status bar).
    const framed = /framed/i.test(f);
    const drawIsland = framed ? false : await pg.evaluate(async uri => {
      const im = new Image(); im.src = uri; await im.decode();
      const cv = document.createElement("canvas"); cv.width = im.width; cv.height = im.height;
      const cx = cv.getContext("2d"); cx.drawImage(im, 0, 0);
      const x = Math.round(im.width * .5), y = Math.round(im.height * .0135);
      const d = cx.getImageData(x - 40, y - 4, 80, 8).data; let dark = 0;
      for (let i = 0; i < d.length; i += 4) if (d[i] < 30 && d[i + 1] < 30 && d[i + 2] < 30) dark++;
      if (dark > d.length / 4 * .85) return false;                  // island already in the screenshot
      const r = cx.getImageData(x - 146, 30, 292, 86).data; let mn = 255, mx = 0;
      for (let i = 0; i < r.length; i += 4) { const l = (r[i] + r[i + 1] + r[i + 2]) / 3; mn = Math.min(mn, l); mx = Math.max(mx, l); }
      return mx - mn < 40;                                           // flat background => safe to draw
    }, dataUri);
    const html = page({ dataUri, theme, c: { ...c0, deviceTop: 636, island: drawIsland, framed } });
    await pg.setContent(html, { waitUntil: "load" });
    await pg.evaluate(() => document.fonts.ready);
    n++;
    const out = path.join(outDir, `${String(n).padStart(2, "0")}_${key}_${theme}.jpg`);
    await pg.screenshot({ path: out, type: "jpeg", quality: 96 });
    console.log("wrote", out);
  }
  await browser.close();
})();
