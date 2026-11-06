// Language, theme, latest DMG, copy buttons and the motion shared by the page.
// Charts and the scripted hero live in charts.js.
(function () {
  'use strict';

  // ---- Configuration -------------------------------------------------------
  // Public repository with the code, the release DMGs and the Homebrew cask.
  var REPO = window.PH_REPO;
  // --------------------------------------------------------------------------

  var RELEASES_URL = 'https://github.com/' + REPO + '/releases';
  var calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var keyPrefix = window.PH_SITE + '-';

  var store = {
    get: function (k) { try { return localStorage.getItem(keyPrefix + k); } catch (e) { return null; } },
    set: function (k, v) { try { localStorage.setItem(keyPrefix + k, v); } catch (e) {} }
  };

  // ---- Language ------------------------------------------------------------
  var en = { 'dl.mac.version': 'Latest: {v}', 'copied': 'Copied' };
  var lang = 'en';
  var select = document.getElementById('lang-select');
  var listeners = [];

  document.querySelectorAll('[data-i18n]').forEach(function (el) {
    en[el.getAttribute('data-i18n')] = el.innerHTML;
  });
  document.querySelectorAll('[data-i18n-attr]').forEach(function (el) {
    el.getAttribute('data-i18n-attr').split(';').forEach(function (pair) {
      var p = pair.split(':');
      en[p[1]] = el.getAttribute(p[0]);
    });
  });
  en['meta.title'] = document.title;
  en['meta.description'] = document.querySelector('meta[name="description"]').content;

  function t(key) {
    var dict = lang === 'en' ? en : (window.PH_STRINGS[lang] || {});
    return dict[key] != null ? dict[key] : en[key];
  }

  // Wraps the words of the headline so they can rise in one after the other.
  function splitWords(el) {
    var i = 0;
    function wrap(node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (child) {
        if (child.nodeType === 1) { if (child.tagName !== 'WBR') wrap(child); return; }
        if (child.nodeType !== 3) return;
        var frag = document.createDocumentFragment();
        child.textContent.split(/(\s+)/).forEach(function (part) {
          if (!part) return;
          if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(' ')); return; }
          var span = document.createElement('span');
          span.className = 'word';
          span.style.setProperty('--i', i++);
          span.textContent = part;
          frag.appendChild(span);
        });
        node.replaceChild(frag, child);
      });
    }
    wrap(el);
  }

  function applyLang(next) {
    lang = window.PH_STRINGS[next] || next === 'en' ? next : 'en';
    document.documentElement.lang = lang;
    select.value = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      el.innerHTML = t(el.getAttribute('data-i18n'));
      if (el.hasAttribute('data-split')) splitWords(el);
    });
    document.querySelectorAll('[data-i18n-attr]').forEach(function (el) {
      el.getAttribute('data-i18n-attr').split(';').forEach(function (pair) {
        var p = pair.split(':');
        el.setAttribute(p[0], t(p[1]));
      });
    });
    document.title = t('meta.title');
    document.querySelector('meta[name="description"]').content = t('meta.description');
    renderVersion();
    listeners.forEach(function (fn) { fn(lang); });
  }

  // Other languages load on demand; the first one was chosen in <head>.
  function loadLang(next, done) {
    if (next === 'en' || window.PH_STRINGS[next]) { done(); return; }
    var script = document.createElement('script');
    script.src = 'i18n/' + next + '.js';
    script.onload = done;
    document.head.appendChild(script);
  }

  select.addEventListener('change', function () {
    var next = select.value;
    store.set('lang', next);
    // Keep a ?lang= in the address bar in step, so reloads and shared links match.
    var url = new URL(location.href);
    if (url.searchParams.has('lang')) { url.searchParams.set('lang', next); history.replaceState(null, '', url); }
    loadLang(next, function () { applyLang(next); });
  });

  // ---- Theme ---------------------------------------------------------------
  var root = document.documentElement;
  var media = window.matchMedia('(prefers-color-scheme: dark)');
  function effectiveTheme() { return root.dataset.theme || (media.matches ? 'dark' : 'light'); }
  document.getElementById('theme-toggle').addEventListener('click', function () {
    var next = effectiveTheme() === 'dark' ? 'light' : 'dark';
    // Going back to what the system prefers clears the override.
    if ((next === 'dark') === media.matches) { delete root.dataset.theme; store.set('theme', ''); }
    else { root.dataset.theme = next; store.set('theme', next); }
  });

  // ---- Repository links ----------------------------------------------------
  document.getElementById('releases-link').href = RELEASES_URL;
  document.getElementById('issues-link').href = 'https://github.com/' + REPO + '/issues';
  document.getElementById('source-link').href = 'https://github.com/' + REPO;

  // ---- Latest DMG ----------------------------------------------------------
  var dmgLink = document.getElementById('dmg-link');
  var heroMac = document.getElementById('hero-mac');
  var latestVersion = null;
  dmgLink.href = RELEASES_URL + '/latest';

  function renderVersion() {
    var el = document.getElementById('dmg-version');
    el.textContent = latestVersion ? t('dl.mac.version').replace('{v}', latestVersion) : '';
  }

  if (window.fetch) {
    fetch('https://api.github.com/repos/' + REPO + '/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (rel) {
        var dmg = (rel.assets || []).filter(function (a) { return /\.dmg$/i.test(a.name); })[0];
        if (!dmg) return;
        dmgLink.href = dmg.browser_download_url;
        heroMac.href = dmg.browser_download_url;
        latestVersion = (rel.tag_name || '').replace(/^v/, '');
        renderVersion();
      })
      .catch(function () { /* keep the releases-page fallback */ });
  }

  // ---- Copy buttons --------------------------------------------------------
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = document.getElementById(btn.getAttribute('data-copy')).textContent;
      var done = function () {
        btn.textContent = t('copied');
        setTimeout(function () { btn.textContent = t('copy'); }, 1600);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
    });
  });

  // ---- What charts.js works with -------------------------------------------
  function nf(options) { return new Intl.NumberFormat(lang, options); }
  window.PH = {
    calm: calm,
    t: t,
    lang: function () { return lang; },
    // Strings charts.js builds itself; the English lives there, the rest in i18n/.
    addEn: function (strings) { Object.keys(strings).forEach(function (k) { en[k] = strings[k]; }); },
    onLang: function (fn) { listeners.push(fn); fn(lang); },
    num: function (v, digits) { return nf({ maximumFractionDigits: digits || 0 }).format(v); },
    money: function (v, digits) { return nf({ style: 'currency', currency: 'USD', minimumFractionDigits: digits || 0, maximumFractionDigits: digits || 0 }).format(v); },
    pct: function (v, signed) { return nf({ style: 'percent', maximumFractionDigits: 1, signDisplay: signed ? 'exceptZero' : 'auto' }).format(v / 100); },
    // True while the element is near the viewport and the tab is showing.
    inView: function (el) {
      if (document.hidden) return false;
      var r = el.getBoundingClientRect();
      return r.bottom > -100 && r.top < window.innerHeight + 100;
    }
  };

  applyLang(window.PH_LANG);

  // ---- Reveal on scroll ----------------------------------------------------
  var reveals = document.querySelectorAll('.rv');
  if ('IntersectionObserver' in window && !calm) {
    var revealer = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('in');
        revealer.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: .08 });
    reveals.forEach(function (el) {
      // Neighbours in a row arrive one after the other.
      var siblings = Array.prototype.filter.call(el.parentNode.children, function (c) { return c.classList.contains('rv'); });
      el.style.setProperty('--rd', Math.min(siblings.indexOf(el), 5) * 70 + 'ms');
      revealer.observe(el);
    });
  } else {
    reveals.forEach(function (el) { el.classList.add('in'); });
  }

  // ---- Scroll: progress bar, nav, setup line -------------------------------
  var nav = document.querySelector('.nav');
  var bar = document.getElementById('progress');
  var steps = document.getElementById('steps');
  var ticking = false;

  function onScroll() {
    ticking = false;
    var y = window.scrollY;
    var vh = window.innerHeight;
    var max = document.documentElement.scrollHeight - vh;
    bar.style.transform = 'scaleX(' + (max > 0 ? y / max : 0) + ')';
    nav.classList.toggle('scrolled', y > 24);
    var box = steps.getBoundingClientRect();
    var p = Math.min(1, Math.max(0, (vh * .85 - box.top) / (vh * .55)));
    steps.style.setProperty('--p', calm ? 1 : p);
  }
  function requestScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(onScroll);
  }
  window.addEventListener('scroll', requestScroll, { passive: true });
  window.addEventListener('resize', requestScroll);
  onScroll();

  // ---- The desk leans towards the pointer ----------------------------------
  var desk = document.getElementById('desk');
  if (!calm && window.matchMedia('(hover: hover)').matches) {
    document.querySelector('.hero').addEventListener('pointermove', function (e) {
      var r = desk.getBoundingClientRect();
      var x = (e.clientX - r.left) / r.width - .5;
      var y = (e.clientY - r.top) / r.height - .5;
      desk.style.setProperty('--ry', (-5 + x * 7).toFixed(2) + 'deg');
      desk.style.setProperty('--rx', (2 - y * 5).toFixed(2) + 'deg');
    });
  }

  // ---- Spotlight on the tiles ----------------------------------------------
  document.querySelectorAll('[data-spot]').forEach(function (el) {
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      el.style.setProperty('--x', e.clientX - r.left + 'px');
      el.style.setProperty('--y', e.clientY - r.top + 'px');
    });
  });
})();
