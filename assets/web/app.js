'use strict';
// Trang xem chỉ đọc của VN Stock Insight. JS thuần, không nạp tài nguyên ngoài (CSP chỉ cho phép 'self').
(function () {
  var SVGNS = 'http://www.w3.org/2000/svg';
  var POLL_MS = 30000;
  var store = {
    get: function (k) { try { return sessionStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { sessionStorage.setItem(k, v); } catch (e) { /* bỏ qua */ } },
    lget: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    lset: function (k, v) { try { localStorage.setItem(k, v); } catch (e) { /* bỏ qua */ } },
  };

  // ---------- Tiện ích ----------
  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
    for (var k in attrs || {}) {
      if (k === 'text') n.textContent = attrs[k];
      else if (k.slice(0, 2) === 'on') n.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] !== null && attrs[k] !== undefined && attrs[k] !== false) n.setAttribute(k, attrs[k] === true ? '' : attrs[k]);
    }
    [].concat(kids || []).forEach(function (c) { if (c !== null && c !== undefined) n.append(c.nodeType ? c : document.createTextNode(String(c))); });
    return n;
  }
  function sv(tag, attrs, kids) {
    var n = document.createElementNS(SVGNS, tag);
    for (var k in attrs || {}) n.setAttribute(k, attrs[k]);
    [].concat(kids || []).forEach(function (c) { if (c) n.append(c); });
    return n;
  }
  var nf = new Intl.NumberFormat('vi-VN', { maximumFractionDigits: 2 });
  function num(x, d) {
    if (x === null || x === undefined || !isFinite(x)) return '–';
    return new Intl.NumberFormat('vi-VN', { minimumFractionDigits: d || 0, maximumFractionDigits: d === undefined ? 2 : d }).format(x);
  }
  function big(x) {
    if (x === null || x === undefined) return '–';
    var a = Math.abs(x);
    if (a >= 1e9) return nf.format(x / 1e9) + ' tỷ';
    if (a >= 1e6) return nf.format(x / 1e6) + ' triệu';
    if (a >= 1e3) return nf.format(x / 1e3) + ' nghìn';
    return nf.format(x);
  }
  function dir(x) { return x === null || x === undefined || x === 0 ? 'flat' : x > 0 ? 'up' : 'down'; }
  // Màu không phải là dấu hiệu duy nhất: luôn kèm mũi tên và dấu +/−.
  function chg(x, suffix, d) {
    var k = dir(x);
    var arrow = k === 'up' ? '▲' : k === 'down' ? '▼' : '■';
    var txt = x === null || x === undefined ? '–' : (x > 0 ? '+' : x < 0 ? '−' : '') + num(Math.abs(x), d === undefined ? 2 : d) + (suffix || '');
    var word = k === 'up' ? 'tăng' : k === 'down' ? 'giảm' : 'đi ngang';
    return el('span', { class: 'chg ' + k, 'aria-label': word + ' ' + txt }, [el('span', { 'aria-hidden': 'true', text: arrow + ' ' }), txt]);
  }
  function dayLabel(t) { var d = new Date((t + 7 * 3600) * 1000).toISOString(); return d.slice(8, 10) + '/' + d.slice(5, 7) + '/' + d.slice(0, 4); }
  function timeLabel(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    return isNaN(d) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' });
  }

  var ICON = {
    home: 'M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10',
    star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z',
    news: 'M4 5h13v14H6a2 2 0 0 1-2-2V5zM17 8h3v9a2 2 0 0 1-2 2M8 9h5M8 13h5',
    bank: 'M3 10l9-6 9 6M5 10v8M9 10v8M15 10v8M19 10v8M3 20h18',
    sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
    moon: 'M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z',
  };
  function icon(name) {
    return sv('svg', { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': '2', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', focusable: 'false' }, [sv('path', { d: ICON[name] })]);
  }

  // ---------- Khoá truy cập & gọi API ----------
  var key = null;
  function readKey() {
    var m = /[#&?]key=([^&]+)/.exec(location.hash) || /[?&]key=([^&]+)/.exec(location.search);
    if (m) { key = decodeURIComponent(m[1]); store.set('k', key); history.replaceState(null, '', location.pathname); }
    else key = store.get('k');
  }
  function api(path) {
    return fetch(path, { headers: { 'X-Access-Key': key || '' }, cache: 'no-store', credentials: 'omit' }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (!r.ok) { var e = new Error(j.error || ('Lỗi ' + r.status)); e.status = r.status; throw e; }
        return j;
      });
    });
  }

  // ---------- Trạng thái giao diện ----------
  var data = null, view = store.get('view') || 'home', detail = null, macroTab = 0, lastErr = null, timer = null;
  var main = document.getElementById('main'), statusEl = document.getElementById('status'), navEl = document.getElementById('nav');

  function setStatus(text, bad) { statusEl.textContent = text; statusEl.className = 'status' + (bad ? ' err' : ''); }

  function applyTheme(mode) {
    var root = document.documentElement;
    if (mode === 'light' || mode === 'dark') root.setAttribute('data-theme', mode); else root.removeAttribute('data-theme');
    var dark = mode === 'dark' || (mode !== 'light' && matchMedia('(prefers-color-scheme: dark)').matches);
    var b = document.getElementById('theme');
    b.replaceChildren(icon(dark ? 'sun' : 'moon'));
    b.setAttribute('aria-label', dark ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối');
    b.setAttribute('title', b.getAttribute('aria-label'));
  }
  function initTheme() {
    applyTheme(store.lget('theme'));
    document.getElementById('theme').addEventListener('click', function () {
      var dark = document.documentElement.getAttribute('data-theme') === 'dark' || (!document.documentElement.getAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
      var next = dark ? 'light' : 'dark';
      store.lset('theme', next); applyTheme(next);
      if (data) render();
    });
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () { applyTheme(store.lget('theme')); });
  }

  var TABS = [['home', 'Tổng quan', 'home'], ['watch', 'Theo dõi', 'star'], ['news', 'Tin tức', 'news'], ['macro', 'Vĩ mô', 'bank']];
  function renderNav() {
    navEl.replaceChildren.apply(navEl, TABS.map(function (t) {
      return el('button', { type: 'button', 'aria-current': view === t[0] && !detail ? 'page' : null, onclick: function () { go(t[0]); } }, [icon(t[2]), el('span', { text: t[1] })]);
    }));
  }
  function go(v) { view = v; detail = null; store.set('view', v); renderNav(); render(); main.focus({ preventScroll: true }); window.scrollTo(0, 0); }

  // ---------- Biểu đồ nhỏ ----------
  function spark(vals, k) {
    if (!vals || vals.length < 2) return el('div');
    var w = 200, h = 40, lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals), span = hi - lo || 1;
    var d = vals.map(function (v, i) { return (i ? 'L' : 'M') + (i / (vals.length - 1) * w).toFixed(1) + ' ' + (h - 3 - (v - lo) / span * (h - 6)).toFixed(1); }).join('');
    var s = sv('svg', { class: 'spark', viewBox: '0 0 ' + w + ' ' + h, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Đường giá 30 phiên gần nhất, từ ' + num(vals[0]) + ' đến ' + num(vals[vals.length - 1]) });
    s.append(sv('path', { d: d, class: k, 'vector-effect': 'non-scaling-stroke' }));
    return s;
  }

  // ---------- Biểu đồ nến ----------
  function sma(c, n) {
    var out = [], sum = 0;
    for (var i = 0; i < c.length; i++) { sum += c[i]; if (i >= n) sum -= c[i - n]; out.push(i >= n - 1 ? sum / n : null); }
    return out;
  }
  function candleChart(rows) {
    // rows: [t,o,h,l,c,v]
    var box = el('div', { class: 'chart' });
    var wrap = el('div');
    var st = { visible: Math.min(120, rows.length), end: rows.length, cur: null };
    var closes = rows.map(function (r) { return r[4]; }), ma20 = sma(closes, 20), ma50 = sma(closes, 50);
    var readout = el('p', { class: 'readout', 'aria-live': 'polite' });
    var svg;
    function clamp() {
      st.visible = Math.max(20, Math.min(rows.length, st.visible));
      st.end = Math.max(st.visible, Math.min(rows.length, st.end));
    }
    function show(i) {
      st.cur = i;
      var r = rows[i], prev = i > 0 ? rows[i - 1][4] : null, d = prev ? (r[4] / prev - 1) * 100 : null;
      var kind = r[4] >= r[1] ? 'nến tăng (rỗng)' : 'nến giảm (đặc)';
      readout.replaceChildren(
        el('strong', { text: dayLabel(r[0]) + ' · ' + kind + ' · ' }),
        'Mở ' + num(r[1]) + ', Cao ' + num(r[2]) + ', Thấp ' + num(r[3]) + ', Đóng ' + num(r[4]) + ' (nghìn đồng), KL ' + big(r[5]) + ' ',
        d === null ? '' : chg(d, '%')
      );
      draw();
    }
    function draw() {
      clamp();
      var W = Math.max(280, box.clientWidth || 340), PH = W < 520 ? 220 : 300, VH = 56, G = 22, pad = 48, H = PH + VH + G + 20;
      var from = st.end - st.visible, vis = rows.slice(from, st.end);
      var lo = Infinity, hi = -Infinity, vmax = 0;
      vis.forEach(function (r, j) {
        lo = Math.min(lo, r[3]); hi = Math.max(hi, r[2]); vmax = Math.max(vmax, r[5]);
        [ma20[from + j], ma50[from + j]].forEach(function (m) { if (m !== null) { lo = Math.min(lo, m); hi = Math.max(hi, m); } });
      });
      var rg = (hi - lo) || 1; lo -= rg * .04; hi += rg * .04; rg = hi - lo;
      var plotW = W - pad - 8, step = plotW / vis.length, bw = Math.max(1.5, Math.min(14, step * .7));
      function X(j) { return pad + step * (j + .5); }
      function Y(p) { return 6 + (hi - p) / rg * (PH - 12); }
      svg = sv('svg', { viewBox: '0 0 ' + W + ' ' + H, tabindex: '0', role: 'img', 'aria-label': 'Biểu đồ nến ngày, ' + vis.length + ' phiên. Dùng phím mũi tên trái/phải để xem từng phiên, phím cộng/trừ để phóng to/thu nhỏ.' });
      var ax = sv('g', { class: 'ax' });
      for (var i = 0; i <= 4; i++) {
        var p = lo + rg * i / 4, y = Y(p);
        ax.append(sv('line', { x1: pad, x2: W - 8, y1: y, y2: y }));
        var t = sv('text', { x: pad - 6, y: y + 4, 'text-anchor': 'end' }); t.textContent = num(p, 1); ax.append(t);
      }
      var ticks = Math.min(W < 520 ? 2 : 4, vis.length - 1);
      for (var q = 0; q <= ticks; q++) {
        var idx = Math.round(q * (vis.length - 1) / (ticks || 1));
        var lt = sv('text', { x: X(idx), y: H - 4, 'text-anchor': q === 0 ? 'start' : q === ticks ? 'end' : 'middle' });
        lt.textContent = dayLabel(vis[idx][0]).slice(0, 5) + '/' + dayLabel(vis[idx][0]).slice(8); ax.append(lt);
      }
      svg.append(ax);
      vis.forEach(function (r, j) {
        var up = r[4] >= r[1], cls = up ? 'up' : 'down', x = X(j);
        svg.append(sv('line', { x1: x, x2: x, y1: Y(r[2]), y2: Y(r[3]), class: 'c-' + cls, 'stroke-width': 1.5 }));
        var y1 = Y(Math.max(r[1], r[4])), y2 = Y(Math.min(r[1], r[4]));
        svg.append(sv('rect', { x: x - bw / 2, y: y1, width: bw, height: Math.max(1.5, y2 - y1), class: 'body-' + cls }));
        var vh = vmax ? r[5] / vmax * VH : 0;
        svg.append(sv('rect', { x: x - bw / 2, y: PH + G + VH - vh, width: bw, height: vh, class: 'vol-' + cls }));
      });
      [[ma20, 'ma20'], [ma50, 'ma50']].forEach(function (m) {
        var d = '';
        vis.forEach(function (_, j) { var v = m[0][from + j]; if (v !== null) d += (d ? 'L' : 'M') + X(j).toFixed(1) + ' ' + Y(v).toFixed(1); });
        if (d) svg.append(sv('path', { d: d, class: m[1] }));
      });
      if (st.cur !== null && st.cur >= from && st.cur < st.end) {
        var cx = X(st.cur - from);
        svg.append(sv('line', { x1: cx, x2: cx, y1: 0, y2: PH + G + VH, class: 'cross' }));
      }
      function pick(ev) {
        var rect = svg.getBoundingClientRect(), x = (ev.clientX - rect.left) / rect.width * W;
        var j = Math.max(0, Math.min(vis.length - 1, Math.floor((x - pad) / step)));
        show(from + j);
      }
      svg.addEventListener('pointerdown', pick);
      svg.addEventListener('pointermove', function (ev) { if (ev.pointerType === 'mouse' || ev.buttons) pick(ev); });
      svg.addEventListener('keydown', function (ev) {
        var c = st.cur === null ? st.end - 1 : st.cur, handled = true;
        if (ev.key === 'ArrowLeft') { c = Math.max(0, c - 1); if (c < st.end - st.visible) st.end -= 1; }
        else if (ev.key === 'ArrowRight') { c = Math.min(rows.length - 1, c + 1); if (c >= st.end) st.end += 1; }
        else if (ev.key === '+' || ev.key === '=') st.visible = Math.round(st.visible * .7);
        else if (ev.key === '-') st.visible = Math.round(st.visible / .7);
        else if (ev.key === 'Home') { c = st.end - st.visible; }
        else if (ev.key === 'End') { c = st.end - 1; }
        else handled = false;
        if (handled) { ev.preventDefault(); clamp(); show(Math.max(0, Math.min(rows.length - 1, c))); svg.focus(); }
      });
      wrap.replaceChildren(svg);
      if (st.cur === null) show(rows.length - 1);
    }
    function btn(label, aria, fn) { return el('button', { type: 'button', class: 'chip', 'aria-label': aria, onclick: fn }, label); }
    var ctrl = el('div', { class: 'ctrl', role: 'group', 'aria-label': 'Điều khiển biểu đồ' }, [
      btn('+', 'Phóng to', function () { st.visible = Math.round(st.visible * .7); st.cur = null; draw(); }),
      btn('−', 'Thu nhỏ', function () { st.visible = Math.round(st.visible / .7); st.cur = null; draw(); }),
      btn('◀', 'Lùi về phiên trước', function () { st.end -= Math.max(1, Math.round(st.visible / 4)); st.cur = null; clamp(); draw(); }),
      btn('▶', 'Tiến tới phiên sau', function () { st.end += Math.max(1, Math.round(st.visible / 4)); st.cur = null; clamp(); draw(); }),
      btn('Đặt lại', 'Đặt lại khoảng xem', function () { st.visible = Math.min(120, rows.length); st.end = rows.length; st.cur = null; draw(); }),
    ]);
    function lg(svgInner, text) { return el('li', {}, [sv('svg', { viewBox: '0 0 28 14', 'aria-hidden': 'true' }, svgInner), text]); }
    var legend = el('ul', { class: 'legend', 'aria-label': 'Chú giải' }, [
      lg([sv('line', { x1: 14, x2: 14, y1: 0, y2: 14, class: 'c-up', 'stroke-width': 1.5 }), sv('rect', { x: 9, y: 3, width: 10, height: 8, class: 'body-up' })], 'Nến tăng (thân rỗng)'),
      lg([sv('line', { x1: 14, x2: 14, y1: 0, y2: 14, class: 'c-down', 'stroke-width': 1.5 }), sv('rect', { x: 9, y: 3, width: 10, height: 8, class: 'body-down' })], 'Nến giảm (thân đặc)'),
      lg([sv('line', { x1: 0, x2: 28, y1: 7, y2: 7, class: 'ma20' })], 'MA20 (nét liền)'),
      lg([sv('line', { x1: 0, x2: 28, y1: 7, y2: 7, class: 'ma50' })], 'MA50 (nét đứt)'),
      lg([sv('rect', { x: 4, y: 4, width: 20, height: 10, class: 'vol-up' })], 'Khối lượng'),
    ]);
    var tbl = el('details', {}, [el('summary', { text: 'Xem bảng số liệu 30 phiên gần nhất' }), (function () {
      var rowsT = rows.slice(-30).reverse().map(function (r) {
        return el('tr', {}, [r[0], r[1], r[2], r[3], r[4], r[5]].map(function (v, i) { return el(i ? 'td' : 'th', { scope: i ? null : 'row' }, i ? (i === 5 ? big(v) : num(v)) : dayLabel(v)); }));
      });
      return el('div', { class: 'tbl-wrap' }, [el('table', {}, [
        el('thead', {}, el('tr', {}, ['Ngày', 'Mở', 'Cao', 'Thấp', 'Đóng', 'KL'].map(function (h) { return el('th', { scope: 'col', text: h }); }))),
        el('tbody', {}, rowsT)])]);
    })()]);
    box.append(wrap);
    var out = el('div', {}, [ctrl, box, readout, legend, tbl]);
    requestAnimationFrame(draw);
    var ro = typeof ResizeObserver === 'function' ? new ResizeObserver(function () { if (box.isConnected) draw(); }) : null;
    if (ro) ro.observe(box);
    return out;
  }

  // ---------- Biểu đồ đường (vĩ mô) ----------
  function lineChart(series) {
    var pts = series.points.map(function (p) { return { label: p[0], v: p[1], fc: !!p[2] }; });
    if (pts.length > 30) pts = pts.slice(-30);
    var box = el('div', { class: 'chart' }), readout = el('p', { class: 'readout', 'aria-live': 'polite' });
    var dec = series.decimals === undefined ? 1 : series.decimals, cur = null;
    function show(i) {
      cur = i;
      var p = pts[i];
      readout.replaceChildren(el('strong', { text: p.label + (p.fc ? ' (dự báo)' : '') + ': ' }), num(p.v, dec) + ' ' + series.unit);
      draw();
    }
    function draw() {
      var W = Math.max(260, box.clientWidth || 320), H = 170, pad = 44;
      var lo = Math.min.apply(null, pts.map(function (p) { return p.v; })), hi = Math.max.apply(null, pts.map(function (p) { return p.v; }));
      if (lo === hi) { lo -= 1; hi += 1; }
      var m = (hi - lo) * .08; lo -= m; hi += m;
      function X(i) { return pad + (W - pad - 10) * i / (pts.length - 1); }
      function Y(v) { return 8 + (hi - v) / (hi - lo) * (H - 34); }
      var svg = sv('svg', { viewBox: '0 0 ' + W + ' ' + H, tabindex: '0', role: 'img', 'aria-label': series.title + ', ' + pts.length + ' kỳ. Phím mũi tên trái/phải để xem từng kỳ.' });
      var ax = sv('g', { class: 'ax' });
      for (var i = 0; i <= 3; i++) {
        var v = lo + (hi - lo) * i / 3, y = Y(v);
        ax.append(sv('line', { x1: pad, x2: W - 10, y1: y, y2: y }));
        var t = sv('text', { x: pad - 6, y: y + 4, 'text-anchor': 'end' }); t.textContent = num(v, dec > 1 ? 1 : dec); ax.append(t);
      }
      [0, Math.floor((pts.length - 1) / 2), pts.length - 1].forEach(function (i2, k) {
        var lt = sv('text', { x: X(i2), y: H - 6, 'text-anchor': k === 0 ? 'start' : k === 2 ? 'end' : 'middle' }); lt.textContent = pts[i2].label; ax.append(lt);
      });
      svg.append(ax);
      var firstFc = pts.findIndex(function (p) { return p.fc; });
      function path(a, b) { var d = ''; for (var i3 = a; i3 <= b; i3++) d += (d ? 'L' : 'M') + X(i3).toFixed(1) + ' ' + Y(pts[i3].v).toFixed(1); return d; }
      if (firstFc < 0) svg.append(sv('path', { d: path(0, pts.length - 1), class: 'line' }));
      else {
        if (firstFc > 0) svg.append(sv('path', { d: path(0, firstFc - 1), class: 'line' }));
        svg.append(sv('path', { d: path(Math.max(0, firstFc - 1), pts.length - 1), class: 'line fc' }));
      }
      if (cur !== null) {
        svg.append(sv('line', { x1: X(cur), x2: X(cur), y1: 0, y2: H - 22, class: 'cross' }));
        svg.append(sv('circle', { cx: X(cur), cy: Y(pts[cur].v), r: 4.5, class: 'dot' }));
      }
      function pick(ev) {
        var r = svg.getBoundingClientRect(), x = (ev.clientX - r.left) / r.width * W;
        show(Math.max(0, Math.min(pts.length - 1, Math.round((x - pad) / (W - pad - 10) * (pts.length - 1)))));
      }
      svg.addEventListener('pointerdown', pick);
      svg.addEventListener('pointermove', function (ev) { if (ev.pointerType === 'mouse' || ev.buttons) pick(ev); });
      svg.addEventListener('keydown', function (ev) {
        var c = cur === null ? pts.length - 1 : cur;
        if (ev.key === 'ArrowLeft') c = Math.max(0, c - 1); else if (ev.key === 'ArrowRight') c = Math.min(pts.length - 1, c + 1); else return;
        ev.preventDefault(); show(c); box.querySelector('svg').focus();
      });
      box.replaceChildren(svg);
    }
    requestAnimationFrame(function () { show(pts.length - 1); });
    if (typeof ResizeObserver === 'function') new ResizeObserver(function () { if (box.isConnected && cur !== null) draw(); }).observe(box);
    var hasFc = pts.some(function (p) { return p.fc; });
    return el('div', {}, [box, readout, hasFc ? el('p', { class: 'small muted', text: 'Nét đứt là số dự báo (IMF).' }) : null]);
  }

  // ---------- Các màn hình ----------
  function section(title, kids, extra) { return el('section', { class: 'card', 'aria-label': title }, [el('h2', { text: title }), kids].concat(extra || [])); }

  function indexCard(q) {
    var k = dir(q.change);
    return el('article', { class: 'card' }, [
      el('div', { class: 'row between' }, [el('h3', { text: q.name }), chg(q.pct, '%')]),
      el('div', { class: 'val', text: num(q.last) }),
      el('div', { class: 'small muted' }, [chg(q.change, '', 2), ' điểm']),
      spark(q.spark, k),
    ]);
  }

  function rowBtn(s) {
    var sub = s.signals && s.signals.length ? s.signals.slice(0, 2).join(' · ') : 'RSI ' + num(s.rsi14, 0) + ' · MA20 ' + num(s.ma20, 1);
    return el('li', {}, el('button', { type: 'button', class: 'item', onclick: function () { openDetail(s.symbol); } }, [
      el('span', {}, [el('span', { class: 'sym', text: s.symbol }), el('span', { class: 'muted tnum', text: '  ' + num(s.close, 2) })]),
      el('span', { class: 'right' }, chg(s.change_1d, '%')),
      el('span', { class: 'sub', text: sub }),
    ]));
  }

  function renderHome() {
    var d = data, kids = [];
    kids.push(el('div', { class: 'grid g-idx' }, d.indices.map(indexCard)));
    if (!d.indices.length) kids[0] = el('div', { class: 'empty', text: 'Chưa có dữ liệu chỉ số. App đang tải dữ liệu, trang sẽ tự cập nhật.' });
    var b = d.marketBrief;
    if (b && (b.summary || b.outlook || b.headline)) {
      var parts = [];
      ['headline', 'summary', 'outlook'].forEach(function (f) { if (typeof b[f] === 'string') parts.push(el('p', { text: b[f] })); });
      [['key_drivers', 'Yếu tố chính'], ['risks', 'Rủi ro']].forEach(function (f) {
        if (Array.isArray(b[f[0]]) && b[f[0]].length) parts.push(el('h3', { text: f[1] }), el('ul', {}, b[f[0]].map(function (x) { return el('li', { text: typeof x === 'string' ? x : JSON.stringify(x) }); })));
      });
      kids.push(section('Nhận định thị trường (AI)', el('div', {}, parts)));
    }
    var v = d.vn30.slice().filter(function (s) { return s.change_1d !== null; });
    var up = v.slice().sort(function (a, b2) { return b2.change_1d - a.change_1d; }).slice(0, 5);
    var dn = v.slice().sort(function (a, b2) { return a.change_1d - b2.change_1d; }).slice(0, 5);
    if (v.length) {
      kids.push(el('div', { class: 'grid g-2' }, [
        section('VN30 tăng mạnh nhất', el('ul', { class: 'list' }, up.map(rowBtn))),
        section('VN30 giảm mạnh nhất', el('ul', { class: 'list' }, dn.map(rowBtn))),
      ]));
    }
    return el('div', { class: 'stack' }, kids);
  }

  function renderWatch() {
    var w = data.watchlist;
    if (!w.length) return el('div', { class: 'empty', text: 'Danh sách theo dõi đang trống hoặc đang tải. Thêm mã trong app để xem ở đây.' });
    return section('Danh sách theo dõi', el('ul', { class: 'list' }, w.map(rowBtn)));
  }

  function renderNews() {
    var n = data.news;
    if (!n.length) return el('div', { class: 'empty', text: 'Chưa có tin tức.' });
    return section('Tin tức mới', el('div', { class: 'news' }, n.map(function (x) {
      var inner = [el('div', { class: 'nt', text: x.title }), el('div', { class: 'small muted', text: x.source + ' · ' + timeLabel(x.published) + (x.tickers && x.tickers.length ? ' · ' + x.tickers.join(', ') : '') })];
      if (x.summary) inner.push(el('div', { class: 'small', text: x.summary.length > 180 ? x.summary.slice(0, 180) + '…' : x.summary }));
      return x.link ? el('a', { href: x.link, target: '_blank', rel: 'noopener noreferrer', 'aria-label': x.title + ' (mở trong tab mới)' }, inner) : el('div', { class: 'news-i' }, inner);
    })));
  }

  function renderMacro() {
    var m = data.macro;
    if (!m) return el('div', { class: 'empty', text: 'Đang tải số liệu vĩ mô trên máy chủ. Trang sẽ tự cập nhật sau ít phút.' });
    var byId = {}; m.series.forEach(function (s) { byId[s.id] = s; });
    var tab = m.tabs[macroTab] || m.tabs[0];
    var chips = el('div', { class: 'chips', role: 'tablist', 'aria-label': 'Nhóm chỉ tiêu' }, m.tabs.map(function (t, i) {
      return el('button', { type: 'button', class: 'chip', role: 'tab', 'aria-selected': String(i === macroTab), onclick: function () { macroTab = i; render(); } }, t.title);
    }));
    var cards = tab.ids.filter(function (id) { return byId[id]; }).map(function (id) {
      var s = byId[id], act = s.points.filter(function (p) { return !p[2]; }), last = act[act.length - 1], prev = act[act.length - 2];
      var delta = last && prev ? last[1] - prev[1] : null;
      return el('article', { class: 'card' }, [
        el('h3', { text: s.title }),
        el('div', { class: 'row between' }, [el('span', { class: 'val', text: last ? num(last[1], s.decimals) : '–' }), el('span', { class: 'small muted', text: s.unit })]),
        el('div', { class: 'small muted' }, [last ? last[0] + ' · ' : '', delta === null ? '' : 'so với kỳ trước ', delta === null ? null : chg(delta, '', s.decimals)]),
        lineChart(s),
        el('p', { class: 'small muted', text: s.frequency + ' · Nguồn: ' + s.source }),
      ]);
    });
    return el('div', { class: 'stack' }, [chips, el('div', { class: 'grid g-2' }, cards),
      el('p', { class: 'note', text: 'Số liệu hàng năm từ World Bank và IMF (có dự báo); tỷ giá USD/VND hàng tháng từ Yahoo Finance. Số liệu hàng tháng của Tổng cục Thống kê chưa có nguồn công khai miễn phí.' })]);
  }

  function renderDetail() {
    var sym = detail, s = data.watchlist.concat(data.vn30).filter(function (x) { return x.symbol === sym; })[0];
    var wrap = el('div', { class: 'stack' });
    wrap.append(el('button', { type: 'button', class: 'btn ghost back', onclick: function () { detail = null; renderNav(); render(); } }, '← Quay lại'));
    var head = el('section', { class: 'card' }, [el('div', { class: 'row between' }, [el('h2', { text: sym }), s ? chg(s.change_1d, '%') : null])]);
    if (s) head.append(el('div', { class: 'val tnum', text: num(s.close, 2) + ' nghìn đồng' }), el('p', { class: 'small muted', text: 'Phiên ' + (s.date || '') + ' · RSI ' + num(s.rsi14, 0) + ' · KL ' + big(s.volume) + (s.vol_ratio ? ' (x' + num(s.vol_ratio, 1) + ' trung bình 20 phiên)' : '') }));
    if (s && s.signals && s.signals.length) head.append(el('div', { class: 'chips' }, s.signals.map(function (x) { return el('span', { class: 'tag', text: x }); })));
    wrap.append(head);
    var chartCard = section('Biểu đồ giá', el('p', { class: 'muted', text: 'Đang tải…' }));
    wrap.append(chartCard);
    var anCard = el('section', { class: 'card', 'aria-label': 'Phân tích AI' }, [el('h2', { text: 'Phân tích AI đã lưu' }), el('p', { class: 'muted', text: 'Đang tải…' })]);
    wrap.append(anCard);
    api('/api/bars?symbol=' + encodeURIComponent(sym)).then(function (j) {
      if (detail !== sym) return;
      chartCard.replaceChildren(el('h2', { text: 'Biểu đồ giá' }), j.bars.length >= 5 ? candleChart(j.bars) : el('p', { class: 'muted', text: 'Chưa đủ dữ liệu giá.' }));
    }).catch(function (e) { chartCard.replaceChildren(el('h2', { text: 'Biểu đồ giá' }), el('p', { class: 'err-text', text: e.message })); });
    function loadAnalysis(run) {
      return api('/api/analysis/' + encodeURIComponent(sym) + (run ? '?run=1' : '')).then(function (a) {
        if (detail === sym) anCard.replaceChildren(el('h2', { text: 'Phân tích AI' }), analysisView(a));
      }).catch(function (e) {
        if (detail !== sym) return;
        var kids = [el('h2', { text: 'Phân tích AI' }), el('p', { class: e.status === 404 ? 'muted' : 'err-text', text: e.status === 404 ? 'Chưa có phân tích đã lưu cho mã này.' : e.message })];
        if (data.canRunAnalysis) {
          var b = el('button', { type: 'button', class: 'btn', onclick: function () { b.disabled = true; b.textContent = 'Đang phân tích… (có thể mất vài chục giây)'; loadAnalysis(true); } }, 'Yêu cầu phân tích AI (tốn API của chủ máy)');
          kids.push(b);
        }
        anCard.replaceChildren.apply(anCard, kids);
      });
    }
    loadAnalysis(false);
    return wrap;
  }

  function analysisView(a) {
    var r = a.result || {}, kids = [];
    kids.push(el('p', { class: 'small muted', text: 'Tạo lúc ' + timeLabel(a.created_at) + (a.ai ? ' · ' + a.ai : '') }));
    Object.keys(r).forEach(function (k) {
      var v = r[k];
      var label = k.replace(/_/g, ' ');
      if (typeof v === 'string' || typeof v === 'number') kids.push(el('p', {}, [el('strong', { text: label + ': ' }), String(v)]));
      else if (Array.isArray(v)) kids.push(el('h3', { text: label }), el('ul', {}, v.map(function (x) { return el('li', { text: typeof x === 'string' ? x : JSON.stringify(x) }); })));
      else if (v && typeof v === 'object') kids.push(el('h3', { text: label }), el('ul', {}, Object.keys(v).map(function (kk) { return el('li', { text: kk.replace(/_/g, ' ') + ': ' + (typeof v[kk] === 'string' ? v[kk] : JSON.stringify(v[kk])) }); })));
    });
    return el('div', {}, kids);
  }

  function openDetail(sym) { detail = sym; renderNav(); render(); window.scrollTo(0, 0); main.focus({ preventScroll: true }); }

  function render() {
    if (!data) return;
    var scroll = window.scrollY;
    var node = detail ? renderDetail() : { home: renderHome, watch: renderWatch, news: renderNews, macro: renderMacro }[view]();
    main.replaceChildren(node);
    if (!detail) window.scrollTo(0, scroll);
  }

  function login(msg) {
    clearInterval(timer);
    setStatus('Cần khoá truy cập', true);
    var input = el('input', { id: 'k', type: 'password', autocomplete: 'off', autocapitalize: 'none', spellcheck: 'false', 'aria-describedby': 'kh' });
    var form = el('form', { class: 'card login', onsubmit: function (ev) { ev.preventDefault(); key = input.value.trim(); store.set('k', key); load(); } }, [
      el('h2', { text: 'Nhập khoá truy cập' }),
      el('p', { id: 'kh', class: 'muted', text: 'Mở link hoặc quét mã QR trong phần Cài đặt › Chia sẻ trong mạng nội bộ của app, hoặc dán khoá vào đây.' }),
      el('label', { for: 'k', text: 'Khoá truy cập' }), input,
      msg ? el('p', { class: 'err-text', role: 'alert', text: msg }) : null,
      el('button', { class: 'btn', type: 'submit' }, 'Xem dữ liệu'),
    ]);
    main.replaceChildren(form);
  }

  function load() {
    return api('/api/state').then(function (j) {
      data = j; lastErr = null;
      var t = j.updatedAt || j.dashUpdatedAt;
      setStatus(t ? 'Cập nhật ' + timeLabel(t) : 'Đang chờ app tải dữ liệu');
      renderNav(); if (!detail || !main.firstChild) render();
      clearInterval(timer); timer = setInterval(function () { if (!document.hidden) load(); }, POLL_MS);
    }).catch(function (e) {
      if (e.status === 401) return login(key ? 'Khoá không đúng.' : '');
      if (e.status === 429) return login(e.message);
      lastErr = e;
      setStatus(data ? 'Mất kết nối, đang hiển thị dữ liệu cũ' : 'Không kết nối được tới app', true);
      if (!data) { main.replaceChildren(el('div', { class: 'empty', role: 'alert', text: 'Không kết nối được tới app. Kiểm tra app còn đang mở, máy cùng mạng và cổng không bị tường lửa chặn.' })); clearInterval(timer); timer = setInterval(load, POLL_MS); }
    });
  }

  initTheme();
  readKey();
  renderNav();
  if (!key) login(''); else load();
  document.addEventListener('visibilitychange', function () { if (!document.hidden && key && lastErr) load(); });
})();
