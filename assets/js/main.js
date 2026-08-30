/* ==========================================================================
   ReelPath — shared behaviour
   Linked (not bundled) on every page, same pattern as style.css.
   ========================================================================== */
(function () {
  "use strict";

  function ready(fn) {
    if (document.readyState !== "loading") fn();
    else document.addEventListener("DOMContentLoaded", fn);
  }

  /* ---- Dark/light theme toggle ----
     Default is always dark -- the inline anti-flash script in <head>
     already applied data-theme="light" before paint if that was the
     saved choice, so this just wires the button and keeps localStorage
     in sync going forward. */
  function mountThemeToggle() {
    var btn = document.getElementById("themeToggle");
    if (!btn) return;
    function isLight() { return document.documentElement.getAttribute("data-theme") === "light"; }
    function reflect() { btn.setAttribute("aria-pressed", isLight() ? "true" : "false"); }
    reflect();
    btn.addEventListener("click", function () {
      var next = isLight() ? "dark" : "light";
      if (next === "light") {
        document.documentElement.setAttribute("data-theme", "light");
      } else {
        document.documentElement.removeAttribute("data-theme");
      }
      try { localStorage.setItem("reelpath-theme", next); } catch (e) {}
      reflect();
    });
  }

  /* ---- "Coming Soon" defensive date filter ----
     The rail is rebuilt daily by scripts/rebuild-coming-soon.ps1 via a
     GitHub Actions cron job, but the site is static: whatever was
     generated at the last scheduled run stays live until the next one.
     This is a client-side backstop for that gap -- if a visitor's actual
     "today" is past a card's data-release-date (the rebuild missed a day,
     ran late, etc), hide that card entirely rather than show a
     since-released title as still "coming soon". */
  function mountComingSoonFilter() {
    var track = document.getElementById("upcomingTrack");
    if (!track) return;
    var today = new Date(); today.setHours(0, 0, 0, 0);
    track.querySelectorAll(".card[data-release-date]").forEach(function (card) {
      var d = new Date(card.getAttribute("data-release-date") + "T00:00:00");
      if (!isNaN(d) && d < today) card.style.display = "none";
    });
  }

  /* ---- Site-wide search ----
     Lazy-fetches /assets/search-index.json (built by
     scripts/build-search-index.ps1) the first time the search box opens,
     caches it in memory for the rest of the page's life, and does a
     plain case-insensitive substring match against every entry's title
     on each keystroke -- no backend, no build-time query awareness
     needed. Root-relative fetch path so it resolves the same from any
     page depth (/watch-order/one-piece/filler-list.html included). */
  function mountSiteSearch() {
    var btn = document.getElementById("searchToggle");
    var box = document.getElementById("searchBox");
    var input = document.getElementById("searchInput");
    var results = document.getElementById("searchResults");
    if (!btn || !box || !input || !results) return;

    var index = null;
    var indexPromise = null;
    function loadIndex() {
      if (indexPromise) return indexPromise;
      indexPromise = fetch("/assets/search-index.json")
        .then(function (r) { return r.json(); })
        .then(function (data) { index = data.entries || []; return index; })
        .catch(function () { index = []; return index; });
      return indexPromise;
    }

    function render(query) {
      if (!query) {
        results.hidden = true;
        results.innerHTML = "";
        return;
      }
      var q = query.toLowerCase();
      var matches = (index || []).filter(function (e) {
        return e.title.toLowerCase().indexOf(q) !== -1;
      }).slice(0, 8);

      results.innerHTML = "";
      results.hidden = false;
      if (matches.length === 0) {
        var empty = document.createElement("div");
        empty.className = "search-empty";
        empty.textContent = "No matches for \"" + query + "\"";
        results.appendChild(empty);
        return;
      }
      matches.forEach(function (m) {
        var a = document.createElement("a");
        a.className = "search-result";
        a.href = m.url;
        var img = document.createElement("img");
        img.src = m.poster || "";
        img.alt = "";
        img.loading = "lazy";
        var body = document.createElement("div");
        body.className = "search-result-body";
        var title = document.createElement("div");
        title.className = "search-result-title";
        title.textContent = m.title;
        var type = document.createElement("div");
        type.className = "search-result-type";
        type.textContent = m.type;
        body.appendChild(title);
        body.appendChild(type);
        a.appendChild(img);
        a.appendChild(body);
        results.appendChild(a);
      });
    }

    function openBox() {
      box.hidden = false;
      btn.setAttribute("aria-expanded", "true");
      loadIndex().then(function () {
        if (input.value) render(input.value);
      });
      setTimeout(function () { input.focus(); }, 10);
    }
    function closeBox() {
      box.hidden = true;
      btn.setAttribute("aria-expanded", "false");
    }

    btn.addEventListener("click", function () {
      if (box.hidden) openBox(); else closeBox();
    });
    input.addEventListener("input", function () { render(input.value); });
    input.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { closeBox(); btn.focus(); }
    });
    document.addEventListener("click", function (e) {
      if (!box.hidden && !box.contains(e.target) && e.target !== btn) closeBox();
    });
  }

  /* ---- Mobile nav toggle ---- */
  function mountNavToggle() {
    var btn = document.querySelector(".nav-toggle");
    var nav = document.getElementById("navLinks");
    if (!btn || !nav) return;
    btn.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      btn.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        nav.classList.remove("open");
        btn.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* ---- Active nav link ----
     Real URL resolution (a.href, not the raw attribute) so page-relative
     hrefs resolve against *this* document — safe from nested folders like
     /watch-order/ and /best/. A trailing "/index" collapses to its parent
     so a hub link stays active on its own child pages too. */
  function mountNavActive() {
    function normPath(p) {
      return (p.replace(/\.html$/, "").replace(/\/+$/, "").replace(/\/index$/, "")) || "/";
    }
    var cur = normPath(location.pathname);
    document.querySelectorAll(".nav-links a").forEach(function (a) {
      if (a.classList.contains("nav-cta")) return;
      var raw = a.getAttribute("href") || "";
      if (!raw || raw.charAt(0) === "#") return;
      var resolvedPath;
      try { resolvedPath = new URL(a.href).pathname; } catch (e) { return; }
      var norm = normPath(resolvedPath);
      if (cur === norm || (norm !== "/" && cur.indexOf(norm + "/") === 0)) {
        a.setAttribute("aria-current", "page");
      }
    });
  }

  /* ---- 3D tilt on poster/trending cards ---- */
  function mountCardTilt() {
    document.querySelectorAll(".card").forEach(function (card) {
      card.addEventListener("mousemove", function (e) {
        var r = card.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width - 0.5;
        var y = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform = "perspective(600px) rotateY(" + x * 10 + "deg) rotateX(" + (-y * 10) + "deg) translateY(-4px)";
      });
      card.addEventListener("mouseleave", function () { card.style.transform = ""; });
    });
  }

  /* ---- Hero parallax glow + grain ---- */
  function mountHeroParallax() {
    var glow = document.getElementById("heroGlow");
    var grain = document.getElementById("heroGrain");
    if (!glow && !grain) return;
    window.addEventListener("scroll", function () {
      var y = window.scrollY;
      if (glow) glow.style.transform = "translate(-50%, " + y * 0.25 + "px)";
      if (grain) grain.style.transform = "translateY(" + y * 0.12 + "px)";
    }, { passive: true });
  }

  /* ---- Scroll-reveal ---- */
  function mountReveal() {
    var targets = document.querySelectorAll(".reveal");
    if (!targets.length) return;
    if (!("IntersectionObserver" in window)) {
      targets.forEach(function (el) { el.classList.add("in"); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry, i) {
        if (entry.isIntersecting) {
          setTimeout(function () { entry.target.classList.add("in"); }, i * 60);
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });
    targets.forEach(function (el) { io.observe(el); });
  }

  /* ---- Binary hide toggle (One Piece "skip filler", Fate "hide side stories") ----
     Any element with [data-toggle] is a switch. It hides every node in
     #pathNodes carrying the class named in [data-hide-class] when on. */
  function mountHideToggle() {
    document.querySelectorAll("[data-toggle]").forEach(function (toggle) {
      var hideClass = toggle.getAttribute("data-hide-class") || "filler";
      var nodes = document.querySelectorAll("#pathNodes .node." + hideClass);
      function setToggle(on) {
        toggle.classList.toggle("on", on);
        toggle.setAttribute("aria-checked", on);
        nodes.forEach(function (n) { n.classList.toggle("hidden", on); });
      }
      toggle.addEventListener("click", function () { setToggle(!toggle.classList.contains("on")); });
      toggle.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); setToggle(!toggle.classList.contains("on")); }
      });
    });
  }

  /* ---- Two-way order switch (MCU / Wan Universe: release vs chronological) ----
     Buttons: [data-order-btn="release|chrono"] inside .order-switch.
     Nodes:   #pathNodes .node with data-order-release / data-order-chrono
              (position number) and data-meta-release / data-meta-chrono
              (the text shown under the title). */
  function mountOrderSwitch() {
    var switches = document.querySelectorAll(".order-switch");
    switches.forEach(function (sw) {
      var buttons = sw.querySelectorAll("[data-order-btn]");
      var nodes = document.querySelectorAll("#pathNodes .node");
      function apply(order) {
        buttons.forEach(function (b) { b.classList.toggle("active", b.getAttribute("data-order-btn") === order); });
        nodes.forEach(function (n) {
          var pos = n.getAttribute("data-order-" + order);
          var meta = n.getAttribute("data-meta-" + order);
          var dot = n.querySelector(".node-dot");
          var metaEl = n.querySelector(".node-meta");
          if (pos) n.style.order = pos;
          if (dot && pos) dot.textContent = pos;
          if (metaEl && meta) metaEl.textContent = meta;
        });
      }
      buttons.forEach(function (b) {
        b.addEventListener("click", function () { apply(b.getAttribute("data-order-btn")); });
      });
    });
  }

  /* ---- Trending-rail auto-scroll (JS-driven, so arrows can share the same
     native scrollLeft instead of fighting a CSS transform animation).
     Content is duplicated x2 in the markup for a seamless loop: once we've
     scrolled past the first copy, snap back by exactly half the width. ---- */
  function mountRailAutoScroll() {
    document.querySelectorAll(".rail").forEach(function (rail) {
      var paused = false;
      var resumeTimer = null;
      var speed = 0.5; // px per frame

      rail.addEventListener("mouseenter", function () { paused = true; });
      rail.addEventListener("mouseleave", function () { paused = false; });
      rail.addEventListener("manualscroll", function () {
        paused = true;
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(function () { paused = false; }, 2500);
      });

      if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

      function tick() {
        if (!paused) {
          rail.scrollLeft += speed;
          var half = rail.scrollWidth / 2;
          if (half > 0 && rail.scrollLeft >= half) rail.scrollLeft -= half;
        }
        requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    });
  }

  /* ---- Manual arrow controls, shared by the trending rail and every
     watch-order path. Each [.scroll-region] wraps one scrollable track
     (.rail or .path-track) plus two [.scroll-arrow] buttons. ---- */
  function mountScrollArrows() {
    document.querySelectorAll(".scroll-region").forEach(function (region) {
      var track = region.querySelector(".rail, .path-track");
      var prev = region.querySelector(".scroll-arrow.prev");
      var next = region.querySelector(".scroll-arrow.next");
      if (!track || !prev || !next) return;
      var isRail = track.classList.contains("rail");

      function stepSize() {
        var child = track.querySelector(".card, .node");
        var w = child ? child.getBoundingClientRect().width : 220;
        return Math.round(w * 2 + 40);
      }
      function go(dir) {
        track.scrollBy({ left: dir * stepSize(), behavior: "smooth" });
        track.dispatchEvent(new CustomEvent("manualscroll"));
      }
      prev.addEventListener("click", function () { go(-1); });
      next.addEventListener("click", function () { go(1); });

      if (!isRail) {
        function updateArrows() {
          var max = track.scrollWidth - track.clientWidth;
          if (max <= 4) { prev.setAttribute("disabled", ""); next.setAttribute("disabled", ""); return; }
          if (track.scrollLeft <= 4) prev.setAttribute("disabled", ""); else prev.removeAttribute("disabled");
          if (track.scrollLeft >= max - 4) next.setAttribute("disabled", ""); else next.removeAttribute("disabled");
        }
        track.addEventListener("scroll", updateArrows, { passive: true });
        window.addEventListener("resize", updateArrows);
        updateArrows();
      }
    });
  }

  /* ---- "Embed this guide" widget ----
     One per franchise guide page: [data-embed-slug] toggles a code box
     containing the iframe snippet for that franchise's /embed/<slug>.html
     page, with a copy-to-clipboard button. */
  function mountEmbedWidget() {
    var btn = document.querySelector("[data-embed-slug]");
    if (!btn) return;
    var box = document.getElementById("embedCodeBox");
    var textarea = document.getElementById("embedCodeText");
    var copyBtn = document.getElementById("embedCopyBtn");
    if (!box || !textarea) return;
    btn.addEventListener("click", function () {
      box.hidden = !box.hidden;
      if (!box.hidden) { textarea.focus(); textarea.select(); }
    });
    if (copyBtn) {
      copyBtn.addEventListener("click", function () {
        textarea.select();
        var copied = false;
        try { copied = document.execCommand("copy"); } catch (e) {}
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(textarea.value).catch(function () {});
        }
        copyBtn.textContent = "Copied!";
        setTimeout(function () { copyBtn.textContent = "Copy code"; }, 1600);
      });
    }
  }

  /* ---- Homepage "signature tool" franchise switcher ----
     Four full node panels (one per franchise, reusing each franchise's own
     data) live side by side in the DOM; only one is shown at a time. Each
     franchise needs a different control below the heading: One Piece and
     Fate use the binary hide-toggle pattern, MCU and Wan Universe use the
     release/chronological order-switch — so this rewires that control's
     behaviour on every tab switch rather than reusing the generic
     single-page mount functions.

     Binge Math Box: EVERY franchise here renders it (renderBinge() is
     called from all four branches of activatePanel below) -- this is the
     established convention, not optional polish. Adding a 5th franchise
     to this demo means adding data-eps (24min/ep, anime) or data-minutes
     (real runtime, live-action) to its nodes too, same as the other four,
     so the box isn't showing a stale or missing total for it. */
  function mountFranchiseDemo() {
    var section = document.getElementById("signatureDemo");
    if (!section) return;
    var tabs = document.querySelectorAll(".franchise-tab");
    var heading = document.getElementById("demoHeading");
    var toggleRow = document.getElementById("demoToggleRow");
    var toggleLabel = document.getElementById("demoToggleLabel");
    var toggleEl = document.getElementById("demoToggle");
    var orderSwitch = document.getElementById("demoOrderSwitch");
    var modePills = document.getElementById("demoModePills");
    var bingeBox = document.getElementById("bingeBox");
    var bingeTime = document.getElementById("bingeBoxTime");
    var bingeDays = document.getElementById("bingeBoxDays");
    var footnoteLink = document.getElementById("demoLink");
    var track = section.querySelector(".path-track");
    if (!track) return;

    var config = {
      onepiece: { heading: "One Piece — the right order", mode: "toggle", label: "Skip filler", hideClass: "filler",
        link: "watch-order/one-piece.html", linkText: "See the full One Piece guide →" },
      mcu: { heading: "MCU — release or chronological", mode: "order",
        link: "watch-order/mcu.html", linkText: "See the full MCU guide →" },
      fate: { heading: "Fate — the core path, untangled", mode: "toggle", label: "Hide side stories", hideClass: "side",
        link: "watch-order/fate.html", linkText: "See the full Fate guide →" },
      wan: { heading: "Wan Universe — release or chronological", mode: "order",
        link: "watch-order/wan-universe.html", linkText: "See the full Wan Universe guide →" },
      onepieceModes: {
        modes: [
          { key: "complete", label: "Complete" },
          { key: "essentials", label: "Story Essentials" },
          { key: "fastest", label: "Fastest Route" }
        ]
      },
      mcuModes: {
        modes: [
          { key: "release", label: "Release Order" },
          { key: "chrono", label: "Chronological Order" },
          { key: "movies", label: "Movies Only" },
          { key: "essential", label: "Essential" }
        ]
      }
    };

    /* ---- Binge Math Box: sums whatever's currently visible in `nodes`
       and renders "≈Xh" + "at 2h/day → ≈Y days". `unit` picks how each
       node's runtime is read: "eps24" reads data-eps and multiplies by
       24min/episode (One Piece), "minutes" reads data-minutes directly
       (MCU). `factor` is an extra multiplier (used for One Piece's
       "Fastest Route", which assumes ~5% of runtime is skippable
       recap/preview padding even within kept episodes). ---- */
    function renderBinge(nodes, unit, factor) {
      if (!bingeBox) return;
      var totalMin = 0;
      nodes.forEach(function (n) {
        if (n.classList.contains("hidden") || n.style.display === "none") return;
        if (unit === "eps24") {
          var eps = parseFloat(n.getAttribute("data-eps") || "0");
          totalMin += eps * 24;
        } else {
          totalMin += parseFloat(n.getAttribute("data-minutes") || "0");
        }
      });
      totalMin *= (factor || 1);
      var hours = totalMin / 60;
      var days = Math.max(1, Math.ceil(hours / 2));
      bingeTime.textContent = "≈" + Math.round(hours) + " hours";
      bingeDays.textContent = "at 2h/day → ≈" + days + " days";
      bingeBox.style.display = "";
    }

    function activatePanel(key, panel) {
      var cfg = config[key];
      heading.textContent = cfg.heading;
      footnoteLink.setAttribute("href", cfg.link);
      footnoteLink.textContent = cfg.linkText;

      if (key === "onepiece") {
        toggleRow.style.display = "none";
        orderSwitch.style.display = "none";
        modePills.style.display = "";
        modePills.innerHTML = "";
        var allNodes = panel.querySelectorAll(".node");
        var fillerNodes = panel.querySelectorAll(".node.filler");
        config.onepieceModes.modes.forEach(function (m) {
          var b = document.createElement("button");
          b.type = "button";
          b.textContent = m.label;
          b.setAttribute("data-mode", m.key);
          if (m.key === "complete") b.classList.add("active");
          modePills.appendChild(b);
        });
        function applyOpMode(modeKey) {
          modePills.querySelectorAll("button").forEach(function (b) {
            b.classList.toggle("active", b.getAttribute("data-mode") === modeKey);
          });
          var showFiller = modeKey === "complete";
          fillerNodes.forEach(function (n) { n.classList.toggle("hidden", !showFiller); });
          var factor = modeKey === "fastest" ? 0.95 : 1;
          renderBinge(allNodes, "eps24", factor);
        }
        modePills.querySelectorAll("button").forEach(function (b) {
          b.onclick = function () { applyOpMode(b.getAttribute("data-mode")); };
        });
        applyOpMode("complete");
      } else if (key === "mcu") {
        toggleRow.style.display = "none";
        orderSwitch.style.display = "none";
        modePills.style.display = "";
        modePills.innerHTML = "";
        var mcuNodes = panel.querySelectorAll(".node");
        config.mcuModes.modes.forEach(function (m) {
          var b = document.createElement("button");
          b.type = "button";
          b.textContent = m.label;
          b.setAttribute("data-mode", m.key);
          if (m.key === "release") b.classList.add("active");
          modePills.appendChild(b);
        });
        function applyMcuMode(modeKey) {
          modePills.querySelectorAll("button").forEach(function (b) {
            b.classList.toggle("active", b.getAttribute("data-mode") === modeKey);
          });
          var orderAttr = modeKey === "chrono" ? "chrono" : "release";
          mcuNodes.forEach(function (n) {
            var pos = n.getAttribute("data-order-" + orderAttr);
            var meta = n.getAttribute("data-meta-" + orderAttr);
            var dot = n.querySelector(".node-dot");
            var metaEl = n.querySelector(".node-meta");
            if (pos) n.style.order = pos;
            if (dot && pos) dot.textContent = pos;
            if (metaEl && meta) metaEl.textContent = meta;
            var isEssential = n.getAttribute("data-essential") === "1";
            n.classList.toggle("hidden", modeKey === "essential" && !isEssential);
          });
          renderBinge(mcuNodes, "minutes", 1);
        }
        modePills.querySelectorAll("button").forEach(function (b) {
          b.onclick = function () { applyMcuMode(b.getAttribute("data-mode")); };
        });
        applyMcuMode("release");
      } else if (cfg.mode === "toggle") {
        toggleRow.style.display = "";
        orderSwitch.style.display = "none";
        modePills.style.display = "none";
        toggleLabel.textContent = cfg.label;
        toggleEl.classList.remove("on");
        toggleEl.setAttribute("aria-checked", "false");
        var hideNodes = panel.querySelectorAll(".node." + cfg.hideClass);
        var allToggleNodes = panel.querySelectorAll(".node");
        hideNodes.forEach(function (n) { n.classList.remove("hidden"); });
        renderBinge(allToggleNodes, "minutes", 1);
        var handler = function () {
          var on = !toggleEl.classList.contains("on");
          toggleEl.classList.toggle("on", on);
          toggleEl.setAttribute("aria-checked", on);
          hideNodes.forEach(function (n) { n.classList.toggle("hidden", on); });
          renderBinge(allToggleNodes, "minutes", 1);
        };
        toggleEl.onclick = handler;
        toggleEl.onkeydown = function (e) {
          if (e.key === "Enter" || e.key === " ") { e.preventDefault(); handler(); }
        };
      } else {
        toggleRow.style.display = "none";
        orderSwitch.style.display = "";
        modePills.style.display = "none";
        var buttons = orderSwitch.querySelectorAll("[data-order-btn]");
        var nodes = panel.querySelectorAll(".node");
        function apply(order) {
          buttons.forEach(function (b) { b.classList.toggle("active", b.getAttribute("data-order-btn") === order); });
          nodes.forEach(function (n) {
            var pos = n.getAttribute("data-order-" + order);
            var meta = n.getAttribute("data-meta-" + order);
            var dot = n.querySelector(".node-dot");
            var metaEl = n.querySelector(".node-meta");
            if (pos) n.style.order = pos;
            if (dot && pos) dot.textContent = pos;
            if (metaEl && meta) metaEl.textContent = meta;
          });
          renderBinge(nodes, "minutes", 1);
        }
        buttons.forEach(function (b) {
          b.onclick = function () { apply(b.getAttribute("data-order-btn")); };
        });
        var activeBtn = orderSwitch.querySelector(".active") || buttons[0];
        apply(activeBtn.getAttribute("data-order-btn"));
      }
    }

    var currentKey = "onepiece";
    function switchTo(key) {
      var newPanel = section.querySelector('.path-nodes[data-franchise-panel="' + key + '"]');
      var oldPanel = section.querySelector('.path-nodes[data-franchise-panel="' + currentKey + '"]');
      if (!newPanel || key === currentKey) return;
      currentKey = key;
      tabs.forEach(function (t) { t.classList.toggle("active", t.getAttribute("data-franchise") === key); });

      var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (oldPanel && !reduceMotion) {
        oldPanel.classList.add("demo-fade-out");
        setTimeout(function () {
          oldPanel.style.display = "none";
          oldPanel.classList.remove("demo-fade-out");
          newPanel.style.display = "flex";
          newPanel.classList.add("demo-fade-in");
          track.scrollLeft = 0;
          activatePanel(key, newPanel);
          requestAnimationFrame(function () { newPanel.classList.remove("demo-fade-in"); });
        }, 200);
      } else {
        if (oldPanel) oldPanel.style.display = "none";
        newPanel.style.display = "flex";
        track.scrollLeft = 0;
        activatePanel(key, newPanel);
      }
    }

    tabs.forEach(function (t) {
      t.addEventListener("click", function () { switchTo(t.getAttribute("data-franchise")); });
    });

    var initial = section.querySelector('.path-nodes[data-franchise-panel="onepiece"]');
    if (initial) activatePanel("onepiece", initial);
  }

  ready(function () {
    mountThemeToggle();
    mountSiteSearch();
    mountNavToggle();
    mountNavActive();
    mountCardTilt();
    mountHeroParallax();
    mountReveal();
    mountHideToggle();
    mountOrderSwitch();
    mountRailAutoScroll();
    mountScrollArrows();
    mountFranchiseDemo();
    mountEmbedWidget();
    mountComingSoonFilter();
    var yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = new Date().getFullYear();
  });
})();
