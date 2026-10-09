// Designed App Store screenshots from real Simulator captures.
//
//   npm i --no-save playwright          (once; uses your installed Google Chrome, no download)
//   node appstore/make_designed_screenshots.cjs <rawDir> <outDir> [ipad]
//   (add "ipad" for the 13" iPad canvas, 2064x2752; default is the 6.9" iPhone canvas, 1320x2868)
//
// Input PNGs (scanned recursively):
//   * REAL SIMULATOR WINDOW captures (preferred): the whole Simulator window with Apple's real
//     iPhone bezel, e.g. `screencapture -o -l <windowId> week_framed.png` (transparent corners).
//     Put "framed" in the file name; placed as-is, no frame is drawn.
//   * Plain screen captures (`simctl io screenshot`, 1320x2868): a simple frame is drawn.
// A path/name containing "dark" => dark slide (dark app theme + dark palette), else light.
// The copy (headline, chips) is picked by keyword in the file name
// (week|home, reader, topics, picker|parash, search, settings, stats) from screenshot_copy.json.
// A closing "brand" slide (icon + feature chips) is generated automatically.
// Output: JPEG (flattened, no alpha), 1320x2868 (iPhone) or 2064x2752 (iPad).
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const [rawDir, outDir, mode] = process.argv.slice(2);
const IPAD = mode === "ipad";
// Design space is always 1320 wide; the iPad canvas is the same design zoomed to 2064 wide and a
// shorter, squarer device. `dH` is the design-space height.
const PROF = IPAD
  ? { W: 2064, H: 2752, k: 2064 / 1320, dH: Math.round(2752 / (2064 / 1320)), devLeft: 236, devW: 848, devH: 1121, scrW: 820, scrH: 1093, devR: 70, scrR: 58, pad: 14,
      framedLeft: 40, framedW: 1240, framedH: 1130, deviceTop: 595, chipScale: 1121 / 2203,
      brand: { markTop: 150, markSize: 520, btTop: 720, featTop: 1180 } }
  : { W: 1320, H: 2868, k: 1, dH: 2868, devLeft: 146, devW: 1028, devH: 2203, scrW: 1000, scrH: 2175, devR: 138, scrR: 124, pad: 14,
      framedLeft: 40, framedW: 1240, framedH: 2230, deviceTop: 636, chipScale: 1,
      brand: { markTop: 430, markSize: 600, btTop: 1150, featTop: 1830 } };
if (!rawDir || !outDir) { console.error("usage: node make_designed_screenshots.cjs <rawDir> <outDir>"); process.exit(1); }
const copy = JSON.parse(fs.readFileSync(path.join(__dirname, "screenshot_copy.json"), "utf8"));
const font = f => "file://" + path.join(__dirname, "fonts", f);
const iconUri = "data:image/png;base64," + fs.readFileSync(path.join(__dirname, "..", "www", "icon-512.png")).toString("base64");

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
const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
const headlineHtml = lines => lines.map(l =>
  `<div class="hl-line">${esc(l).replace(/\{([^}]+)\}/g, '<em>$1</em>')}</div>`).join("");

