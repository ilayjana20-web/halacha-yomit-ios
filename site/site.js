// תנועה לדף הנחיתה: צופה גלילה אחד (rAF) מניע הכל, רק transform/opacity זזים.
(() => {
  const root = document.documentElement;
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));

  // חשיפה בגלילה
  if (still) document.querySelectorAll(".rv").forEach(el => el.classList.add("in"));
  else {
    const io = new IntersectionObserver(es => es.forEach(e => {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }), { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    document.querySelectorAll(".rv").forEach(el => io.observe(el));
    setTimeout(() => document.querySelectorAll(".rv").forEach(el => {
      if (el.getBoundingClientRect().top < innerHeight * 0.95) { el.classList.add("in"); io.unobserve(el); }
    }), 60);
  }

  // מילים שנדלקות תוך כדי גלילה
  const wordBlocks = [...document.querySelectorAll("[data-words]")].map(el => {
    const gold = new Set((el.dataset.gold || "").split("|").filter(Boolean));
    const words = el.textContent.trim().split(/\s+/);
    el.textContent = "";
    const spans = words.map((w, i) => {
      const s = document.createElement("span");
      s.className = "w" + ([...gold].some(g => w.replace(/[.,:]/g, "") === g) ? " g" : "");
      s.textContent = w;
      el.appendChild(s);
      if (i < words.length - 1) el.appendChild(document.createTextNode(" "));
      return s;
    });
    if (still) spans.forEach(s => s.classList.add("lit"));
    return { el, spans };
  });

  const frame = () => {
    if (still) return;
    for (const { el, spans } of wordBlocks) {
      const r = el.getBoundingClientRect();
      if (r.bottom < 0 || r.top > innerHeight) continue;
      const p = clamp((innerHeight * 0.85 - r.top) / (r.height + innerHeight * 0.4));
      const n = Math.round(p * spans.length);
      if (el._n === n) continue;
      el._n = n;
      spans.forEach((w, i) => w.classList.toggle("lit", i < n));
    }
  };
  let ticking = false;
  const onScroll = () => { if (!ticking) { ticking = true; requestAnimationFrame(() => { frame(); ticking = false; }); } };
  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", onScroll);
  frame();

  // מתג בהיר/כהה בהירו — לחיצה, וגם מתהפך לבד כל כמה שניות עד שלוחצים
  document.querySelectorAll(".switch-host").forEach(host => {
    const flip = (manual) => {
      if (host.dataset.manual && !manual) return;
      if (manual) host.dataset.manual = "1";
      const on = !host.classList.contains("is-on");
      host.classList.toggle("is-on", on);
      host.querySelectorAll(".dev").forEach(d => d.classList.toggle("on", on));
      const sw = host.querySelector(".switch-ui"); if (sw) sw.setAttribute("aria-pressed", on);
    };
    const btn = host.querySelector(".switch-ui");
    if (btn) btn.addEventListener("click", () => flip(true));
    if (!still && host.dataset.auto !== undefined) {
      setTimeout(() => { flip(false); setInterval(() => flip(false), 3200); }, 1500);
    }
  });

  // סיפור דביק: המכשיר מציג את הצילום של השלב שבמרכז המסך
  document.querySelectorAll(".story").forEach(story => {
    const steps = [...story.querySelectorAll(".story-step")];
    const shots = [...story.querySelectorAll(".story-stick .scr img")];
    const dots = [...story.querySelectorAll(".dots i")];
    const show = i => [steps, shots, dots].forEach(list => list.forEach((el, k) => el.classList.toggle("on", k === i)));
    const sio = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) show(steps.indexOf(e.target)); }),
      { rootMargin: "-42% 0px -42% 0px" });
    steps.forEach(s => sio.observe(s));
    show(0);
  });
})();
