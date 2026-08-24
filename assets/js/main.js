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

  ready(function () {
    mountNavToggle();
    mountNavActive();
    mountCardTilt();
    mountHeroParallax();
    mountReveal();
    mountHideToggle();
    mountOrderSwitch();
    mountRailAutoScroll();
    mountScrollArrows();
    var yearEl = document.getElementById("year");
    if (yearEl) yearEl.textContent = new Date().getFullYear();
  });
})();