const ICONS = {
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  book: '<path d="M12 6.5C10 5 7 4.5 4 5v13c3-.5 6 0 8 1.5 2-1.5 5-2 8-1.5V5c-3-.5-6 0-8 1.5z"/><path d="M12 6.5v13"/>',
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>',
  tag: '<path d="M3.5 12.5V4.5h8l9 9-8 8z"/><circle cx="8" cy="8.5" r="1.3"/>',
  check: '<circle cx="12" cy="12" r="9"/><path d="M8 12.3l2.8 2.8L16.5 9.5"/>',
  flame: '<path d="M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5.3 1.5 1 2 1.8 2.2C10.5 8 11 5.5 12 3z"/>',
  star: '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.8 6.8 19.6l1-5.8-4.3-4.1 5.9-.8z"/>',
  share: '<path d="M12 15V4M8 8l4-4 4 4M6 11h-.5A1.5 1.5 0 0 0 4 12.5v6A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-6a1.5 1.5 0 0 0-1.5-1.5H18"/>',
  textsize: '<path d="M4 19l5-13 5 13M5.8 14.5h6.4M15 19l3-8 3 8M16 17h4"/>',
  cloud: '<path d="M5 18h12.5a4 4 0 0 0 .5-8 6 6 0 0 0-11.5-1A5 5 0 0 0 5 18z"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"/>',
  sparkle: '<path d="M12 2l1.8 7.2L21 12l-7.2 2.8L12 22l-1.8-7.2L3 12l7.2-2.8z"/>',
};
const icon = n => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICONS[n] || ICONS.sparkle}</svg>`;
const SPARKLES = [[1210, 150, 30], [96, 300, 22], [1236, 830, 26], [64, 1880, 24], [1244, 2330, 30], [96, 2640, 22]];

function palette(dark) {
  return dark ? {
    bg: "radial-gradient(90% 45% at 12% 0%,rgba(63,132,138,.40),transparent 70%),radial-gradient(80% 40% at 100% 100%,rgba(191,149,48,.22),transparent 70%),linear-gradient(180deg,#0A141C 0%,#0E212D 55%,#0A1822 100%)",
    ink: "#FFF8E4", gold1: "#F6DE96", gold2: "#D9AE45", sub: "#A9BBC4", pillInk: "#E7D49E", pillBorder: "rgba(231,212,158,.5)",
    pillBg: "rgba(231,212,158,.08)", chipBg: "rgba(14,33,45,.94)", chipInk: "#FFF3D6", chipBorder: "rgba(217,174,69,.65)", chipIcon: "#E7C25C",
    chipShadow: "0 16px 40px rgba(0,0,0,.5)", spark: "#E7C25C", devShadow: "rgba(0,0,0,.62)",
    bezel: "#05090D", edge: "rgba(255,255,255,.18)", plate: "rgba(231,212,158,.07)"
  } : {
    bg: "radial-gradient(90% 45% at 0% 0%,rgba(63,132,138,.26),transparent 70%),radial-gradient(80% 40% at 100% 100%,rgba(191,149,48,.30),transparent 70%),linear-gradient(180deg,#FFFDF6 0%,#F6EFDC 55%,#EAD9A6 100%)",
    ink: "#0F314D", gold1: "#CFA02F", gold2: "#8A6A1E", sub: "#5C6B72", pillInk: "#8A6A1E", pillBorder: "rgba(138,106,30,.5)",
    pillBg: "rgba(255,253,246,.7)", chipBg: "#FFFFFF", chipInk: "#0F314D", chipBorder: "rgba(191,149,48,.6)", chipIcon: "#B8892A",
    chipShadow: "0 16px 40px rgba(15,49,77,.22)", spark: "#C99A2B", devShadow: "rgba(15,49,77,.38)",
    bezel: "#0E141A", edge: "rgba(255,255,255,.28)", plate: "rgba(191,149,48,.10)"
  };
}

function baseCss(P) {
  return `
