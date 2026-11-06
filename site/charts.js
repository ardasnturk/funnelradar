// Charts and the scripted hero. Every number here is made up: they are FunnelRadar's demo apps.
(function () {
  'use strict';
  var PH = window.PH;
  var calm = PH.calm;

  PH.addEn({
    'mock.keeps': 'Kite Reader keeps {v} here',
    'mock.alertText': 'Article Opened: {a} users, against about {b} on a normal day.',
    'mock.i1': 'Reader to Subscriber loses the most people at Subscribed: only {v} get there from Paywall Viewed.',
    'leak.keeps': 'keeps {v}',
    'index.note': '100 = each app 90 days ago, on a 7-day average',
    'unusual.note': 'Marked days are far from the 28 before them. Dashed: a trend, not a forecast.',
    'week.best': 'Tuesday is your busiest day, {v} against an average day.',
    'stick.note': 'DAU/MAU of the key event, full months only.',
    'budget.used': '{a} of {b} queries this hour',
    'n.quiet.t': 'Unusually quiet day · Kite Reader',
    'n.busy.t': 'Unusually busy day · Tempo Run',
    'n.busy.d': 'Run Started: {a} users, against about {b} on a normal day.',
    'n.ret.t': 'Retention fell · Pine Journal',
    'n.ret.d': 'Day 7 retention is {a}, down from {b}.',
    'n.conv.t': 'Conversion fell · Tempo Run',
    'n.conv.d': 'Trial to Paid converts {a}, down from {b}.'
  });

  // ---- The demo apps, the same ones as in the screenshots ------------------
  var apps = [
    { name: 'Tempo Run', ev: 'Run Started', dau: 3841, change: -3.5, stick: 26.7, d7: 20.2, best: 20.5, seed: 3 },
    { name: 'Kite Reader', ev: 'Article Opened', dau: 1084, change: -9.6, stick: 21.6, d7: 15, best: 1.5, seed: 11, drop: true },
    { name: 'Pine Journal', ev: 'Entry Written', dau: 586, change: -14.5, stick: 21.2, d7: null, best: 18.2, seed: 23 },
    { name: 'Moss Budget', ev: 'Expense Added', dau: 59, change: null, stick: null, d7: null, best: null, seed: 41, rise: true }
  ];

  function noise(seed) {
    var s = seed * 9301 + 49297;
    return function () { s = (s * 9301 + 49297) % 233280; return s / 233280; };
  }

  function sparkPath(app, w, h) {
    var r = noise(app.seed), ys = [], n = 22;
    for (var i = 0; i < n; i++) ys.push((app.rise ? i * .12 : 0) + (r() - .5) + (app.drop && i === n - 1 ? -1.6 : 0));
    var min = Math.min.apply(null, ys), max = Math.max.apply(null, ys), pts = [];
    ys.forEach(function (v, k) {
      pts.push((k / (n - 1) * w).toFixed(1) + ' ' + (h - 2 - (v - min) / (max - min) * (h - 4)).toFixed(1));
    });
    return 'M' + pts.join('L');
  }

  function renderRows(id) {
    document.getElementById(id).innerHTML = apps.map(function (a, i) {
      var fall = a.change != null && a.change < -3;
      return '<div class="row"><span class="row-icon">' + a.name[0] + '</span>' +
        '<div class="row-name"><b>' + a.name + '</b><span>' + a.ev + '</span></div>' +
        '<svg class="spark' + (fall ? ' fall' : '') + '" viewBox="0 0 62 22" preserveAspectRatio="none"><path pathLength="1" d="' + sparkPath(a, 62, 22) + '" style="--n:' + i + '"/></svg>' +
        '<div class="row-val"><b style="font-weight:500">' + PH.num(a.dau) + '</b>' +
        (a.change != null ? '<span class="down">' + PH.pct(a.change, true) + '</span>' : '') + '</div></div>';
    }).join('');
  }

  function meter(label, w, value, kind, n) {
    return '<div class="meter-row"><span>' + label + '</span><i class="meter-track"><u class="' + (kind || '') + '" style="--w:' + w + '%;--n:' + (n || 0) + '"></u></i><b>' + value + '</b></div>';
  }
  function dash(v) { return v == null ? '—' : PH.pct(v); }

  // Lines drawn from arrays, shared by the index and the daily chart.
  function linePath(values, x, y) {
    return 'M' + values.map(function (v, i) { return x(i).toFixed(1) + ' ' + y(v).toFixed(1); }).join('L');
  }

  function indexChart() {
    var W = 640, H = 220;
    function walk(seed, end) {
      var r = noise(seed), out = [];
      for (var i = 0; i < 90; i++) out.push(100 + (end - 100) * Math.pow(i / 89, 1.6) + Math.sin(i / 6 + seed) * 2 + (r() - .5) * 2.4);
      return out;
    }
    var lines = [['var(--a)', walk(5, 128), 'Tempo Run'], ['var(--b)', walk(9, 96), 'Kite Reader'], ['var(--good)', walk(14, 76), 'Pine Journal']];
    function x(i) { return i / 89 * (W - 30); }
    function y(v) { return (150 - v) / 80 * H; }
    return '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img">' +
      [75, 100, 125].map(function (v) {
        return '<line class="chart-grid" x1="0" x2="' + W + '" y1="' + y(v).toFixed(1) + '" y2="' + y(v).toFixed(1) + '"/><text class="chart-text" x="' + W + '" y="' + (y(v) - 5).toFixed(1) + '" text-anchor="end">' + v + '</text>';
      }).join('') +
      lines.map(function (l, i) {
        return '<path class="chart-line line-draw" pathLength="1" style="stroke:' + l[0] + ';transition-delay:' + i * 200 + 'ms" d="' + linePath(l[1], x, y) + '"/>';
      }).join('') + '</svg>' +
      '<div class="viz-note">' + lines.map(function (l) { return '<span><i style="display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:' + l[0] + '"></i>' + l[2] + '</span>'; }).join('') + '</div>';
  }

  function dailyChart() {
    var W = 640, H = 190, r = noise(31), days = [];
    for (var i = 0; i < 100; i++) days.push(3000 + i * 6 + Math.sin(i * 2 * Math.PI / 7) * 340 + (r() - .5) * 300);
    days[84] = 6640;
    var hist = days.length, ahead = 30, total = hist + ahead;
    // Least squares through the last 60 days, as in the app.
    var last = days.slice(-60), n = 60, sx = 0, sy = 0, sxy = 0, sxx = 0;
    last.forEach(function (v, k) { sx += k; sy += v; sxy += k * v; sxx += k * k; });
    var b = (n * sxy - sx * sy) / (n * sxx - sx * sx), a = (sy - b * sx) / n;
    function x(k) { return k / (total - 1) * W; }
    function y(v) { return H - v / 7500 * H; }
    var line = linePath(days, x, y);
    return '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img">' +
      '<defs><linearGradient id="area-fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="var(--a)" stop-opacity=".4"/><stop offset="1" stop-color="var(--a)" stop-opacity="0"/></linearGradient></defs>' +
      [2500, 5000].map(function (v) { return '<line class="chart-grid" x1="0" x2="' + W + '" y1="' + y(v).toFixed(1) + '" y2="' + y(v).toFixed(1) + '"/>'; }).join('') +
      '<path class="chart-area fade-late" d="' + line + 'L' + x(hist - 1).toFixed(1) + ' ' + H + 'L0 ' + H + 'Z"/>' +
      '<path class="chart-line line-draw" pathLength="1" d="' + line + '"/>' +
      '<line class="fade-late" stroke="var(--d)" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="5 5" x1="' + x(hist - 1).toFixed(1) + '" y1="' + y(a + b * 59).toFixed(1) + '" x2="' + x(total - 1).toFixed(1) + '" y2="' + y(a + b * (59 + ahead)).toFixed(1) + '"/>' +
      '<circle class="fade-late" style="fill:var(--good)" cx="' + x(84).toFixed(1) + '" cy="' + (y(6640) - 8).toFixed(1) + '" r="4"/></svg>';
  }

  function render() {
    var t = PH.t, num = PH.num, pct = PH.pct;

    // Hero
    renderRows('hero-rows');
    renderRows('phone-rows');
    ['hero-keeps', 'phone-keeps'].forEach(function (id) { document.getElementById(id).textContent = t('mock.keeps').replace('{v}', pct(9)); });
    var quiet = t('mock.alertText').replace('{a}', num(589)).replace('{b}', num(1193));
    document.getElementById('hero-alert-text').textContent = quiet;
    document.getElementById('phone-alert-text').textContent = quiet;
    document.getElementById('hero-funnel').innerHTML = '<div class="meter">' +
      meter('Article Opened', 100, num(40800), '', 0) +
      meter('Paywall Viewed', 17, num(6800), '', 1) +
      meter('Subscribed', 2, num(612), 'bad', 2) + '</div>';
    document.getElementById('phone-funnel').innerHTML = document.getElementById('hero-funnel').innerHTML;
    document.getElementById('phone-ret').innerHTML = '<div class="tri">' + [['D1', 45.8], ['D7', 20.2], ['D30', 11]].map(function (r) {
      return '<div><span>' + r[0] + '</span><b>' + pct(r[1]) + '</b></div>';
    }).join('') + '</div>';
    document.getElementById('hero-insights').innerHTML = '<li>' + t('mock.i1').replace('{v}', pct(9)) + '</li>';

    // Table
    document.getElementById('ptable').innerHTML = apps.map(function (a, i) {
      return '<tr style="--n:' + i + '"><td><div class="app-cell"><i>' + a.name[0] + '</i>' + a.name + '</div></td>' +
        '<td class="col-m" style="text-align:left;color:var(--muted)">' + a.ev + '</td>' +
        '<td>' + num(a.dau) + '</td>' +
        '<td class="' + (a.change == null ? '' : 'down') + '">' + (a.change == null ? '—' : pct(a.change, true)) + '</td>' +
        '<td class="col-m">' + dash(a.stick) + '</td>' +
        '<td class="col-m">' + dash(a.d7) + '</td>' +
        '<td class="col-s">' + dash(a.best) + '</td></tr>';
    }).join('');

    // Funnel leaks
    var leaks = [
      ['Paywall Viewed → Subscribed', 'Kite Reader · Reader to Subscriber', 9],
      ['Paywall Viewed → Trial Started', 'Tempo Run · Trial to Paid', 22],
      ['Plan Picked → First Run', 'Tempo Run · Onboarding to First Run', 31],
      ['First Entry → Third Entry', 'Pine Journal · First Week', 31],
      ['Invite Sent → Invite Accepted', 'Tempo Run · Invite a Friend', 38]
    ];
    document.getElementById('viz-leaks').innerHTML = '<div class="stack">' + leaks.map(function (l, i) {
      return '<div class="leak"><div><b>' + l[0] + '</b><small>' + l[1] + '</small></div>' +
        '<i class="meter-track"><u style="--w:' + l[2] + '%;transition-delay:' + (300 + i * 120) + 'ms"></u></i><span>' + t('leak.keeps').replace('{v}', pct(l[2])) + '</span></div>';
    }).join('') + '</div>';

    // D1, D7, D30 with the curve
    var curve = [], cw = 300, ch = 120;
    for (var d = 1; d <= 30; d++) curve.push(11 + 34.8 * Math.pow(d, -1.05) + (30 - d) * .03);
    function cx(i) { return i / 29 * cw; }
    function cy(v) { return ch - v / 50 * ch; }
    document.getElementById('viz-ret').innerHTML = '<div class="tri">' + [['D1', 45.8], ['D7', 20.2], ['D30', 11]].map(function (r) {
      return '<div><span>' + r[0] + '</span><b>' + pct(r[1]) + '</b></div>';
    }).join('') + '</div>' +
      '<svg style="margin-top:14px" viewBox="0 0 ' + cw + ' ' + ch + '" role="img"><line class="chart-grid" x1="0" x2="' + cw + '" y1="' + cy(0) + '" y2="' + cy(0) + '"/><line class="chart-grid" x1="0" x2="' + cw + '" y1="' + cy(25) + '" y2="' + cy(25) + '"/><path class="chart-line line-draw" pathLength="1" style="stroke:var(--b)" d="' + linePath(curve, cx, cy) + '"/></svg>';

    // Weekly cohorts
    var df = new Intl.DateTimeFormat(PH.lang(), { day: 'numeric', month: 'short' });
    var cohorts = [
      [new Date(2026, 8, 7), [46, 29, 20, 15, 13, 11]], [new Date(2026, 8, 14), [46, 29, 20, 15, 13, 11]],
      [new Date(2026, 8, 21), [46, 29, 21, 15, 13, 11]], [new Date(2026, 8, 28), [46, 29, 20, 15, 13, 11]],
      [new Date(2026, 9, 5), [46, 30, 21, 15, 13, 11]], [new Date(2026, 9, 12), [46, 29, 20, 15, 12]],
      [new Date(2026, 9, 19), [46, 29, 20, 15]], [new Date(2026, 9, 26), [46, 29, 20]], [new Date(2026, 10, 2), [45, 29]]
    ];
    var n = 0;
    var head = '<div class="heat-row" style="--cols:6"><span></span>' + ['D1', 'D3', 'D7', 'D14', 'D21', 'D30'].map(function (h) { return '<span style="text-align:center">' + h + '</span>'; }).join('') + '</div>';
    document.getElementById('viz-heat').innerHTML = head + cohorts.map(function (c) {
      var cells = '';
      for (var i = 0; i < 6; i++) {
        var v = c[1][i];
        cells += v == null ? '<i></i>' : '<i class="heat-cell" style="--o:' + (.22 + v / 58).toFixed(2) + ';--n:' + (n++) + '">' + pct(v) + '</i>';
      }
      return '<div class="heat-row" style="--cols:6"><span>' + df.format(c[0]) + '</span>' + cells + '</div>';
    }).join('');

    document.getElementById('viz-index').innerHTML = indexChart();
    document.getElementById('viz-index-note').textContent = t('index.note');

    // Movers
    var movers = [['Expense Added', 'Moss Budget', 102], ['Budget Viewed', 'Moss Budget', 86.7], ['Share Tapped', 'Tempo Run', -26], ['Entry Written', 'Pine Journal', -14.5], ['Plan Opened', 'Tempo Run', 9.6]];
    document.getElementById('viz-movers').innerHTML = '<div class="stack">' + movers.map(function (m) {
      var w = Math.abs(m[2]) / 102 * 50, up = m[2] > 0;
      return '<div class="mover"><div class="mover-top"><span>' + m[0] + '</span><span class="' + (up ? 'up' : 'down') + '">' + pct(m[2], true) + '</span></div><small>' + m[1] + '</small>' +
        '<div class="mover-track"><u style="--l:' + (up ? 50 : 50 - w).toFixed(1) + '%;--w:' + w.toFixed(1) + '%;background:var(--' + (up ? 'good' : 'bad') + ')"></u></div></div>';
    }).join('') + '</div>';

    document.getElementById('viz-unusual').innerHTML = dailyChart() + '<div class="viz-note"><span>' + t('unusual.note') + '</span></div>';

    // Weekdays: names from the browser, in the page's language.
    var wf = new Intl.DateTimeFormat(PH.lang(), { weekday: 'short' });
    var week = [1.02, 1.14, 1.09, 1.01, 1.07, .83, .82];
    var names = week.map(function (_, i) { return wf.format(new Date(2026, 10, 2 + i)); });
    var wW = 300, wH = 150, step = wW / 7;
    document.getElementById('viz-week').innerHTML = '<svg viewBox="0 0 ' + wW + ' ' + (wH + 18) + '" role="img">' + week.map(function (v, i) {
      var h = v / 1.5 * wH;
      return '<rect class="bar-v ' + (v > 1 ? 'bar-a' : 'bar-b') + '" style="--n:' + i * 4 + '" x="' + (i * step + 4).toFixed(1) + '" width="' + (step - 8).toFixed(1) + '" y="' + (wH - h).toFixed(1) + '" height="' + h.toFixed(1) + '" rx="4"/>' +
        '<text class="chart-text" text-anchor="middle" x="' + (i * step + step / 2).toFixed(1) + '" y="' + (wH + 15) + '">' + names[i].replace(/\.$/, '').slice(0, 3) + '</text>';
    }).join('') + '<line class="chart-grid" x1="0" x2="' + wW + '" y1="' + (wH - 1 / 1.5 * wH).toFixed(1) + '" y2="' + (wH - 1 / 1.5 * wH).toFixed(1) + '"/></svg>' +
      '<div class="viz-note"><span>' + t('week.best').replace('{v}', '<b>' + pct(13.7, true) + '</b>') + '</span></div>';

    // Stickiness by month
    var mf = new Intl.DateTimeFormat(PH.lang(), { month: 'short' });
    var months = [[5, 30], [6, 26], [7, 30], [8, 26], [9, 27]];
    var sW = 300, sH = 130, sStep = sW / 5;
    document.getElementById('viz-stick').innerHTML = '<svg viewBox="0 -18 ' + sW + ' ' + (sH + 36) + '" role="img">' + months.map(function (m, i) {
      var h = m[1] / 36 * sH;
      return '<rect class="bar-v bar-a" style="--n:' + i * 5 + '" x="' + (i * sStep + 7).toFixed(1) + '" width="' + (sStep - 14).toFixed(1) + '" y="' + (sH - h).toFixed(1) + '" height="' + h.toFixed(1) + '" rx="5"/>' +
        '<text class="chart-text" text-anchor="middle" x="' + (i * sStep + sStep / 2).toFixed(1) + '" y="' + (sH - h - 6).toFixed(1) + '">' + pct(m[1]) + '</text>' +
        '<text class="chart-text" text-anchor="middle" x="' + (i * sStep + sStep / 2).toFixed(1) + '" y="' + (sH + 15) + '">' + mf.format(new Date(2026, m[0], 1)).replace(/\.$/, '').slice(0, 4) + '</text>';
    }).join('') + '</svg><div class="viz-note"><span>' + t('stick.note') + '</span></div>';

    // Query budget
    var dots = '';
    for (var q = 0; q < 40; q++) dots += '<i class="' + (q < 36 ? 'on' : '') + '" style="--n:' + q + '"></i>';
    document.getElementById('viz-budget').innerHTML = '<div class="dots">' + dots + '</div><div class="viz-note"><span>' +
      t('budget.used').replace('{a}', '<b>' + num(36) + '</b>').replace('{b}', '<b>' + num(40) + '</b>') + '</span></div>';

    renderNotifs();
  }

  // ---- Notifications in the alerts section ---------------------------------
  var notifIndex = 0;
  function notifList() {
    var t = PH.t, pct = PH.pct, num = PH.num;
    return [
      [t('n.quiet.t'), t('mock.alertText').replace('{a}', num(589)).replace('{b}', num(1193))],
      [t('n.busy.t'), t('n.busy.d').replace('{a}', num(6640)).replace('{b}', num(3480))],
      [t('n.ret.t'), t('n.ret.d').replace('{a}', pct(14)).replace('{b}', pct(18))],
      [t('n.conv.t'), t('n.conv.d').replace('{a}', pct(7.5)).replace('{b}', pct(10.1))]
    ];
  }
  var stage = document.getElementById('notifs');
  function notifHtml(n, pos, enter) {
    return '<div class="notif' + (enter ? ' enter' : '') + '" style="--pos:' + pos + '"><img src="assets/favicon.png" width="38" height="38" alt=""><div><b>' + n[0] + '</b><span>' + n[1] + '</span></div></div>';
  }
  function renderNotifs() {
    var list = notifList();
    stage.innerHTML = [0, 1, 2].map(function (i) { return notifHtml(list[(notifIndex - i + list.length * 4) % list.length], i); }).join('');
  }
  function pushNotif() {
    var list = notifList();
    notifIndex++;
    var cards = stage.querySelectorAll('.notif');
    cards.forEach(function (c) { c.style.setProperty('--pos', Number(c.style.getPropertyValue('--pos')) + 1); });
    stage.insertAdjacentHTML('afterbegin', notifHtml(list[notifIndex % list.length], 0, true));
    var fresh = stage.firstChild;
    fresh.getBoundingClientRect();
    fresh.classList.remove('enter');
    setTimeout(function () { var old = stage.querySelectorAll('.notif'); if (old.length > 3) old[old.length - 1].remove(); }, 650);
  }

  PH.onLang(render);

  // How far the tall screenshot pans, measured so it stops at its last row.
  var pan = document.getElementById('pan');
  function measurePan() { pan.style.setProperty('--pan-h', pan.clientHeight + 'px'); }
  window.addEventListener('resize', measurePan);
  measurePan();

  // ---- Scripted hero -------------------------------------------------------
  var desk = document.getElementById('desk');
  var panel = document.getElementById('panel');
  var banner = document.getElementById('phone-banner');
  var used = document.getElementById('hero-used');

  if (calm) {
    desk.classList.add('play');
    panel.classList.add('alerting');
    banner.classList.add('on');
    return;
  }

  function play() {
    if (!PH.inView(desk)) { setTimeout(play, 700); return; }
    desk.classList.remove('play');
    panel.classList.remove('alerting');
    used.textContent = '33/40';
    desk.getBoundingClientRect();
    desk.classList.add('play');
    // One query at a time, 5 seconds apart in the app; quicker here.
    [34, 35, 36].forEach(function (v, i) { setTimeout(function () { used.textContent = v + '/40'; }, 700 + i * 700); });
    setTimeout(function () { panel.classList.add('alerting'); }, 3400);
    setTimeout(function () { panel.classList.remove('alerting'); }, 9000);
    setTimeout(play, 10400);
  }
  play();

  // The alerts section and the phone keep moving only while someone can see them.
  setInterval(function () { if (PH.inView(stage)) pushNotif(); }, 3200);
  setInterval(function () {
    if (!PH.inView(banner)) return;
    banner.classList.add('on');
    setTimeout(function () { banner.classList.remove('on'); }, 3400);
  }, 6000);
})();