@font-face{font-family:Heebo;font-weight:500;src:url("${font("Heebo-Medium.ttf")}")}
@font-face{font-family:Heebo;font-weight:700;src:url("${font("Heebo-Bold.ttf")}")}
@font-face{font-family:Heebo;font-weight:800;src:url("${font("Heebo-ExtraBold.ttf")}")}
*{box-sizing:border-box;margin:0;padding:0}
html{width:${PROF.W}px;height:${PROF.H}px;overflow:hidden}
body{width:1320px;height:${PROF.dH}px;zoom:${PROF.k};overflow:hidden;background:${P.bg};position:relative;font-family:Heebo,sans-serif}
.copy{position:absolute;top:64px;left:0;right:0;text-align:center;padding:0 70px}
.pill{display:inline-block;font-weight:700;font-size:34px;color:${P.pillInk};border:2.5px solid ${P.pillBorder};background:${P.pillBg};border-radius:999px;padding:9px 38px 11px}
.hl{margin-top:26px;font-weight:800;font-size:124px;line-height:1.06;letter-spacing:-.01em;color:${P.ink}}
.hl em{font-style:normal;background:linear-gradient(100deg,${P.gold1},${P.gold2});-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{margin-top:24px;font-weight:500;font-size:44px;line-height:1.32;color:${P.sub};white-space:pre-line}
.spark{position:absolute;color:${P.spark};opacity:.75}
.spark svg{display:block;width:100%;height:100%;fill:currentColor;stroke:none}
.chip{position:absolute;display:flex;align-items:center;gap:18px;height:88px;padding:0 34px 0 30px;border-radius:999px;background:${P.chipBg};
  border:2.5px solid ${P.chipBorder};color:${P.chipInk};font-weight:700;font-size:37px;white-space:nowrap;box-shadow:${P.chipShadow};z-index:5}
.chip svg{width:42px;height:42px;color:${P.chipIcon};flex:none}
`;
}
const sparkles = () => SPARKLES.map(([x, y, s]) => `<div class="spark" style="left:${x}px;top:${Math.round(y * PROF.dH / 2868)}px;width:${s}px;height:${s}px">${icon("sparkle")}</div>`).join("");
const chipsHtml = chips => (chips || []).map(c =>
  `<div class="chip" style="top:${Math.round(PROF.deviceTop + (c.top - 636) * PROF.chipScale)}px;${c.side === "left" ? "left:22px" : "right:22px"}">${icon(c.icon)}<span>${esc(c.t)}</span></div>`).join("");

function slidePage({ dataUri, dark, c }) {
  const P = palette(dark);
  const device = c.framed
    ? `<div class="framed"><img src="${dataUri}"></div>`
    : `<div class="device"><div class="screen"><img src="${dataUri}">${c.island ? '<div class="island"></div>' : ""}<div class="sheen"></div></div></div>`;
  return `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><style>${baseCss(P)}
.device{position:absolute;left:${PROF.devLeft}px;top:${c.deviceTop}px;width:${PROF.devW}px;height:${PROF.devH}px;border-radius:${PROF.devR}px;background:${P.bezel};box-shadow:0 50px 110px ${P.devShadow};padding:${PROF.pad}px}
.device:before{content:"";position:absolute;inset:0;border-radius:${PROF.devR}px;box-shadow:inset 0 0 0 3px ${P.edge};pointer-events:none}
.screen{position:relative;width:${PROF.scrW}px;height:${PROF.scrH}px;border-radius:${PROF.scrR}px;overflow:hidden;background:#000}
.screen img{display:block;width:${PROF.scrW}px;height:${PROF.scrH}px}
.island{position:absolute;left:50%;top:28px;width:270px;height:80px;margin-left:-135px;border-radius:46px;background:#000}
.sheen{position:absolute;inset:0;border-radius:${PROF.scrR}px;background:linear-gradient(115deg,rgba(255,255,255,.10),transparent 28%);pointer-events:none}
.framed{position:absolute;left:${PROF.framedLeft}px;top:${c.deviceTop - 10}px;width:${PROF.framedW}px;height:${PROF.framedH}px;display:flex;align-items:flex-start;justify-content:center}
.framed img{max-width:100%;max-height:100%;display:block;filter:drop-shadow(0 50px 70px ${P.devShadow})}
</style></head><body>
${sparkles()}
<div class="copy">
  <div class="pill">${esc(c.eyebrow)}</div>
  <div class="hl">${headlineHtml(c.headline)}</div>
  <div class="sub">${esc(c.sub)}</div>
</div>
${device}
${chipsHtml(c.chips)}
</body></html>`;
}

function brandPage({ dark, c }) {
  const P = palette(dark);
  return `<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><style>${baseCss(P)}
.mark{position:absolute;left:50%;top:${PROF.brand.markTop}px;width:${PROF.brand.markSize}px;height:${PROF.brand.markSize}px;margin-left:-${PROF.brand.markSize / 2}px;border-radius:50%;
  box-shadow:0 0 0 14px ${P.pillBg},0 0 0 18px ${P.pillBorder},0 50px 110px ${P.devShadow};overflow:hidden}
.mark img{width:100%;height:100%;display:block;object-fit:cover}
.bt{position:absolute;top:${PROF.brand.btTop}px;left:0;right:0;text-align:center;padding:0 60px}
.bt .hl{font-size:132px;margin-top:0}
.bt .sub{font-size:52px;margin-top:30px}
.feat{position:absolute;top:${PROF.brand.featTop}px;left:90px;right:90px;display:flex;flex-wrap:wrap;gap:30px 26px;justify-content:center}
.feat .chip{position:static;height:104px;font-size:44px;gap:20px;padding:0 40px 0 36px}
.feat .chip svg{width:50px;height:50px}
</style></head><body>
${sparkles()}
<div class="mark"><img src="${iconUri}"></div>
<div class="bt"><div class="hl">${headlineHtml(c.headline)}</div><div class="sub">${esc(c.sub)}</div></div>
<div class="feat">${(c.features || []).map(f => `<div class="chip">${icon(f.icon)}<span>${esc(f.t)}</span></div>`).join("")}</div>
</body></html>`;
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const files = walk(rawDir).map(f => ({ f, key: keyOf(f), theme: /dark/i.test(f) ? "dark" : "light" })).filter(x => x.key);
  files.sort((a, b) => copy.order.indexOf(a.key) - copy.order.indexOf(b.key) || a.theme.localeCompare(b.theme));
  let browser;
  try { browser = await chromium.launch({ channel: "chrome" }); } catch (e) { browser = await chromium.launch(); }
  const ctx = await browser.newContext({ viewport: { width: PROF.W, height: PROF.H }, deviceScaleFactor: 1 });
  const pg = await ctx.newPage();
  let n = 0;
  const shoot = async (html, name) => {
    await pg.setContent(html, { waitUntil: "load" });
    await pg.evaluate(() => document.fonts.ready);
    n++;
    const out = path.join(outDir, `${String(n).padStart(2, "0")}_${name}.jpg`);
    await pg.screenshot({ path: out, type: "jpeg", quality: 96 });
    console.log("wrote", out);
  };
  for (const { f, key, theme } of files) {
    const slide = copy.slides[key]; const c0 = { ...slide.light, ...(slide[theme] || {}) };
    const dataUri = "data:image/png;base64," + fs.readFileSync(f).toString("base64");
    const framed = /framed/i.test(f);
    const drawIsland = framed ? false : await pg.evaluate(async uri => {
      const im = new Image(); im.src = uri; await im.decode();
      const cv = document.createElement("canvas"); cv.width = im.width; cv.height = im.height;
      const cx = cv.getContext("2d"); cx.drawImage(im, 0, 0);
      const x = Math.round(im.width * .5), y = Math.round(im.height * .0135);
      const d = cx.getImageData(x - 40, y - 4, 80, 8).data; let dark = 0;
      for (let i = 0; i < d.length; i += 4) if (d[i] < 30 && d[i + 1] < 30 && d[i + 2] < 30) dark++;
      if (dark > d.length / 4 * .85) return false;
      const r = cx.getImageData(x - 146, 30, 292, 86).data; let mn = 255, mx = 0;
      for (let i = 0; i < r.length; i += 4) { const l = (r[i] + r[i + 1] + r[i + 2]) / 3; mn = Math.min(mn, l); mx = Math.max(mx, l); }
      return mx - mn < 40;
    }, dataUri);
    await shoot(slidePage({ dataUri, dark: theme === "dark", c: { ...c0, deviceTop: PROF.deviceTop, island: drawIsland, framed } }), `${key}_${theme}`);
  }
  if (copy.slides.brand) await shoot(brandPage({ dark: false, c: copy.slides.brand.light }), "brand");
  await browser.close();
})();
