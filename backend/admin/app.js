/* Mukafaah Manager — web dashboard (no build step, no libraries).
 * Talks to the same backend as the apps: /v1/auth/* to sign in, /v1/admin/* for everything else.
 * Every action is checked again by the server; this page only shows what the signed-in account may use. */
(() => {
  'use strict';

  // ---------- Small helpers ----------
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
  const num = (n) => Number(n || 0).toLocaleString('en-US');
  const usd = (minor) => '$' + (Number(minor || 0) / 100).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  const day = (iso) => (iso ? new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
  const when = (iso) => (iso ? new Date(iso).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
  const initials = (s) => String(s || '?').replace(/^Demo · /, '').trim().slice(0, 1).toUpperCase();
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* private mode */ } },
  };
  const VERSION = '0.8.0';

  // ---------- Icons (inline SVG, 24px grid) ----------
  const IC = {
    dashboard: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>',
    store: '<path d="M3 9l1.5-5h15L21 9"/><path d="M4 9v11h16V9"/><path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0"/><path d="M10 20v-5h4v5"/>',
    chart: '<path d="M3 3v18h18"/><path d="M7 15l4-4 3 3 5-6"/>',
    phone: '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
    image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
    tag: '<path d="M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7"/><path d="M18.5 20a6.5 6.5 0 0 0-3-5.5"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    crown: '<path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5L3 7z"/>',
    coins: '<circle cx="9" cy="9" r="6"/><path d="M15.5 9.2A6 6 0 1 1 9.2 15.5"/><path d="M9 6.5v5M7 9h4"/>',
    gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v9h14v-9"/><path d="M12 8v13"/><path d="M12 8S10.5 3 8 3a2.5 2.5 0 0 0 0 5h4zM12 8s1.5-5 4-5a2.5 2.5 0 0 1 0 5h-4z"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
    bell: '<path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
    chevd: '<path d="M6 9l6 6 6-6"/>',
    chevr: '<path d="M9 18l6-6-6-6"/>',
    chevl2: '<path d="M11 17l-5-5 5-5M18 17l-5-5 5-5"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5M21 12H9"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    x: '<path d="M18 6L6 18M6 6l12 12"/>',
    check: '<path d="M20 6L9 17l-5-5"/>',
    edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    trash: '<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>',
    upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5M12 3v12"/>',
    drag: '<circle cx="9" cy="6" r="1"/><circle cx="15" cy="6" r="1"/><circle cx="9" cy="12" r="1"/><circle cx="15" cy="12" r="1"/><circle cx="9" cy="18" r="1"/><circle cx="15" cy="18" r="1"/>',
    up: '<path d="M18 15l-6-6-6 6"/>',
    down: '<path d="M6 9l6 6 6-6"/>',
    pin: '<path d="M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
    percent: '<path d="M19 5L5 19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5M12 15V3"/>',
    eyeoff: '<path d="M17.9 17.9A10 10 0 0 1 12 20c-7 0-10-8-10-8a18 18 0 0 1 5-5.9M9.9 4.2A9 9 0 0 1 12 4c7 0 10 8 10 8a18 18 0 0 1-2.2 3.2M2 2l20 20"/>',
    eye: '<path d="M2 12s3-8 10-8 10 8 10 8-3 8-10 8-10-8-10-8z"/><circle cx="12" cy="12" r="3"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    receipt: '<path d="M5 3h14v18l-3-2-2 2-2-2-2 2-2-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
    box: '<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>',
    handshake: '<path d="M11 17l2 2a1.4 1.4 0 0 0 2-2"/><path d="M14 14l2.5 2.5a1.4 1.4 0 0 0 2-2L15 11"/><path d="M3 11l4-4 5 1 3-2 6 5-3 3"/><path d="M3 11l5 5a1.4 1.4 0 0 0 2-2"/>',
    star: '<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
    userplus: '<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0"/><path d="M19 8v6M16 11h6"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3"/>',
    send: '<path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4z"/>',
    calendar: '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    bag: '<path d="M6 7h12l1 14H5L6 7z"/><path d="M9 7a3 3 0 0 1 6 0"/>',
    alert: '<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    wallet: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M16 13h2"/><path d="M3 10h18"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>',
  };
  const ic = (n, cls = '') => `<svg class="i ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${IC[n] || ''}</svg>`;

  const S = {
    access: store.get('mk_admin_access'),
    refresh: store.get('mk_admin_refresh'),
    me: null,
    categories: [],
    shops: [],
    collapsed: store.get('mk_admin_collapsed') === '1',
  };
  const ROLE_NAME = { OWNER: 'Owner', ADMIN: 'Admin', EDITOR: 'Editor', SHOP: 'Shop account' };
  const isFull = () => ['OWNER', 'ADMIN'].includes(S.me?.role);
  const isContent = () => ['OWNER', 'ADMIN', 'EDITOR'].includes(S.me?.role);
  const isShop = () => S.me?.role === 'SHOP';

  const ERR = {
    VALIDATION_FAILED: 'Some fields are not valid. Please check and try again.',
    NOT_ADMIN: 'This number has no Mukafaah Manager account. Ask Mukafaah to create one for you.',
    FORBIDDEN_SCOPE: 'Your account can’t open this. Ask a Mukafaah admin.',
    OTP_INVALID: 'Wrong code. Try again.',
    OTP_TOO_MANY_ATTEMPTS: 'Too many wrong codes. Request a new one.',
    OTP_COOLDOWN: 'Please wait a moment before asking for another code.',
    OTP_LIMIT_PHONE: 'Too many codes for this number. Try again later.',
    OTP_LIMIT_IP: 'Too many codes from this network. Try again later.',
    CATEGORY_EXISTS: 'A category with this key already exists.',
    ACCOUNT_EXISTS: 'This number already has a Manager account.',
    SELF_CHANGE: 'You can’t switch off or change your own account.',
    USER_NOT_FOUND: 'No Mukafaah member with this number.',
    FORBIDDEN: 'Only the owner can do this.',
    NETWORK: 'Can’t reach the Mukafaah server. Is it running?',
  };

  // ---------- API ----------
  class ApiError extends Error {
    constructor(status, code, msg) { super(msg || code); this.status = status; this.code = code; }
  }
  let refreshing = null;
  async function refreshTokens() {
    if (!S.refresh) return false;
    if (!refreshing) {
      refreshing = fetch('/v1/auth/refresh', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refreshToken: S.refresh }) })
        .then(async (r) => {
          if (!r.ok) return false;
          const t = await r.json();
          setTokens(t.accessToken, t.refreshToken);
          return true;
        })
        .catch(() => false)
        .finally(() => { setTimeout(() => { refreshing = null; }, 0); });
    }
    return refreshing;
  }
  function setTokens(a, r) {
    S.access = a; S.refresh = r;
    store.set('mk_admin_access', a); store.set('mk_admin_refresh', r);
  }
  async function api(method, path, body, retry = true) {
    let res;
    try {
      res = await fetch(path, {
        method,
        headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...(S.access ? { authorization: 'Bearer ' + S.access } : {}) },
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
    } catch {
      throw new ApiError(0, 'NETWORK');
    }
    if (res.status === 401 && retry && S.refresh) {
      if (await refreshTokens()) return api(method, path, body, false);
      signOut();
      throw new ApiError(401, 'UNAUTHORIZED', 'Please sign in again.');
    }
    const data = res.status === 204 ? null : await res.json().catch(() => null);
    if (!res.ok) throw new ApiError(res.status, data?.code || data?.error?.code || 'HTTP_' + res.status, data?.title || data?.error?.message);
    return data;
  }
  const errText = (e) => ERR[e?.code] || e?.message || 'Something went wrong.';

  // ---------- Toasts, modal ----------
  function toast(msg, isErr = false) {
    let box = $('.toasts');
    if (!box) { box = document.createElement('div'); box.className = 'toasts'; document.body.appendChild(box); }
    const t = document.createElement('div');
    t.className = 'toast' + (isErr ? ' err' : '');
    t.setAttribute('role', 'status');
    t.innerHTML = `${ic(isErr ? 'alert' : 'check', 'sm')}<span>${esc(msg)}</span>`;
    box.appendChild(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 220); }, 3200);
  }
  const fail = (e) => toast(errText(e), true);

  /** Modal form. o: { save, size ('sm'|'lg'), sub, drawer, danger, noFoot }. onSave returning false keeps it open. */
  function modal(title, html, onSave, o = {}) {
    const bg = document.createElement('div');
    bg.className = 'mbg' + (o.drawer ? ' drawer' : '');
    bg.innerHTML = `<form class="modal ${o.size || ''}" novalidate role="dialog" aria-label="${esc(title)}">
      <div class="mh"><div><h3>${esc(title)}</h3>${o.sub ? `<div class="sub">${esc(o.sub)}</div>` : ''}</div><button type="button" class="iconbtn x" data-x aria-label="Close">${ic('x')}</button></div>
      <div class="mb">${html}</div>
      ${o.noFoot ? '' : `<div class="mf"><button type="button" class="btn sec" data-x>Cancel</button><button class="btn ${o.danger ? 'danger solid' : ''}" type="submit">${esc(o.save || 'Save')}</button></div>`}</form>`;
    const close = () => { bg.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    document.addEventListener('keydown', onKey);
    bg.addEventListener('mousedown', (e) => { if (e.target === bg) close(); });
    $$('[data-x]', bg).forEach((b) => (b.onclick = close));
    const form = $('form', bg);
    form.onsubmit = async (e) => {
      e.preventDefault();
      const btn = $('button[type=submit]', form);
      if (btn) btn.disabled = true;
      try { if ((await onSave(form)) !== false) close(); } catch (err) { fail(err); } finally { if (btn) btn.disabled = false; }
    };
    form.close = close;
    document.body.appendChild(bg);
    const first = $('.mb input:not([type=hidden]):not([type=file]):not([type=checkbox]), .mb select, .mb textarea', form);
    if (first) first.focus();
    return form;
  }
  function confirmBox(title, text, label = 'Delete') {
    return new Promise((resolve) => {
      let ok = false;
      const f = modal(title, `<p class="muted" style="margin:0">${esc(text)}</p>`, () => { ok = true; }, { save: label, danger: true, size: 'sm' });
      const obs = new MutationObserver(() => { if (!document.body.contains(f)) { obs.disconnect(); resolve(ok); } });
      obs.observe(document.body, { childList: true });
    });
  }

  /** Reads an image file, shrinks it if large, and uploads it. Returns {id, url}. */
  async function uploadImage(file, maxSide = 1600, target = null) {
    if (!/^image\/(png|jpeg|webp)$/.test(file.type)) throw new ApiError(400, 'X', 'Use a PNG, JPG or WebP image.');
    const dataUrl = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file); });
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = dataUrl; });
    let out = dataUrl;
    const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
    if (scale < 1 || file.size > 1_500_000) {
      const c = document.createElement('canvas');
      c.width = Math.round(img.width * scale); c.height = Math.round(img.height * scale);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      out = file.type === 'image/png' ? c.toDataURL('image/png') : c.toDataURL('image/jpeg', 0.86);
    }
    if (target) return api('POST', target.path, { purpose: target.purpose || 'item', dataBase64: out });
    return api('POST', '/v1/admin/media', { dataBase64: out });
  }
  const dropEmpty = (label) => `<div class="dz">${ic('upload', 'lg')}<span>${esc(label || 'Click or drop an image')}</span><small class="faint">PNG, JPG or WebP</small></div>`;
  const dropHtml = (name, url, label, hint = '') => `
    <label class="f"><span>${esc(label)}</span>
      <input type="hidden" name="${name}" value="">
      <div class="drop" data-drop="${name}" tabindex="0">${url ? `<img src="${esc(url)}" alt=""><span class="chg">Change</span>` : dropEmpty(hint)}</div>
      ${url ? `<div class="dropfoot"><button type="button" class="btn ghost sm" data-clear="${name}">${ic('trash', 'sm')} Remove image</button></div>` : ''}
    </label>`;
  /** Wires a .drop box: click or drop to choose an image, uploads it, stores the id in the hidden input. */
  function wireDrop(form, name, maxSide, target = null) {
    const box = $(`[data-drop="${name}"]`, form);
    const hidden = $(`input[name="${name}"]`, form);
    if (!box) return;
    const file = document.createElement('input');
    file.type = 'file'; file.accept = 'image/png,image/jpeg,image/webp'; file.hidden = true;
    box.after(file);
    const take = async (f) => {
      if (!f) return;
      box.innerHTML = '<div class="skel h120" style="width:100%"></div>';
      try {
        const m = await uploadImage(f, maxSide, target);
        hidden.value = m.id;
        box.innerHTML = `<img src="${esc(m.url)}" alt=""><span class="chg">Change</span>`;
        box.dispatchEvent(new Event('change', { bubbles: true }));
      } catch (e) { box.innerHTML = dropEmpty(); fail(e); }
    };
    box.onclick = () => file.click();
    box.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); file.click(); } };
    box.ondragover = (e) => { e.preventDefault(); };
    box.ondrop = (e) => { e.preventDefault(); take(e.dataTransfer.files[0]); };
    file.onchange = () => take(file.files[0]);
    const clear = $(`[data-clear="${name}"]`, form);
    if (clear) clear.onclick = () => { hidden.value = ''; box.innerHTML = dropEmpty(); clear.remove(); box.dataset.cleared = '1'; box.dispatchEvent(new Event('change', { bubbles: true })); };
  }
  const dropCleared = (form, name) => $(`[data-drop="${name}"]`, form)?.dataset.cleared === '1';

  const toggle = (name, on, attrs = '') => `<label class="sw"><input type="checkbox" name="${name}" ${on ? 'checked' : ''} ${attrs}><i></i></label>`;
  const opt = (v, label, cur) => `<option value="${esc(v)}" ${String(v) === String(cur ?? '') ? 'selected' : ''}>${esc(label)}</option>`;
  const val = (form, n) => { const el = form.elements[n]; return el ? String(el.value).trim() : ''; };
  const orNull = (s) => (s === '' ? null : s);
  const empty = (icon, title, text, action = '') => `<div class="empty"><div class="ei">${ic(icon, 'lg')}</div><b>${esc(title)}</b>${text ? `<p>${esc(text)}</p>` : ''}${action}</div>`;
  const skeleton = (rows = 5) => `<div class="card flush">${Array.from({ length: rows }, () => '<div class="skrow"><div class="skel h28" style="width:28px"></div><div class="skel h12" style="flex:1"></div><div class="skel h12" style="width:80px"></div></div>').join('')}</div>`;

  /** Drag-to-reorder for a .list; saves the new order through /reorder. */
  function sortable(list, type, after) {
    let dragged = null;
    $$('.item, .ccard', list).forEach((it) => {
      const h = $('.handle', it);
      if (!h) return;
      h.addEventListener('mousedown', () => { it.draggable = true; });
      h.addEventListener('touchstart', () => { it.draggable = true; }, { passive: true });
      it.addEventListener('dragstart', (e) => { dragged = it; it.classList.add('drag'); e.dataTransfer.effectAllowed = 'move'; });
      it.addEventListener('dragend', async () => {
        it.classList.remove('drag'); it.draggable = false;
        const ids = $$('[data-id]', list).map((x) => x.dataset.id);
        try { await api('POST', '/v1/admin/reorder', { type, ids }); toast('Order saved'); if (after) after(); } catch (e) { fail(e); }
      });
      it.addEventListener('dragover', (e) => {
        e.preventDefault();
        if (!dragged || dragged === it) return;
        const r = it.getBoundingClientRect();
        const before = list.classList.contains('cgrid') ? e.clientX < r.left + r.width / 2 : e.clientY < r.top + r.height / 2;
        list.insertBefore(dragged, before ? it : it.nextSibling);
      });
    });
  }
  /** Up/down buttons as a keyboard- and touch-friendly fallback. */
  async function moveItem(list, id, dir, type, after) {
    const items = $$('[data-id]', list);
    const i = items.findIndex((x) => x.dataset.id === id);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= items.length) return;
    if (dir < 0) list.insertBefore(items[i], items[j]); else list.insertBefore(items[j], items[i]);
    try { await api('POST', '/v1/admin/reorder', { type, ids: $$('[data-id]', list).map((x) => x.dataset.id) }); if (after) after(); } catch (e) { fail(e); }
  }

  // =====================================================================
  // Sign in
  // =====================================================================
  function signOut() {
    const r = S.refresh;
    if (r) fetch('/v1/auth/logout', { method: 'POST', headers: { 'content-type': 'application/json', ...(S.access ? { authorization: 'Bearer ' + S.access } : {}) }, body: JSON.stringify({ refreshToken: r }) }).catch(() => {});
    setTokens(null, null);
    S.me = null; S.shops = []; S.categories = [];
    renderLogin();
  }

  function renderLogin(msg) {
    $('#app').innerHTML = `
      <div class="auth">
        <section class="auth-brand"><div class="rings"></div>
          <div class="auth-logo" role="img" aria-label="Mukafaah"></div>
          <h1>Run every shop. <em>One dashboard.</em></h1>
          <p class="lead">Mukafaah Manager is where shops, the customer app and the loyalty programme are managed across Lebanon.</p>
          <ul class="auth-points">
            <li><span class="dot">${ic('store', 'sm')}</span><div><b>Shops and stores</b><small>Profiles, offers, products and orders for every shop.</small></div></li>
            <li><span class="dot">${ic('chart', 'sm')}</span><div><b>Monthly reports</b><small>Sales, customers and points, month on month.</small></div></li>
            <li><span class="dot">${ic('shield', 'sm')}</span><div><b>Accounts made by Mukafaah</b><small>Shop owners only see their own shop.</small></div></li>
          </ul>
          <div class="auth-foot">Mukafaah Manager · v${VERSION}</div>
        </section>
        <section class="auth-form"><div class="auth-card" id="ac"></div></section>
      </div>`;
    stepPhone(msg);
  }
  const flag = '<span class="flag" aria-hidden="true"><i></i><i></i><i></i></span>';
  function stepPhone(msg, phone = '') {
    const ac = $('#ac');
    ac.innerHTML = `
      <div class="mobile-brand"><span class="mark lg"></span><b>Mukafaah Manager</b></div>
      <h2>Sign in</h2>
      <p class="sub">Use the phone number Mukafaah registered for you. We’ll text you a code.</p>
      ${msg ? `<div class="alert bad">${ic('alert', 'sm')}<div>${esc(msg)}</div></div>` : ''}
      <form id="f1" novalidate>
        <label class="f"><span>Phone number</span><div class="phone-in"><span class="cc">${flag}+961</span><input name="phone" inputmode="tel" autocomplete="tel" placeholder="70 123 456" value="${esc(phone)}" required></div></label>
        <button class="btn lg block">Send code</button>
      </form>`;
    const f1 = $('#f1');
    f1.elements.phone.focus();
    f1.onsubmit = async (e) => {
      e.preventDefault();
      const btn = $('button', f1); btn.disabled = true; btn.innerHTML = '<span class="spin"></span>';
      try {
        const p = val(f1, 'phone');
        const r = await api('POST', '/v1/auth/otp/request', { phone: p, app: 'ADMIN', locale: 'en' });
        stepCode(p, r);
      } catch (err) { stepPhone(errText(err), val(f1, 'phone')); }
    };
  }
  function stepCode(phone, ch) {
    const ac = $('#ac');
    ac.innerHTML = `
      <button class="auth-back" id="back">${ic('chevl2', 'sm')} Change number</button>
      <h2>Enter the code</h2>
      <p class="sub">We sent a 6-digit code to +961 ${esc(phone)}.</p>
      ${ch.devCode ? `<div class="dev-code">${ic('info', 'sm')}<span>Test server: your code is <b>${esc(ch.devCode)}</b></span></div>` : ''}
      <div id="err"></div>
      <form id="f2" novalidate>
        <div class="otp">${Array.from({ length: 6 }, (_, i) => `<input inputmode="numeric" maxlength="6" aria-label="Digit ${i + 1}" ${i === 0 ? 'autocomplete="one-time-code"' : ''}>`).join('')}</div>
        <button class="btn lg block" style="margin-top:20px">Sign in</button>
      </form>
      <div class="resend">Didn’t get it? <button id="again" disabled>Send again in <span id="cd">30</span>s</button></div>`;
    const boxes = $$('.otp input', ac);
    const code = () => boxes.map((b) => b.value).join('');
    boxes.forEach((b, i) => {
      b.oninput = () => {
        const d = b.value.replace(/\D/g, '');
        if (d.length > 1) { d.split('').slice(0, 6 - i).forEach((x, k) => { boxes[i + k].value = x; boxes[i + k].classList.add('filled'); }); boxes[Math.min(5, i + d.length)].focus(); }
        else { b.value = d; b.classList.toggle('filled', !!d); if (d && i < 5) boxes[i + 1].focus(); }
        if (code().length === 6) $('#f2').requestSubmit();
      };
      b.onkeydown = (e) => { if (e.key === 'Backspace' && !b.value && i > 0) boxes[i - 1].focus(); };
    });
    boxes[0].focus();
    let left = 30;
    const t = setInterval(() => { left--; const cd = $('#cd'); if (!cd) return clearInterval(t); if (left <= 0) { clearInterval(t); $('#again').disabled = false; $('#again').textContent = 'Send again'; } else cd.textContent = left; }, 1000);
    $('#again').onclick = async () => { try { stepCode(phone, await api('POST', '/v1/auth/otp/request', { phone, app: 'ADMIN', locale: 'en' })); } catch (e) { fail(e); } };
    $('#back').onclick = () => { clearInterval(t); stepPhone('', phone); };
    $('#f2').onsubmit = async (e) => {
      e.preventDefault();
      if (code().length !== 6) return;
      const btn = $('#f2 button'); btn.disabled = true; btn.innerHTML = '<span class="spin"></span>';
      try {
        const r = await api('POST', '/v1/auth/otp/verify', { challengeId: ch.challengeId, code: code(), app: 'ADMIN', deviceLabel: 'Mukafaah Manager (web)' }, false);
        setTokens(r.accessToken, r.refreshToken);
        clearInterval(t);
        await boot();
      } catch (err) {
        btn.disabled = false; btn.textContent = 'Sign in';
        $('#err').innerHTML = `<div class="alert bad">${ic('alert', 'sm')}<div>${esc(errText(err))}</div></div>`;
        boxes.forEach((b) => { b.value = ''; b.classList.remove('filled'); }); boxes[0].focus();
      }
    };
  }

  // =====================================================================
  // Shell
  // =====================================================================
  function navGroups() {
    if (isShop()) {
      const shops = S.me.shops || [];
      return [['My shop', [
        ...(shops.length === 1 ? [['shop/' + shops[0].id, 'store', shops[0].name]] : [['myshops', 'store', 'My shops']]),
        ['reports', 'chart', 'Monthly report'],
      ]]];
    }
    const g = [
      ['Main', [['overview', 'dashboard', 'Overview'], ['shops', 'store', 'Shops'], ['reports', 'chart', 'Monthly report'], ['customers', 'users', 'Customers']]],
      ['Customer app', [['home', 'phone', 'Home screen'], ['banners', 'image', 'Banners'], ['categories', 'grid', 'Categories'], ['offers', 'tag', 'Offers']]],
    ];
    if (isFull()) {
      g.push(['Loyalty', [['tiers', 'crown', 'Tiers'], ['mukafaah', 'coins', 'Mukafaah Points']]]);
      g.push(['Admin', [['accounts', 'shield', 'Accounts'], ['settings', 'settings', 'Settings']]]);
    }
    return g;
  }
  function renderShell() {
    $('#app').innerHTML = `
      <div class="shell ${S.collapsed ? 'collapsed' : ''}" id="shell">
        <aside class="side" id="side" aria-label="Main menu">
          <div class="side-head"><span class="mark"></span><div class="bt"><b>Mukafaah</b><small>Manager</small></div></div>
          <nav class="side-scroll">${navGroups().map(([g, items]) => `<div class="nav-g"><div class="gl">${esc(g)}</div>${items.map(([k, i, l]) => `<a class="nav" href="#${esc(k)}" data-nav="${esc(k)}" title="${esc(l)}">${ic(i)}<span class="lbl">${esc(l)}</span></a>`).join('')}</div>`).join('')}</nav>
          <div class="side-foot"><button class="nav collapse-btn" id="collapse" title="Collapse menu">${ic('chevl2', 'collapse-ic')}<span class="lbl">Collapse</span></button><div class="ver">v${VERSION}</div></div>
        </aside>
        <div class="main">
          <header class="top" id="top">
            <button class="iconbtn burger" id="burger" aria-label="Menu">${ic('menu')}</button>
            <div class="crumbs" id="crumbs"></div>
            ${isShop() ? '<span class="spacer"></span>' : `<div class="gsearch" id="gs"><button class="iconbtn sbtn" id="sbtn" aria-label="Search">${ic('search')}</button><div class="box">${ic('search', 'sm')}<input id="gq" placeholder="Search shops" autocomplete="off"><kbd>/</kbd></div></div>`}
            ${isShop() ? '' : `<div class="top-act"><button class="iconbtn" id="bell" aria-label="Activity">${ic('bell')}<span class="badge-dot" id="bdot" hidden></span></button></div>`}
            <div class="top-act"><button class="userbtn" id="ub" aria-haspopup="menu"><span class="avatar">${esc(initials(S.me.name || 'M'))}</span><span class="un">${esc(S.me.name || 'Manager')}</span>${ic('chevd', 'sm chev')}</button></div>
          </header>
          <main class="content" id="view"></main>
        </div>
      </div>`;
    const shell = $('#shell');
    $('#collapse').onclick = () => { S.collapsed = !S.collapsed; shell.classList.toggle('collapsed', S.collapsed); store.set('mk_admin_collapsed', S.collapsed ? '1' : null); };
    const closeNav = () => { shell.classList.remove('nav-open'); $('.scrim')?.remove(); };
    $('#burger').onclick = () => {
      shell.classList.add('nav-open');
      const sc = document.createElement('div'); sc.className = 'scrim'; sc.onclick = closeNav; document.body.appendChild(sc);
    };
    $('#side').addEventListener('click', (e) => { if (e.target.closest('.nav')) closeNav(); });
    $('#ub').onclick = (e) => {
      e.stopPropagation();
      popup($('#ub').parentElement, `<div class="pop umenu" role="menu">
        <div class="uh"><span class="avatar">${esc(initials(S.me.name || 'M'))}</span><div><b>${esc(S.me.name || 'Manager')}</b><small>${S.me.phoneLast4 ? '•••• ' + esc(S.me.phoneLast4) + ' · ' : ''}<span class="role ${esc(S.me.role)}">${esc(ROLE_NAME[S.me.role] || S.me.role)}</span></small></div></div>
        <div class="sep"></div><button class="pi" id="out">${ic('logout', 'sm')}<span class="t"><b>Sign out</b></span></button></div>`);
      $('#out').onclick = signOut;
    };
    if (!isShop()) {
      wireSearch();
      $('#bell').onclick = async (e) => {
        e.stopPropagation();
        const host = $('#bell').parentElement;
        popup(host, `<div class="pop notif"><div class="ph2">Activity</div><div class="skel h40"></div></div>`);
        try {
          const o = await api('GET', '/v1/admin/overview');
          const pop = $('.pop', host); if (!pop) return;
          pop.innerHTML = `<div class="ph2">Activity</div>
            <a class="pi" href="#shops"><span class="ni y">${ic('calendar', 'sm')}</span><span class="t"><b>${num(o.pendingBookings)} booking requests waiting</b><small>Shops accept them in the Business app</small></span></a>
            <a class="pi" href="#reports"><span class="ni">${ic('bag', 'sm')}</span><span class="t"><b>${num(o.orders30d)} store orders</b><small>Last 30 days</small></span></a>
            <a class="pi" href="#customers"><span class="ni g">${ic('userplus', 'sm')}</span><span class="t"><b>${num(o.newUsers7d)} new customers</b><small>Last 7 days</small></span></a>`;
          $('#bdot').hidden = true;
        } catch (err) { fail(err); }
      };
      api('GET', '/v1/admin/overview').then((o) => { const d = $('#bdot'); if (d) d.hidden = !(o.pendingBookings > 0); }).catch(() => {});
    }
  }
  function popup(host, html) {
    $$('.pop').forEach((p) => p.remove());
    host.insertAdjacentHTML('beforeend', html);
    const pop = host.lastElementChild;
    const off = (e) => { if (!pop.contains(e.target)) { pop.remove(); document.removeEventListener('mousedown', off); } };
    setTimeout(() => document.addEventListener('mousedown', off), 0);
    return pop;
  }
  function wireSearch() {
    const gq = $('#gq'), gs = $('#gs'), top = $('#top');
    const draw = async () => {
      const q = gq.value.trim().toLowerCase();
      $('.pop', gs)?.remove();
      if (!q) return;
      if (!S.shops.length) { try { await loadShops(); } catch { return; } }
      const hits = S.shops.filter((s) => (s.name + ' ' + (s.city || '')).toLowerCase().includes(q)).slice(0, 8);
      gs.insertAdjacentHTML('beforeend', `<div class="pop">${hits.length ? `<div class="ph">Shops</div>${hits.map((s, i) => `<a class="pi ${i === 0 ? 'act' : ''}" href="#shop/${esc(s.id)}"><span class="thumb">${s.logoUrl ? `<img src="${esc(s.logoUrl)}" alt="">` : esc(initials(s.name))}</span><span class="t"><b>${esc(s.name)}</b><small>${esc(s.city || '—')} · ${esc(s.earnPercent)}% back</small></span></a>`).join('')}` : '<div class="empty-s">No shops match.</div>'}</div>`);
    };
    gq.oninput = draw;
    gq.onkeydown = (e) => {
      if (e.key === 'Enter') { const a = $('.pop .pi.act', gs); if (a) { location.hash = a.getAttribute('href').slice(1); gq.value = ''; draw(); top.classList.remove('searching'); } }
      if (e.key === 'Escape') { gq.value = ''; draw(); gq.blur(); top.classList.remove('searching'); }
    };
    gq.onblur = () => setTimeout(() => { $('.pop', gs)?.remove(); top.classList.remove('searching'); }, 150);
    $('#sbtn').onclick = () => { top.classList.add('searching'); gq.focus(); };
    document.addEventListener('keydown', (e) => { if (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName || '') && $('#gq')) { e.preventDefault(); $('#gq').focus(); } });
  }

  function crumbs(parts) {
    const c = $('#crumbs'); if (!c) return;
    c.innerHTML = parts.map((p, i) => (i === parts.length - 1 ? `<b>${esc(p[0])}</b>` : `<a href="#${esc(p[1])}">${esc(p[0])}</a>${ic('chevr', 'xs')}`)).join('');
    document.title = parts[parts.length - 1][0] + ' · Mukafaah Manager';
  }
  /** Page header row. */
  const ph = (title, sub, acts = '') => `<div class="ph-row"><div class="tt"><h1>${esc(title)}</h1>${sub ? `<div class="sub">${esc(sub)}</div>` : ''}</div>${acts ? `<div class="acts">${acts}</div>` : ''}</div>`;
  function mount(html) {
    const v = $('#view');
    v.innerHTML = `<div class="page">${html}</div>`;
    return v;
  }
  const loading = (title) => mount(ph(title) + skeleton());

  async function loadCategories() { S.categories = await api('GET', '/v1/admin/categories'); return S.categories; }
  async function loadShops() { S.shops = await api('GET', '/v1/admin/shops'); return S.shops; }
  const catName = (key) => S.categories.find((c) => c.key === key)?.nameEn || key;
  const catTile = (c, cls = '') => `<span class="ctile ${cls}" style="${c?.color ? `background:${esc(c.color)}1f;color:${esc(c.color)}` : ''}">${c?.iconUrl ? `<img src="${esc(c.iconUrl)}" alt="">` : esc(initials(c?.nameEn || '?'))}</span>`;

  // =====================================================================
  // Overview
  // =====================================================================
  const kpi = (label, value, icon, foot = '', cls = '', kicls = '') => `<div class="card kpi ${cls}"><div class="kh"><span class="ki ${kicls}">${ic(icon, 'sm')}</span>${esc(label)}</div><div class="kv">${value}</div><div class="kf">${foot}</div></div>`;
  async function pageOverview() {
    crumbs([['Overview']]);
    loading('Overview');
    const o = await api('GET', '/v1/admin/overview');
    const maxV = Math.max(1, ...o.topShops.map((s) => s.visits));
    const hr = new Date().getHours();
    mount(ph(`Good ${hr < 12 ? 'morning' : hr < 18 ? 'afternoon' : 'evening'}${S.me.name ? ', ' + S.me.name.split(' ')[0] : ''}`, 'Mukafaah across Lebanon, last 30 days.', `<a class="btn sec" href="#reports">${ic('chart', 'sm')} Monthly report</a>${isFull() ? `<button class="btn" id="addShop">${ic('plus', 'sm')} Add shop</button>` : ''}`) + `
      <div class="grid g4">
        ${kpi('Bills recorded', usd(o.bills30dMinor), 'receipt', 'Collected at shop counters', 'hero')}
        ${kpi('Points given', num(o.issued30d), 'coins', `≈ ${usd(o.issued30d)} in rewards`, '', 'y')}
        ${kpi('Points redeemed', num(o.redeemed30d), 'gift', o.issued30d ? `${Math.round((o.redeemed30d * 100) / o.issued30d)}% of given` : '', '', 'g')}
        ${kpi('Customers', num(o.users), 'users', `<span class="dl up">+${num(o.newUsers7d)}</span> this week`)}
      </div>
      <div class="grid g4 mt16">
        ${kpi('Live shops', num(o.liveShops), 'store', `of ${num(o.shops)} shops`, 'sm')}
        ${kpi('Live offers', num(o.liveOffers), 'tag', '', 'sm')}
        ${kpi('Bookings waiting', num(o.pendingBookings), 'calendar', 'Shops accept in the Business app', 'sm')}
        ${kpi('Store orders', num(o.orders30d), 'bag', 'Sent on WhatsApp', 'sm')}
      </div>
      <div class="grid g21 mt16">
        <div class="card"><div class="card-h"><h3>Busiest shops</h3><span class="sp"></span><a class="btn ghost sm" href="#shops">All shops ${ic('chevr', 'xs')}</a></div>
          ${o.topShops.length ? `<div class="ranked">${o.topShops.map((s, i) => `<a class="rk" href="#shop/${esc(s.id)}"><span class="n">${i + 1}</span><span class="t"><b>${esc(s.name)}</b><div class="bar"><i style="width:${Math.round((s.visits / maxV) * 100)}%"></i></div></span><span class="v"><b>${num(s.visits)} visits</b>${usd(s.billsMinor)}</span></a>`).join('')}</div>` : empty('store', 'No shops yet', 'Add the first shop to get started.')}
        </div>
        <div class="card"><div class="card-h"><h3>Quick actions</h3></div><div class="qa">
          ${isFull() ? `<a href="#shops" data-add>${'<span class="qi">' + ic('store', 'sm') + '</span>'}<span class="qt"><b>Add a shop</b><small>Owner signs in with their phone</small></span>${ic('chevr', 'sm')}</a>` : ''}
          <a href="#banners"><span class="qi">${ic('image', 'sm')}</span><span class="qt"><b>Banners</b><small>Uno, Duo or Trio on the home screen</small></span>${ic('chevr', 'sm')}</a>
          <a href="#categories"><span class="qi">${ic('grid', 'sm')}</span><span class="qt"><b>Categories</b><small>Logos and colours</small></span>${ic('chevr', 'sm')}</a>
          ${isFull() ? `<a href="#mukafaah"><span class="qi">${ic('coins', 'sm')}</span><span class="qt"><b>Give Mukafaah Points</b><small>Rewards for referrals and tasks</small></span>${ic('chevr', 'sm')}</a>
          <a href="#accounts"><span class="qi">${ic('shield', 'sm')}</span><span class="qt"><b>Accounts</b><small>Who can sign in here</small></span>${ic('chevr', 'sm')}</a>` : ''}
        </div></div>
      </div>`);
    const add = $('#addShop'); if (add) add.onclick = addShop;
    const qa = $('[data-add]'); if (qa) qa.onclick = (e) => { e.preventDefault(); addShop(); };
  }

  // =====================================================================
  // Shops
  // =====================================================================
  async function pageShops() {
    crumbs([['Shops']]);
    loading('Shops');
    await Promise.all([loadCategories(), loadShops()]);
    const v = mount(ph('Shops', 'Every shop on Mukafaah. Only Mukafaah adds shops; the owner signs in to the Business app with the phone you enter.', isFull() ? `<button class="btn" id="addShop">${ic('plus', 'sm')} Add shop</button>` : '') + `
      <div class="card flush">
        <div class="toolbar"><div class="inwrap">${ic('search', 'sm')}<input class="in" id="q" placeholder="Search shops or city"></div>
          <div class="seg" id="st"><button class="on" data-s="">All</button><button data-s="ACTIVE">Active</button><button data-s="SUSPENDED">Suspended</button></div>
          <span class="cnt" id="cnt"></span></div>
        <div class="tw"><table class="tbl"><thead><tr><th>Shop</th><th>Category</th><th>Points back</th><th>Store</th><th>Friends</th><th>Featured</th><th>Listed</th><th class="r">30 days</th><th></th></tr></thead><tbody id="tb"></tbody></table></div>
      </div>`);
    let status = '';
    const draw = () => {
      const q = $('#q', v).value.trim().toLowerCase();
      const list = S.shops.filter((s) => (!q || (s.name + ' ' + (s.city || '')).toLowerCase().includes(q)) && (!status || s.status === status));
      $('#cnt', v).textContent = `${list.length} of ${S.shops.length}`;
      $('#tb', v).innerHTML = list.length ? list.map((s) => `
        <tr data-id="${esc(s.id)}" class="${s.status === 'ACTIVE' ? '' : 'off'}">
          <td><div class="who"><span class="thumb ${s.logoUrl ? '' : 'c'}">${s.logoUrl ? `<img src="${esc(s.logoUrl)}" alt="">` : esc(initials(s.name))}</span><div class="t"><a href="#shop/${esc(s.id)}"><b>${esc(s.name)}</b></a><small>${esc(s.city || '—')} · ${esc(s.owner)}</small></div></div></td>
          <td><select class="in sm" data-f="category" style="min-width:150px">${S.categories.map((c) => opt(c.key, c.nameEn, s.category)).join('')}</select></td>
          <td><span class="pct"><input class="in sm" type="number" min="0" max="100" step="1" value="${esc(s.earnPercent)}" data-f="earnPercent" aria-label="Points back percent"></span></td>
          <td>${s.storeEnabled ? '<span class="pill ok">On</span>' : '<span class="pill">Off</span>'}</td>
          <td>${s.friendsEnabled ? `<span class="pill pur">Up to ${num(s.friendsMaxPoints)}</span>` : '<span class="faint">—</span>'}</td>
          <td>${toggle('featured', s.featured, 'data-f="featured" aria-label="Featured"')}</td>
          <td>${toggle('listed', s.listed, 'data-f="listed" aria-label="Visible in app"')}</td>
          <td class="r num"><span class="muted">${num(s.visits30d)} visits · ${num(s.offers)} offers</span></td>
          <td><div class="acts"><a class="btn sec sm" href="#shop/${esc(s.id)}">Open</a></div></td>
        </tr>`).join('') : `<tr><td colspan="9">${empty('search', 'No shops match', 'Try another search or filter.')}</td></tr>`;
    };
    draw();
    const add = $('#addShop', v); if (add) add.onclick = addShop;
    $('#q', v).oninput = draw;
    $('#st', v).onclick = (e) => { const b = e.target.closest('[data-s]'); if (!b) return; status = b.dataset.s; $$('#st button', v).forEach((x) => x.classList.toggle('on', x === b)); draw(); };
    const patch = async (id, body, msg) => {
      try { await api('PATCH', '/v1/admin/shops/' + id, body); Object.assign(S.shops.find((s) => s.id === id), body); toast(msg); } catch (e) { fail(e); draw(); }
    };
    $('#tb', v).addEventListener('change', (e) => {
      const el = e.target, tr = el.closest('tr'), f = el.dataset.f;
      if (!tr || !f) return;
      const id = tr.dataset.id, name = S.shops.find((s) => s.id === id)?.name;
      if (f === 'earnPercent') {
        const n = Math.round(Number(el.value));
        if (!Number.isFinite(n) || n < 0 || n > 100) { toast('Use a whole number from 0 to 100.', true); return; }
        el.value = n; patch(id, { earnPercent: n }, `${name}: customers now get ${n}% back`);
      } else if (f === 'category') patch(id, { category: el.value }, `${name} moved to ${catName(el.value)}`);
      else if (f === 'featured') patch(id, { featured: el.checked }, el.checked ? `${name} is featured` : `${name} is no longer featured`);
      else if (f === 'listed') patch(id, { listed: el.checked }, el.checked ? `${name} is visible in the app` : `${name} is hidden from the app`);
    });
  }

  /** Reads "lat, lng" or a Google Maps link and returns [lat, lng] or null. */
  function parseLatLng(s) {
    const m = String(s || '').match(/(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})/) || String(s || '').match(/@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)/);
    return m ? [Number(m[1]), Number(m[2])] : null;
  }
  async function addShop() {
    if (!S.categories.length) await loadCategories();
    modal('Add a shop', `
      <div class="alert info">${ic('info', 'sm')}<div>The owner signs in to the Business app with this phone number. Nothing to sign up on their side.</div></div>
      <label class="f"><span>Shop name</span><input class="in" name="name" maxlength="80" required></label>
      <div class="fgrid">
        <label class="f"><span>Category</span><select class="in" name="category">${S.categories.filter((c) => c.active).map((c) => opt(c.key, c.nameEn, '')).join('')}</select></label>
        <label class="f"><span>Points back</span><span class="pct" style="width:100%"><input class="in" type="number" name="earnPercent" min="0" max="100" value="10" style="width:100%"></span></label>
        <label class="f"><span>Owner phone</span><div class="phone-in sm"><span class="cc">${flag}+961</span><input name="ownerPhone" inputmode="tel" placeholder="70 123 456" required></div></label>
        <label class="f"><span>Owner name</span><input class="in" name="ownerName" maxlength="60"></label>
        <label class="f"><span>City</span><input class="in" name="city" maxlength="60" placeholder="Beirut"></label>
        <label class="f"><span>Area / street</span><input class="in" name="address" maxlength="160" placeholder="Hamra"></label>
        <label class="f"><span>WhatsApp for orders</span><input class="in" name="whatsapp" inputmode="tel" placeholder="+961 …"></label>
        <label class="f"><span>Instagram</span><input class="in" name="instagram" maxlength="60"></label>
      </div>
      <label class="f"><span>Location</span><input class="in" name="loc" placeholder='Google Maps link or "33.8966, 35.4823"'><em>Used for the map in the customer app.</em></label>
      <label class="f"><span>About the shop</span><textarea class="in" name="description" maxlength="600"></textarea></label>
      <div class="optcard hl"><div class="swrow">${toggle('managerAccess', false)}<div class="t"><b>Give the owner a Manager account</b><small>They can sign in here too, and only see their own shop: profile, offers, store, orders, bills and its monthly report.</small></div></div></div>`,
    async (f) => {
      const ll = parseLatLng(val(f, 'loc'));
      if (val(f, 'loc') && !ll) { toast('Couldn’t read that location. Paste a Google Maps link or "lat, lng".', true); return false; }
      const body = {
        name: val(f, 'name'), category: val(f, 'category'), ownerPhone: val(f, 'ownerPhone'), earnPercent: Math.round(Number(val(f, 'earnPercent')) || 0),
        managerAccess: f.elements.managerAccess.checked,
        ...(val(f, 'ownerName') ? { ownerName: val(f, 'ownerName') } : {}), ...(val(f, 'city') ? { city: val(f, 'city') } : {}),
        ...(val(f, 'address') ? { address: val(f, 'address') } : {}), ...(val(f, 'whatsapp') ? { whatsapp: val(f, 'whatsapp') } : {}),
        ...(val(f, 'instagram') ? { instagram: val(f, 'instagram').replace(/^@/, '') } : {}), ...(val(f, 'description') ? { description: val(f, 'description') } : {}),
        ...(ll ? { lat: ll[0], lng: ll[1] } : {}),
      };
      if (!body.name || !body.ownerPhone) { toast('Add the shop name and the owner’s phone.', true); return false; }
      const r = await api('POST', '/v1/admin/shops', body);
      toast('Shop added. Add its photos, offers and products next.');
      S.shops = [];
      location.hash = 'shop/' + r.id + '/profile';
    }, { save: 'Add shop', size: 'lg' });
  }

  // =====================================================================
  // Shop workspace: everything about one shop
  // =====================================================================
  const WS_TABS = [
    ['overview', 'Overview', 'dashboard'], ['profile', 'Profile', 'store'], ['offers', 'Offers', 'tag'], ['rewards', 'Rewards', 'gift'],
    ['store', 'Online store', 'bag'], ['orders', 'Orders', 'box'], ['bookings', 'Bookings', 'calendar'], ['team', 'Cashiers', 'users'], ['bills', 'Bills', 'receipt'],
  ];
  const ST_CLS = { ACTIVE: 'ok', PAUSED: '', ARCHIVED: '', REQUESTED: 'y', ACCEPTED: 'pur', DECLINED: 'bad', CANCELLED: 'bad', REDEEMED: 'ok', EXPIRED: '', NEW: 'y', CONFIRMED: 'pur', READY: 'ok', COMPLETED: 'ok' };
  const pill = (st) => `<span class="pill ${ST_CLS[st] || ''}">${esc(st.charAt(0) + st.slice(1).toLowerCase())}</span>`;
  const base = (shop) => `/v1/admin/shops/${shop.id}`;

  async function pageShop(id, tab = 'overview') {
    loading('Shop');
    if (!S.categories.length) { try { await loadCategories(); } catch { /* shop accounts can't list categories */ } }
    if (!S.shops.length) { try { await loadShops(); } catch { /* ignore */ } }
    const shop = await api('GET', `/v1/admin/shops/${id}`);
    const row = S.shops.find((s) => s.id === id) || {};
    shop.friendsEnabled = !!row.friendsEnabled; shop.friendsMaxPoints = row.friendsMaxPoints ?? 0;
    crumbs(isShop() ? [[shop.name]] : [['Shops', 'shops'], [shop.name]]);
    const v = mount(`
      ${isShop() ? '' : `<a class="backlink" href="#shops">${ic('chevl2', 'xs')} All shops</a>`}
      <div class="card ws-head">
        <div class="ws-cover ${shop.coverUrl ? 'img' : ''}" style="${shop.coverUrl ? `background-image:url('${esc(shop.coverUrl)}')` : ''}"></div>
        <div class="ws-id">
          <div class="ws-logo">${shop.logoUrl ? `<img src="${esc(shop.logoUrl)}" alt="">` : esc(initials(shop.name))}</div>
          <div class="nm"><h1>${esc(shop.name)}</h1>
            <div class="meta"><span>${ic('grid', 'xs')} ${esc(catName(shop.category))}</span><span>${ic('pin', 'xs')} ${esc(shop.city || 'No city')}</span><span>${ic('users', 'xs')} Owner ${esc(shop.owner?.name || '')} ${esc(shop.owner?.phone || '')}</span></div></div>
          <div class="ws-pills">
            ${shop.status === 'ACTIVE' ? '<span class="pill ok">Active</span>' : `<span class="pill bad">${esc(shop.status)}</span>`}
            ${shop.listed === false ? '<span class="pill">Hidden from app</span>' : '<span class="pill pur">In the app</span>'}
            <span class="pill dark nodot">${esc(shop.earnPercent)}% back</span>
            ${shop.storeEnabled ? '<span class="pill ok">Store on</span>' : ''}
            ${shop.friendsEnabled ? '<span class="pill y">Mukafaah Friend</span>' : ''}
          </div>
        </div>
      </div>
      <div class="tabs ws-tabs">${WS_TABS.map(([k, t, i]) => `<a class="tab ${k === tab ? 'on' : ''}" href="#shop/${esc(id)}/${k}">${ic(i, 'sm')}${esc(t)}</a>`).join('')}</div>
      <div class="ws-body" id="ws"></div>`);
    const ws = $('#ws', v);
    const T = { overview: wsOverview, profile: wsProfile, offers: wsOffers, rewards: wsRewards, store: wsStore, orders: wsOrders, bookings: wsBookings, team: wsTeam, bills: wsBills }[tab] || wsOverview;
    ws.innerHTML = skeleton(4);
    try { await T(ws, shop); } catch (e) { ws.innerHTML = `<div class="card">${empty('alert', 'Couldn’t load this', errText(e))}</div>`; }
  }
  const reloadTab = () => route();

  async function wsOverview(ws, shop) {
    const r = await api('GET', `/v1/admin/reports/monthly?shopId=${shop.id}`);
    const k = r.kpis, p = r.prev, s0 = r.shops[0] || {};
    ws.innerHTML = `
      <div class="grid g4">
        ${kpiTile('Bills this month', usd(k.billsMinor), k.billsMinor, p.billsMinor, `${num(k.bills)} invoices`, 'receipt', 'hero')}
        ${kpiTile('Points given', num(k.pointsIssued), k.pointsIssued, p.pointsIssued, `≈ ${usd(k.pointsIssued)}`, 'coins')}
        ${kpiTile('Points redeemed', num(k.pointsRedeemed), k.pointsRedeemed, p.pointsRedeemed, `${num(k.redemptions)} redemptions`, 'gift')}
        ${kpiTile('Customers', num(k.activeCustomers), k.activeCustomers, p.activeCustomers, 'this month', 'users')}
      </div>
      <div class="card mt16"><div class="friends">
        <span class="fi">${ic('handshake')}</span>
        <div class="ft"><b>Mukafaah Friends</b><small>${shop.friendsEnabled ? `Accepts Mukafaah Points, up to ${num(shop.friendsMaxPoints)} per bill.` : 'Doesn’t accept Mukafaah Points yet.'}</small></div>
        ${isFull() ? `<div class="fc"><div class="inwrap"><input class="in" type="number" id="frMax" min="0" max="100000" value="${esc(shop.friendsMaxPoints || 300)}" aria-label="Max points per bill"><span class="suf">pts</span></div>${toggle('fr', shop.friendsEnabled, 'id="frOn" aria-label="Accept Mukafaah Points"')}</div>` : ''}
      </div></div>
      <div class="grid g21 mt16">
        <div class="card"><div class="card-h"><h3>Bills per day</h3><span class="sp"></span><span class="muted">${esc(monthName(r.month))}</span></div>${lineChart(r.daily, [['billsMinor', 'Bills', '#5B2BD6', (x) => x / 100]], { money: true })}</div>
        <div class="card"><div class="card-h"><h3>This month</h3></div>
          <div class="swrow"><div class="t"><b>Average bill</b><small>${delta(k.avgBillMinor, p.avgBillMinor)}</small></div><b class="num">${usd(k.avgBillMinor)}</b></div>
          <div class="swrow"><div class="t"><b>Store orders</b><small>${usd(k.ordersMinor)}</small></div><b class="num">${num(k.orders)}</b></div>
          <div class="swrow"><div class="t"><b>Offers used</b><small>${num(k.bookingsRequested)} booking requests</small></div><b class="num">${num(k.bookingsUsed + k.walkinOffersUsed)}</b></div>
          <div class="swrow"><div class="t"><b>Rating</b><small>From customers</small></div><b class="num">${s0.rating == null ? '—' : esc(s0.rating) + ' / 5'}</b></div>
        </div>
      </div>
      <div class="grid g2 mt16">
        <div class="card"><div class="card-h"><h3>Busiest hours</h3></div>${heatmap(r.heatmap)}</div>
        <div class="card flush"><div class="card-h"><h3>Who collected bills</h3></div>${r.cashiers.length ? `<div class="tw nomax"><table class="tbl"><thead><tr><th>Cashier</th><th class="r">Bills</th><th class="r">Amount</th></tr></thead><tbody>${r.cashiers.map((c) => `<tr><td>${esc(c.name)}</td><td class="r num">${num(c.bills)}</td><td class="r num">${usd(c.billsMinor)}</td></tr>`).join('')}</tbody></table></div>` : empty('receipt', 'No bills yet this month', '')}</div>
      </div>`;
    const on = $('#frOn', ws);
    if (on) {
      const save = async () => {
        const max = Math.max(0, Math.min(100000, Math.round(Number($('#frMax', ws).value) || 0)));
        try {
          await api('PATCH', `${base(shop)}/friends`, { enabled: on.checked, maxPoints: max });
          const row = S.shops.find((s) => s.id === shop.id); if (row) { row.friendsEnabled = on.checked; row.friendsMaxPoints = max; }
          toast(on.checked ? `${shop.name} accepts up to ${num(max)} Mukafaah Points per bill` : `${shop.name} left Mukafaah Friends`);
        } catch (e) { fail(e); on.checked = !on.checked; }
      };
      on.onchange = save;
      $('#frMax', ws).onchange = () => { if (on.checked) save(); };
    }
  }

  async function wsProfile(ws, shop) {
    const shopRole = isShop();
    ws.innerHTML = `<form class="card" id="pf" novalidate>
      <div class="fgrid">
        ${dropHtml('logo', shop.logoUrl, 'Logo', 'Square, at least 400 px')}
        ${dropHtml('cover', shop.coverUrl, 'Cover photo', 'Wide, about 3:1')}
      </div>
      <div class="fsec">Details</div>
      <div class="fgrid">
        <label class="f"><span>Shop name</span><input class="in" name="name" maxlength="80" value="${esc(shop.name)}"></label>
        <label class="f"><span>Category</span><select class="in" name="category" ${shopRole ? 'disabled' : ''}>${S.categories.length ? S.categories.map((c) => opt(c.key, c.nameEn, shop.category)).join('') : opt(shop.category, shop.category, shop.category)}</select></label>
        <label class="f"><span>City</span><input class="in" name="city" maxlength="60" value="${esc(shop.city || '')}"></label>
        <label class="f"><span>Area / street</span><input class="in" name="address" maxlength="160" value="${esc(shop.address || '')}"></label>
        <label class="f"><span>WhatsApp for orders</span><input class="in" name="whatsapp" value="${esc(shop.whatsapp || '')}" placeholder="+961 …"></label>
        <label class="f"><span>Instagram</span><input class="in" name="instagram" value="${esc(shop.instagram || '')}"></label>
      </div>
      <label class="f"><span>Location</span><input class="in" name="loc" value="${shop.lat != null ? esc(`${shop.lat}, ${shop.lng}`) : ''}" placeholder='Google Maps link or "lat, lng"'>${shop.lat != null ? `<em><a href="https://www.google.com/maps?q=${esc(shop.lat)},${esc(shop.lng)}" target="_blank" rel="noopener">${ic('link', 'xs')} Open on Google Maps</a></em>` : ''}</label>
      <label class="f"><span>About the shop</span><textarea class="in" name="description" maxlength="600">${esc(shop.description || '')}</textarea></label>
      <div class="optcard">
        <div class="swrow">${toggle('listed', shop.listed !== false)}<div class="t"><b>Visible in the customer app</b><small>Turn off to hide the shop without deleting anything.</small></div></div>
        <div class="swrow">${toggle('allowTransfer', !!shop.allowTransfer)}<div class="t"><b>Customers can send these points to friends</b></div></div>
      </div>
      <div class="fsec">Loyalty</div>
      <div class="fgrid">
        <label class="f"><span>Points back</span><span class="pct" style="width:100%"><input class="in" type="number" name="earnPercent" min="0" max="100" value="${esc(shop.earnPercent)}" style="width:100%"></span><em>The shop can change it in the Business app too. 100 points = $1.</em></label>
        ${shopRole ? '' : `<label class="f"><span>Private note</span><input class="in" name="adminNote" maxlength="500" value="${esc(shop.adminNote || '')}"><em>Only Mukafaah sees this.</em></label>`}
      </div>
      <div class="row end"><button class="btn">Save shop</button></div>
    </form>`;
    const f = $('#pf', ws);
    wireDrop(f, 'logo', 600, { path: `${base(shop)}/media`, purpose: 'logo' });
    wireDrop(f, 'cover', 1800, { path: `${base(shop)}/media`, purpose: 'cover' });
    f.onsubmit = async (e) => {
      e.preventDefault();
      const ll = parseLatLng(val(f, 'loc'));
      if (val(f, 'loc') && !ll) { toast('Couldn’t read that location.', true); return; }
      const btn = $('button.btn:not(.ghost)', f); btn.disabled = true;
      try {
        const prof = {
          name: val(f, 'name'), city: orNull(val(f, 'city')), address: orNull(val(f, 'address')),
          whatsapp: orNull(val(f, 'whatsapp')), instagram: orNull(val(f, 'instagram').replace(/^@/, '')), description: orNull(val(f, 'description')),
          lat: ll ? ll[0] : null, lng: ll ? ll[1] : null, listed: f.elements.listed.checked, allowTransfer: f.elements.allowTransfer.checked,
        };
        if (!shopRole) prof.category = val(f, 'category');
        await api('PATCH', `${base(shop)}/profile`, prof);
        const patch = { earnPercent: Math.round(Number(val(f, 'earnPercent')) || 0) };
        if (!shopRole) patch.adminNote = orNull(val(f, 'adminNote'));
        await api('PATCH', `/v1/admin/shops/${shop.id}`, patch);
        S.shops = [];
        toast('Shop saved. The app shows it now.');
        reloadTab();
      } catch (err) { fail(err); } finally { btn.disabled = false; }
    };
  }

  // ---------- Offers ----------
  const KIND = { DEAL: 'Deal', DISCOUNT: 'Discount', FREE_ITEM: 'Free item', SERVICE: 'Service' };
  async function wsOffers(ws, shop) {
    const list = await api('GET', `${base(shop)}/offers`);
    ws.innerHTML = `<div class="card flush"><div class="card-h"><h3>Offers &amp; discounts</h3><span class="sp"></span><button class="btn sm" id="add">${ic('plus', 'sm')} New offer</button></div>
      <div class="tw nomax"><table class="tbl"><thead><tr><th>Offer</th><th>Type</th><th>Cost</th><th>How</th><th>Valid</th><th>Activity</th><th>Status</th><th></th></tr></thead><tbody>
      ${list.map((o) => `<tr data-id="${esc(o.id)}"><td><div class="who"><span class="thumb">${o.imageUrl ? `<img src="${esc(o.imageUrl)}" alt="">` : ic('tag', 'sm')}</span><div class="t"><b>${esc(o.title)}</b><small>${esc(o.description || '')}</small></div></div></td>
        <td>${esc(KIND[o.kind] || o.kind)}${o.discountPercent ? ` −${esc(o.discountPercent)}%` : ''}</td><td class="num">${o.pointsCost ? num(o.pointsCost) + ' pts' : 'Free'}</td><td>${o.requiresBooking ? 'Book first' : 'Walk in'}</td>
        <td class="muted nw">${esc(o.validFrom || '')}${o.validTo ? ' → ' + esc(o.validTo) : ''}</td><td class="muted nw">${o.stats ? `${o.stats.requested} new · ${o.stats.redeemed} used` : ''}</td>
        <td>${o.hiddenByAdmin ? '<span class="pill bad">Hidden</span>' : pill(o.status)}</td><td><div class="acts"><button class="btn ghost sm" data-edit>${ic('edit', 'sm')} Edit</button></div></td></tr>`).join('') || `<tr><td colspan="8">${empty('tag', 'No offers yet', 'Offers show in the customer app straight away.')}</td></tr>`}
      </tbody></table></div></div>`;
    $('#add', ws).onclick = () => editOffer(shop, null);
    ws.querySelector('tbody').addEventListener('click', (e) => { if (e.target.closest('[data-edit]')) editOffer(shop, list.find((o) => o.id === e.target.closest('tr').dataset.id)); });
  }
  function editOffer(shop, o) {
    const f = modal(o ? 'Edit offer' : 'New offer', `
      ${dropHtml('imageId', o?.imageUrl, 'Photo')}
      <label class="f"><span>Title</span><input class="in" name="title" maxlength="90" value="${esc(o?.title)}" required></label>
      <label class="f"><span>Description</span><textarea class="in" name="description" maxlength="600">${esc(o?.description || '')}</textarea></label>
      <div class="fgrid">
        <label class="f"><span>Type</span><select class="in" name="kind">${Object.entries(KIND).map(([k, t]) => opt(k, t, o?.kind || 'DEAL')).join('')}</select></label>
        <label class="f"><span>Discount % (discounts only)</span><input class="in" type="number" name="discountPercent" min="1" max="100" value="${esc(o?.discountPercent ?? '')}"></label>
        <label class="f"><span>Points it costs</span><input class="in" type="number" name="pointsCost" min="0" value="${esc(o?.pointsCost ?? 0)}"><em>0 = free</em></label>
        <label class="f"><span>Customer saves ($)</span><input class="in" name="saving" inputmode="decimal" value="${o?.savingMinor ? (o.savingMinor / 100).toFixed(2) : ''}"></label>
        <label class="f"><span>Valid from</span><input class="in" type="date" name="validFrom" value="${esc(o?.validFrom || '')}"></label>
        <label class="f"><span>Valid until</span><input class="in" type="date" name="validTo" value="${esc(o?.validTo || '')}"><em>Optional</em></label>
        <label class="f"><span>Times per customer</span><input class="in" type="number" name="maxPerCustomer" min="1" max="100" value="${esc(o?.maxPerCustomer ?? 1)}"></label>
        <label class="f"><span>Total available</span><input class="in" type="number" name="totalLimit" min="1" value="${esc(o?.totalLimit ?? '')}"><em>Optional</em></label>
      </div>
      <label class="f"><span>Terms</span><textarea class="in" name="terms" maxlength="600">${esc(o?.terms || '')}</textarea></label>
      <div class="optcard"><div class="swrow">${toggle('requiresBooking', o ? o.requiresBooking : true)}<div class="t"><b>Customer books first</b><small>The shop accepts the request in the Business app.</small></div></div></div>
      ${o ? `<label class="f"><span>Status</span><select class="in" name="status">${opt('ACTIVE', 'Active', o.status)}${opt('PAUSED', 'Paused', o.status)}${opt('ARCHIVED', 'Delete (archive)', o.status)}</select></label>` : ''}`,
    async (form) => {
      const n = (x) => (val(form, x) === '' ? null : Math.round(Number(val(form, x))));
      const body = {
        title: val(form, 'title'), description: orNull(val(form, 'description')), terms: orNull(val(form, 'terms')), kind: val(form, 'kind'),
        discountPercent: val(form, 'kind') === 'DISCOUNT' ? n('discountPercent') : null, pointsCost: n('pointsCost') ?? 0,
        savingMinor: Math.round((Number(val(form, 'saving')) || 0) * 100), requiresBooking: form.elements.requiresBooking.checked,
        maxPerCustomer: n('maxPerCustomer') ?? 1, totalLimit: n('totalLimit'), validTo: orNull(val(form, 'validTo')),
        ...(val(form, 'validFrom') ? { validFrom: val(form, 'validFrom') } : {}),
      };
      if (!body.title) { toast('Give the offer a title.', true); return false; }
      const img = val(form, 'imageId'); if (img) body.imageId = img; else if (dropCleared(form, 'imageId')) body.imageId = null;
      if (o) { body.status = val(form, 'status'); await api('PATCH', `${base(shop)}/offers/${o.id}`, body); }
      else { for (const k of Object.keys(body)) if (body[k] === null) delete body[k]; await api('POST', `${base(shop)}/offers`, body); }
      toast('Offer saved. It’s live in the app.');
      reloadTab();
    }, { size: 'lg', drawer: true });
    wireDrop(f, 'imageId', 1400, { path: `${base(shop)}/media`, purpose: 'item' });
  }

  // ---------- Rewards ----------
  async function wsRewards(ws, shop) {
    const list = await api('GET', `${base(shop)}/rewards`);
    ws.innerHTML = `<div class="card flush"><div class="card-h"><h3>Rewards</h3><span class="sp"></span><button class="btn sm" id="add">${ic('plus', 'sm')} New reward</button></div>
      <div class="tw nomax"><table class="tbl"><thead><tr><th>Reward</th><th class="r">Points</th><th class="r">Worth</th><th class="r">Stock</th><th class="r">Redeemed</th><th>Status</th><th></th></tr></thead><tbody>
      ${list.map((w) => `<tr data-id="${esc(w.id)}"><td><div class="who"><span class="thumb">${w.imageUrl ? `<img src="${esc(w.imageUrl)}" alt="">` : ic('gift', 'sm')}</span><div class="t"><b>${esc(w.title)}</b><small>${esc(w.description || '')}</small></div></div></td>
        <td class="r num">${num(w.pointsCost)}</td><td class="r num">${usd(w.valueMinor)}</td><td class="r num">${w.stock == null ? '∞' : num(w.stock)}</td><td class="r num">${num(w.redeemed)}</td><td>${pill(w.status)}</td><td><div class="acts"><button class="btn ghost sm" data-edit>${ic('edit', 'sm')} Edit</button></div></td></tr>`).join('') || `<tr><td colspan="7">${empty('gift', 'No rewards yet', 'Rewards customers can get with their points.')}</td></tr>`}
      </tbody></table></div></div>`;
    $('#add', ws).onclick = () => editReward(shop, null);
    ws.querySelector('tbody').addEventListener('click', (e) => { if (e.target.closest('[data-edit]')) editReward(shop, list.find((w) => w.id === e.target.closest('tr').dataset.id)); });
  }
  function editReward(shop, w) {
    const f = modal(w ? 'Edit reward' : 'New reward', `
      ${dropHtml('imageId', w?.imageUrl, 'Photo')}
      <label class="f"><span>Title</span><input class="in" name="title" maxlength="90" value="${esc(w?.title)}" required></label>
      <label class="f"><span>Description</span><textarea class="in" name="description" maxlength="600">${esc(w?.description || '')}</textarea></label>
      <div class="fgrid">
        <label class="f"><span>Points it costs</span><input class="in" type="number" name="pointsCost" min="1" value="${esc(w?.pointsCost ?? '')}" required></label>
        <label class="f"><span>Worth ($)</span><input class="in" name="value" inputmode="decimal" value="${w?.valueMinor ? (w.valueMinor / 100).toFixed(2) : ''}"></label>
        <label class="f"><span>Stock</span><input class="in" type="number" name="stock" min="0" value="${esc(w?.stock ?? '')}"><em>Empty = unlimited</em></label>
        ${w ? `<label class="f"><span>Status</span><select class="in" name="status">${opt('ACTIVE', 'Active', w.status)}${opt('PAUSED', 'Paused', w.status)}${opt('ARCHIVED', 'Delete (archive)', w.status)}</select></label>` : ''}
      </div>`,
    async (form) => {
      const body = {
        title: val(form, 'title'), description: orNull(val(form, 'description')), pointsCost: Math.round(Number(val(form, 'pointsCost'))),
        valueMinor: Math.round((Number(val(form, 'value')) || 0) * 100), stock: val(form, 'stock') === '' ? null : Math.round(Number(val(form, 'stock'))),
      };
      if (!body.title || !(body.pointsCost > 0)) { toast('Add a title and the points it costs.', true); return false; }
      const img = val(form, 'imageId'); if (img) body.imageId = img; else if (dropCleared(form, 'imageId')) body.imageId = null;
      if (w) { body.status = val(form, 'status'); await api('PATCH', `${base(shop)}/rewards/${w.id}`, body); }
      else { for (const k of Object.keys(body)) if (body[k] === null) delete body[k]; await api('POST', `${base(shop)}/rewards`, body); }
      toast('Reward saved');
      reloadTab();
    }, { drawer: true });
    wireDrop(f, 'imageId', 1200, { path: `${base(shop)}/media`, purpose: 'item' });
  }

  // ---------- Online store ----------
  async function wsStore(ws, shop) {
    const st = await api('GET', `${base(shop)}/store`);
    ws.innerHTML = `
      <div class="card"><div class="swrow" style="padding:0">${toggle('enabled', st.enabled, 'id="storeOn" aria-label="Online store"')}<div class="t"><b>Online store ${st.enabled ? '<span class="pill ok">Open</span>' : '<span class="pill">Off</span>'}</b><small>Customers browse products with sizes and colours and send the order to the shop’s WhatsApp. No online payment.</small></div></div>
        ${st.enabled && !st.hasWhatsapp ? `<div class="alert warn mt16">${ic('alert', 'sm')}<div>Add a WhatsApp number in Profile so orders can be sent.</div></div>` : ''}</div>
      <div class="card"><div class="card-h"><h3>Categories</h3><span class="sp"></span><button class="btn ghost sm" id="addCat">${ic('plus', 'sm')} Category</button></div>
        <div class="chips">${st.categories.map((c) => `<button class="chip" data-cat="${esc(c.id)}">${esc(c.name)} <span class="n">${num(c.products)}</span></button>`).join('') || '<span class="muted">No categories yet.</span>'}</div></div>
      <div class="ph-row mt24" style="margin-bottom:16px"><div class="tt"><h1 style="font-size:17px">Products (${st.products.length})</h1></div><div class="acts"><button class="btn" id="addProd">${ic('plus', 'sm')} New product</button></div></div>
      ${st.products.length ? `<div class="pgrid">${st.products.map((p) => `<button class="pcard" data-id="${esc(p.id)}"><div class="pimg">${p.imageUrl ? `<img src="${esc(p.imageUrl)}" alt="">` : ic('image', 'lg')}${p.inStock === false ? '<em>Sold out</em>' : p.available === false ? '<em>Hidden</em>' : ''}</div>
        <div class="pb"><b>${esc(p.name)}</b><small>${p.hasVariants ? p.options.map((o) => `${o.values.length} ${esc(o.name.toLowerCase())}`).join(' · ') : (p.trackStock ? `${num(p.stock ?? 0)} in stock` : 'No options')}</small>
        <div class="pr">${p.maxPriceMinor > p.priceMinor ? `${usd(p.priceMinor)} – ${usd(p.maxPriceMinor)}` : usd(p.priceMinor)}${p.compareAtMinor ? `<s>${usd(p.compareAtMinor)}</s>` : ''}</div></div></button>`).join('')}</div>` : `<div class="card">${empty('bag', 'No products yet', 'Add the first product. Sizes and colours become variants with their own price and stock.')}</div>`}`;
    $('#storeOn', ws).onchange = async (e) => { try { await api('PUT', `${base(shop)}/store`, { enabled: e.target.checked }); toast(e.target.checked ? 'Store is open' : 'Store is off'); reloadTab(); } catch (err) { fail(err); e.target.checked = !e.target.checked; } };
    $('#addCat', ws).onclick = () => modal('New category', '<label class="f"><span>Name</span><input class="in" name="name" maxlength="40" placeholder="e.g. T-shirts"></label>', async (f) => { await api('POST', `${base(shop)}/store/categories`, { name: val(f, 'name') }); reloadTab(); }, { save: 'Add', size: 'sm' });
    $$('[data-cat]', ws).forEach((b) => (b.onclick = () => {
      const c = st.categories.find((x) => x.id === b.dataset.cat);
      const f = modal('Edit category', `<label class="f"><span>Name</span><input class="in" name="name" maxlength="40" value="${esc(c.name)}"></label><button type="button" class="btn danger sm" id="delCat">${ic('trash', 'sm')} Delete category</button>`, async (form) => { await api('PATCH', `${base(shop)}/store/categories/${c.id}`, { name: val(form, 'name') }); reloadTab(); }, { size: 'sm' });
      $('#delCat', f).onclick = async () => { try { await api('DELETE', `${base(shop)}/store/categories/${c.id}`); f.close(); reloadTab(); } catch (err) { fail(err); } };
    }));
    $('#addProd', ws).onclick = () => editProduct(shop, st, null);
    $$('.pcard', ws).forEach((el) => (el.onclick = async () => { try { editProduct(shop, st, await api('GET', `${base(shop)}/store/products/${el.dataset.id}`)); } catch (err) { fail(err); } }));
  }

  /** Product editor: photos, details, options (Size, Colour…) and one row per combination. */
  function editProduct(shop, st, p) {
    const images = (p?.imageIds || []).map((id, i) => ({ id, url: p.imageUrls[i] }));
    let options = (p?.options || []).map((o) => ({ name: o.name, values: [...o.values] }));
    let variants = (p?.variants || []).map((v) => ({ id: v.id, values: v.optionValues, price: v.priceMinor, stock: v.stock, active: v.active }));
    const f = modal(p ? 'Edit product' : 'New product', `
      <label class="f"><span>Photos</span><div class="thumbs" id="thumbs"></div><em>The first photo is the cover. Up to 8.</em></label>
      <label class="f"><span>Name</span><input class="in" name="name" maxlength="90" value="${esc(p?.name)}" required></label>
      <label class="f"><span>Description</span><textarea class="in" name="description" maxlength="2000">${esc(p?.description || '')}</textarea></label>
      <div class="fgrid">
        <label class="f"><span>Category</span><select class="in" name="categoryId">${opt('', 'No category', p?.categoryId || '')}${st.categories.map((c) => opt(c.id, c.name, p?.categoryId || '')).join('')}</select></label>
        <label class="f"><span>Price</span><div class="inwrap"><span class="pre">$</span><input class="in haspre" name="price" inputmode="decimal" value="${p ? (p.priceMinor / 100).toFixed(2) : ''}" required></div></label>
        <label class="f"><span>Was (optional)</span><div class="inwrap"><span class="pre">$</span><input class="in haspre" name="compare" inputmode="decimal" value="${p?.compareAtMinor ? (p.compareAtMinor / 100).toFixed(2) : ''}"></div></label>
        <label class="f" id="stockBox"><span>In stock</span><input class="in" type="number" name="stock" min="0" value="${esc(p?.stock ?? '')}"></label>
      </div>
      <div class="optcard">
        <div class="swrow">${toggle('trackStock', p?.trackStock)}<div class="t"><b>Track stock</b><small>Sold-out products and variants can’t be ordered.</small></div></div>
        <div class="swrow">${toggle('available', p ? p.available : true)}<div class="t"><b>Visible in the store</b></div></div>
        <div class="swrow">${toggle('featured', p?.featured)}<div class="t"><b>Featured</b><small>Shown first.</small></div></div>
      </div>
      <div class="fsec">Options</div><p class="muted" style="margin:-4px 0 12px">Add Size, Colour… Each combination becomes a variant with its own price and stock.</p>
      <div id="opts"></div><button type="button" class="btn sec sm" id="addOpt">${ic('plus', 'sm')} Add option</button>
      <div id="vars" class="mt16"></div>
      ${p ? `<div class="mt16"><button type="button" class="btn danger sm" id="delProd">${ic('trash', 'sm')} Delete product</button></div>` : ''}`,
    async (form) => {
      const price = Math.round(Number(val(form, 'price').replace(',', '.')) * 100);
      if (!val(form, 'name') || !Number.isFinite(price) || price < 0) { toast('Add a name and a price.', true); return false; }
      const compare = val(form, 'compare') ? Math.round(Number(val(form, 'compare')) * 100) : null;
      const track = form.elements.trackStock.checked;
      readVariantInputs();
      const opts = options.filter((o) => o.name.trim() && o.values.length);
      const body = {
        name: val(form, 'name'), description: orNull(val(form, 'description')), categoryId: orNull(val(form, 'categoryId')), priceMinor: price,
        compareAtMinor: compare && compare > price ? compare : null, imageIds: images.map((i) => i.id), trackStock: track,
        stock: track && !opts.length ? Math.round(Number(val(form, 'stock')) || 0) : null,
        options: opts.map((o) => ({ name: o.name.trim(), values: o.values })),
        variants: opts.length ? variants.map((v) => ({ ...(v.id ? { id: v.id } : {}), optionValues: v.values, priceMinor: v.price ?? price, stock: track ? v.stock ?? 0 : null, active: v.active })) : [],
        available: form.elements.available.checked, featured: form.elements.featured.checked,
      };
      if (p) await api('PATCH', `${base(shop)}/store/products/${p.id}`, body);
      else { for (const k of Object.keys(body)) if (body[k] === null) delete body[k]; await api('POST', `${base(shop)}/store/products`, body); }
      toast('Product saved');
      reloadTab();
    }, { save: 'Save product', size: 'lg', drawer: true });
    const thumbs = $('#thumbs', f);
    const drawThumbs = () => {
      thumbs.innerHTML = images.map((im, i) => `<div class="th"><img src="${esc(im.url)}" alt=""><button type="button" data-rm="${i}" aria-label="Remove photo">${ic('x', 'xs')}</button>${i === 0 ? '<em>Cover</em>' : ''}</div>`).join('') + (images.length < 8 ? `<button type="button" class="th add" id="addImg">${ic('plus')}<span>Photo</span></button>` : '');
      $$('[data-rm]', thumbs).forEach((b) => (b.onclick = () => { images.splice(Number(b.dataset.rm), 1); drawThumbs(); }));
      const add = $('#addImg', thumbs);
      if (add) add.onclick = () => {
        const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/png,image/jpeg,image/webp'; inp.multiple = true;
        inp.onchange = async () => {
          for (const file of [...inp.files].slice(0, 8 - images.length)) {
            try { const m = await uploadImage(file, 1600, { path: `${base(shop)}/media`, purpose: 'item' }); images.push({ id: m.id, url: m.url }); drawThumbs(); } catch (err) { fail(err); }
          }
        };
        inp.click();
      };
    };
    drawThumbs();
    const optsEl = $('#opts', f), varsEl = $('#vars', f);
    const readVariantInputs = () => {
      $$('tr[data-k]', varsEl).forEach((tr) => {
        const v = variants[Number(tr.dataset.k)]; if (!v) return;
        const pr = $('[data-p]', tr).value.trim(); v.price = pr === '' ? null : Math.round(Number(pr) * 100);
        const sk = $('[data-s]', tr); v.stock = sk && sk.value !== '' ? Math.round(Number(sk.value)) : null;
        v.active = $('[data-a]', tr).checked;
      });
    };
    const rebuild = () => {
      readVariantInputs();
      const opts = options.filter((o) => o.name.trim() && o.values.length);
      let combos = [[]];
      for (const o of opts) combos = combos.flatMap((c) => o.values.map((x) => [...c, x]));
      if (!opts.length) combos = [];
      const old = new Map(variants.map((v) => [v.values.join('\u0000').toLowerCase(), v]));
      variants = combos.slice(0, 100).map((c) => old.get(c.join('\u0000').toLowerCase()) || { values: c, price: null, stock: null, active: true });
      drawVariants();
    };
    const drawOpts = () => {
      optsEl.innerHTML = options.map((o, i) => `<div class="optbox" data-i="${i}">
        <div class="row nw"><input class="in sm" data-on value="${esc(o.name)}" placeholder="Option name, e.g. Size" maxlength="30" style="max-width:240px"><span class="spacer"></span><button type="button" class="btn ghost sm" data-rmopt>${ic('trash', 'sm')} Remove</button></div>
        <div class="chipsrow">${o.values.map((x, j) => `<span class="chip on">${esc(x)} <button type="button" data-rmv="${j}" aria-label="Remove ${esc(x)}">${ic('x', 'xs')}</button></span>`).join('')}
          <input class="in sm" data-nv placeholder="Add value + Enter" maxlength="30" style="width:170px"></div></div>`).join('');
      $('#addOpt', f).hidden = options.length >= 3;
      $$('.optbox', optsEl).forEach((box) => {
        const o = options[Number(box.dataset.i)];
        $('[data-on]', box).oninput = (e) => { o.name = e.target.value; };
        $('[data-on]', box).onchange = rebuild;
        $('[data-rmopt]', box).onclick = () => { options.splice(Number(box.dataset.i), 1); drawOpts(); rebuild(); };
        $$('[data-rmv]', box).forEach((b) => (b.onclick = () => { o.values.splice(Number(b.dataset.rmv), 1); drawOpts(); rebuild(); }));
        $('[data-nv]', box).onkeydown = (e) => {
          if (e.key !== 'Enter') return; e.preventDefault();
          const x = e.target.value.trim(); if (!x || o.values.some((y) => y.toLowerCase() === x.toLowerCase()) || o.values.length >= 20) return;
          o.values.push(x); drawOpts(); rebuild(); $(`.optbox[data-i="${options.indexOf(o)}"] [data-nv]`, optsEl)?.focus();
        };
      });
    };
    const drawVariants = () => {
      const track = f.elements.trackStock.checked;
      $('#stockBox', f).hidden = !track || variants.length > 0;
      varsEl.innerHTML = variants.length ? `<div class="fsec">Variants (${variants.length})</div><div class="card flush"><div class="tw nomax"><table class="tbl"><thead><tr><th>Combination</th><th>Price ($)</th>${track ? '<th>Stock</th>' : ''}<th>On</th></tr></thead><tbody>
        ${variants.map((v, k) => `<tr data-k="${k}"><td><b>${esc(v.values.join(' / '))}</b></td><td><input class="in sm" data-p inputmode="decimal" style="width:100px" value="${v.price == null ? '' : (v.price / 100).toFixed(2)}" placeholder="${esc(val(f, 'price') || '')}"></td>
          ${track ? `<td><input class="in sm" data-s type="number" min="0" style="width:80px" value="${v.stock ?? ''}"></td>` : ''}<td>${toggle('va' + k, v.active, 'data-a')}</td></tr>`).join('')}</tbody></table></div></div>` : '';
    };
    $('#addOpt', f).onclick = () => { options.push({ name: ['Size', 'Colour', 'Style'][options.length] || '', values: [] }); drawOpts(); };
    f.elements.trackStock.onchange = () => { readVariantInputs(); drawVariants(); };
    const del = $('#delProd', f);
    if (del) del.onclick = async () => { if (!(await confirmBox('Delete product?', 'It disappears from the store.'))) return; try { await api('PATCH', `${base(shop)}/store/products/${p.id}`, { archived: true }); f.close(); toast('Product deleted'); reloadTab(); } catch (err) { fail(err); } };
    drawOpts(); drawVariants();
  }

  // ---------- Orders & bookings ----------
  async function wsOrders(ws, shop) {
    const list = await api('GET', `${base(shop)}/orders`);
    const NEXT = { NEW: ['CONFIRMED', 'Confirm'], CONFIRMED: ['READY', 'Mark ready'], READY: ['COMPLETED', 'Complete'] };
    ws.innerHTML = `<div class="card flush"><div class="card-h"><h3>Store orders</h3><span class="sp"></span><span class="muted">Confirming takes the stock; the customer gets a notification.</span></div><div class="tw nomax"><table class="tbl"><thead><tr><th>Order</th><th>Customer</th><th>Items</th><th class="r">Total</th><th>How</th><th>Status</th><th></th></tr></thead><tbody>
      ${list.map((o) => `<tr data-id="${esc(o.id)}"><td><b>#${esc(o.code || '—')}</b><div class="muted">${esc(when(o.createdAt))}</div></td><td>${esc(o.customer)}</td>
        <td class="muted">${(o.items || []).map((it) => `${it.qty}× ${esc(it.name)}${it.variant ? ` (${esc(it.variant)})` : ''}`).join('<br>')}</td><td class="r num">${usd(o.totalMinor)}</td>
        <td class="muted">${o.fulfilment === 'DELIVERY' ? `Delivery<br>${esc(o.address || '')}` : 'Pickup'}</td><td>${pill(o.status)}</td>
        <td><div class="acts">${NEXT[o.status] ? `<button class="btn sm" data-st="${NEXT[o.status][0]}">${NEXT[o.status][1]}</button><button class="btn danger sm" data-st="CANCELLED">Cancel</button>` : ''}</div></td></tr>`).join('') || `<tr><td colspan="7">${empty('box', 'No orders yet', 'Orders from the customer app show up here and in the Business app.')}</td></tr>`}
      </tbody></table></div></div>`;
    ws.querySelector('tbody').addEventListener('click', async (e) => {
      const b = e.target.closest('[data-st]'); if (!b) return;
      b.disabled = true;
      try { await api('POST', `${base(shop)}/orders/${b.closest('tr').dataset.id}/status`, { status: b.dataset.st }); toast('Order updated. The customer was notified.'); reloadTab(); } catch (err) { fail(err); b.disabled = false; }
    });
  }
  async function wsBookings(ws, shop) {
    const [req, acc, hist] = await Promise.all(['REQUESTED', 'ACCEPTED', 'HISTORY'].map((st) => api('GET', `${base(shop)}/bookings?status=${st}`)));
    const rows = [...req, ...acc, ...hist];
    ws.innerHTML = `<div class="card flush"><div class="card-h"><h3>Bookings</h3><span class="sp"></span><span class="muted">The shop accepts requests in the Business app.</span></div><div class="tw nomax"><table class="tbl"><thead><tr><th>Code</th><th>Offer</th><th>Customer</th><th>When</th><th class="r">People</th><th>Status</th></tr></thead><tbody>
      ${rows.map((k) => `<tr><td><b class="mono">${esc(k.code)}</b></td><td>${esc(k.offerTitle || '')}</td><td>${esc(k.customerName || '•••• ' + (k.customerLast4 || ''))}</td><td class="muted">${esc(k.requestedFor ? when(k.requestedFor) : when(k.createdAt))}</td><td class="r">${esc(k.partySize ?? '')}</td><td>${pill(k.status)}</td></tr>`).join('') || `<tr><td colspan="6">${empty('calendar', 'No bookings yet', '')}</td></tr>`}
      </tbody></table></div></div>`;
  }

  // ---------- Cashiers ----------
  async function wsTeam(ws, shop) {
    const t = await api('GET', `${base(shop)}/staff`);
    ws.innerHTML = `
      <div class="card flush"><div class="card-h"><h3>Cashiers</h3><span class="sp"></span><button class="btn sec sm" id="pair">${ic('key', 'sm')} Pair a counter device</button><button class="btn sm" id="add">${ic('plus', 'sm')} Add cashier</button></div>
      <div class="tw nomax"><table class="tbl"><thead><tr><th>Cashier</th><th>Branch</th><th>Can redeem</th><th class="r">Max bill</th><th>Active</th><th></th></tr></thead><tbody>
      ${t.staff.map((x) => `<tr data-id="${esc(x.id)}"><td><div class="who"><span class="avatar lt">${esc(initials(x.name))}</span><div class="t"><b>${esc(x.name)}</b></div></div></td><td>${esc(x.branchName)}</td><td>${x.limits?.canRedeem ? '<span class="pill ok">Yes</span>' : '<span class="pill">No</span>'}</td><td class="r num">${usd(x.limits?.maxBillMinor)}</td><td>${toggle('a', x.active, 'data-active aria-label="Active"')}</td><td><div class="acts"><button class="btn ghost sm" data-pin>${ic('key', 'sm')} New PIN</button></div></td></tr>`).join('') || `<tr><td colspan="6">${empty('users', 'No cashiers yet', 'The owner can also collect and redeem from their own phone.')}</td></tr>`}
      </tbody></table></div></div>
      <div class="card flush"><div class="card-h"><h3>Counter devices</h3></div>${t.devices.length ? `<div class="tw nomax"><table class="tbl"><tbody>${t.devices.map((d) => `<tr data-id="${esc(d.id)}"><td><b>${esc(d.label)}</b><div class="muted">${esc(d.branch_name || d.branchName || '')}</div></td><td>${d.status === 'ACTIVE' ? '<span class="pill ok">Active</span>' : '<span class="pill">Revoked</span>'}</td><td class="muted">${d.last_seen_at || d.lastSeenAt ? 'Last seen ' + esc(day(d.last_seen_at || d.lastSeenAt)) : ''}</td><td><div class="acts">${d.status === 'ACTIVE' ? `<button class="btn danger sm" data-revoke>Revoke</button>` : ''}</div></td></tr>`).join('')}</tbody></table></div>` : `<div style="padding:0 20px 20px" class="muted">No devices yet.</div>`}</div>`;
    const branchSel = () => `<label class="f"><span>Branch</span><select class="in" name="branchId">${t.branches.map((b) => opt(b.id, b.name, t.branches[0]?.id)).join('')}</select></label>`;
    $('#add', ws).onclick = () => modal('Add cashier', `<label class="f"><span>Name</span><input class="in" name="name" maxlength="60" required></label>${branchSel()}<label class="f"><span>PIN</span><input class="in" name="pin" inputmode="numeric" maxlength="6" required><em>4 to 6 digits. The cashier uses it on the counter device.</em></label>`,
      async (f) => { await api('POST', `${base(shop)}/staff`, { name: val(f, 'name'), branchId: val(f, 'branchId'), pin: val(f, 'pin') }); toast('Cashier added'); reloadTab(); }, { save: 'Add', size: 'sm' });
    $('#pair', ws).onclick = () => modal('Pair a counter device', `${branchSel()}<p class="muted" style="margin:0">Enter the code in the Business app on the counter device (Counter device → Pair). It works for 10 minutes.</p>`,
      async (f) => { const r = await api('POST', `${base(shop)}/pairing-codes`, { branchId: val(f, 'branchId') }); modal('Pairing code', `<div class="code-big">${esc(r.code)}</div><p class="muted" style="text-align:center">Branch ${esc(r.branchName || '')} · valid 10 minutes</p>`, () => {}, { save: 'Done', size: 'sm' }); }, { save: 'Create code', size: 'sm' });
    ws.addEventListener('click', async (e) => {
      const tr = e.target.closest('tr'); if (!tr) return;
      if (e.target.closest('[data-pin]')) modal('New PIN', '<label class="f"><span>New PIN</span><input class="in" name="pin" inputmode="numeric" maxlength="6"><em>4 to 6 digits.</em></label>', async (f) => { await api('PATCH', `${base(shop)}/staff/${tr.dataset.id}`, { pin: val(f, 'pin') }); toast('PIN changed'); }, { size: 'sm' });
      if (e.target.closest('[data-revoke]') && (await confirmBox('Revoke device?', 'It will be signed out and can’t give points any more.', 'Revoke'))) { try { await api('POST', `${base(shop)}/devices/${tr.dataset.id}/revoke`); reloadTab(); } catch (err) { fail(err); } }
    });
    ws.addEventListener('change', async (e) => { if (!e.target.matches('[data-active]')) return; try { await api('PATCH', `${base(shop)}/staff/${e.target.closest('tr').dataset.id}`, { active: e.target.checked }); toast('Saved'); } catch (err) { fail(err); e.target.checked = !e.target.checked; } });
  }

  async function wsBills(ws, shop) {
    const list = await api('GET', `${base(shop)}/bills`);
    const T = { EARN: 'Points given', PREPOINT_EARN: 'Pre-Points', REDEEM: 'Redeemed' };
    ws.innerHTML = `<div class="card flush"><div class="card-h"><h3>Bills</h3><span class="sp"></span><button class="btn sec sm" id="csv">${ic('download', 'sm')} Export CSV</button></div><div class="tw"><table class="tbl"><thead><tr><th>When</th><th>Type</th><th>Invoice</th><th>Customer</th><th class="r">Bill</th><th class="r">Points</th><th>By</th></tr></thead><tbody>
      ${list.map((x) => `<tr class="${x.voided ? 'off' : ''}"><td class="muted nw">${esc(when(x.createdAt))}</td><td>${esc(T[x.type] || x.type)}${x.refType ? ` <span class="muted">(${esc(x.refType.toLowerCase())})</span>` : ''}${x.voided ? ' <span class="pill bad">Voided</span>' : ''}</td>
        <td class="mono">${esc(x.invoiceNo || '—')}</td><td>${esc(x.customer || '')}</td><td class="r num">${x.billMinor ? usd(x.billMinor) : ''}</td><td class="r num">${x.type === 'REDEEM' ? '−' : '+'}${num(x.points)}</td><td class="muted">${esc(x.staffName || '')}</td></tr>`).join('') || `<tr><td colspan="7">${empty('receipt', 'No bills yet', 'Every bill collected at the counter shows here.')}</td></tr>`}
      </tbody></table></div></div>`;
    $('#csv', ws).onclick = () => download(`bills-${shop.name.replace(/\W+/g, '-').toLowerCase()}.csv`, csv(list, [['When', (x) => x.createdAt], ['Type', (x) => x.type], ['Invoice', (x) => x.invoiceNo || ''], ['Customer', (x) => x.customer || ''], ['Bill $', (x) => (Number(x.billMinor || 0) / 100).toFixed(2)], ['Points', (x) => x.points], ['By', (x) => x.staffName || ''], ['Voided', (x) => (x.voided ? 'yes' : '')]]));
  }

  async function pageMyShops() {
    crumbs([['My shops']]);
    const shops = S.me.shops || [];
    mount(ph('My shops', 'Choose a shop to manage.') + (shops.length ? `<div class="mshops">${shops.map((s) => `<a class="mshop" href="#shop/${esc(s.id)}"><span class="thumb c">${esc(initials(s.name))}</span><span class="t"><b>${esc(s.name)}</b><small>Open workspace</small></span>${ic('chevr', 'sm')}</a>`).join('')}</div>` : `<div class="card noaccess">${empty('store', 'No shop linked yet', 'Ask Mukafaah to link your shop to this account.')}</div>`));
  }

  // =====================================================================
  // Monthly report
  // =====================================================================
  const monthName = (m) => new Date(m + '-01T12:00:00').toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  function delta(cur, prev) {
    if (!prev && !cur) return '<span class="dl">—</span>';
    if (!prev) return '<span class="dl up">new</span>';
    const d = Math.round(((cur - prev) * 100) / prev);
    return `<span class="dl ${d > 0 ? 'up' : d < 0 ? 'down' : ''}">${d > 0 ? '▲' : d < 0 ? '▼' : '•'} ${Math.abs(d)}%</span>`;
  }
  const kpiTile = (label, value, cur, prev, sub = '', icon = 'chart', cls = '') => `<div class="card kpi ${cls}"><div class="kh"><span class="ki">${ic(icon, 'sm')}</span>${esc(label)}</div><div class="kv">${value}</div><div class="kf">${delta(cur, prev)}<span>${esc(sub)}</span></div></div>`;

  /** SVG line/area chart, one or more series over the month's days. */
  function lineChart(rows, series, o = {}) {
    if (!rows.length) return empty('chart', 'No data yet', '');
    const W = 760, H = 220, L = 48, R = 12, T = 14, B = 26;
    const max = Math.max(1, ...series.flatMap(([k, , , fx]) => rows.map((r) => (fx ? fx(r[k]) : r[k]))));
    const nice = (() => { const p = Math.pow(10, Math.floor(Math.log10(max))); const m = max / p; return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p; })();
    const x = (i) => L + (i * (W - L - R)) / Math.max(1, rows.length - 1);
    const y = (v) => T + (H - T - B) * (1 - v / nice);
    const grid = [0, 0.25, 0.5, 0.75, 1].map((g) => `<line x1="${L}" x2="${W - R}" y1="${y(nice * g)}" y2="${y(nice * g)}" class="gl"/><text x="${L - 8}" y="${y(nice * g) + 4}" text-anchor="end" class="ax">${o.money ? '$' : ''}${num(Math.round(nice * g))}</text>`).join('');
    const xl = rows.map((r, i) => (i % 5 === 0 || i === rows.length - 1 ? `<text x="${x(i)}" y="${H - 6}" text-anchor="middle" class="ax">${Number(String(r.date).slice(8))}</text>` : '')).join('');
    const paths = series.map(([k, , color, fx], si) => {
      const pts = rows.map((r, i) => `${x(i).toFixed(1)},${y(fx ? fx(r[k]) : r[k]).toFixed(1)}`);
      const area = si === 0 ? `<path class="area" d="M${x(0)},${y(0)} L${pts.join(' L')} L${x(rows.length - 1)},${y(0)} Z" fill="${color}" opacity=".10"/>` : '';
      const last = rows.length - 1;
      return `${area}<polyline class="ln" points="${pts.join(' ')}" fill="none" stroke="${color}" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/><circle cx="${x(last)}" cy="${y(fx ? fx(rows[last][k]) : rows[last][k])}" r="4" fill="${color}"/>`;
    }).join('');
    const legend = series.length > 1 ? `<div class="legend" style="margin-bottom:8px">${series.map(([, label, color]) => `<span><i style="background:${color}"></i>${esc(label)}</span>`).join('')}</div>` : '';
    return `<div class="chartbox">${legend}<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(series.map((s) => s[1]).join(', '))} per day">${grid}${xl}${paths}</svg></div>`;
  }
  function barList(items, valueOf, labelOf, fmt) {
    const max = Math.max(1, ...items.map(valueOf));
    return items.length ? items.map((it) => `<div class="brow"><span class="bl">${esc(labelOf(it))}</span><div class="bar"><i style="width:${Math.round((valueOf(it) / max) * 100)}%"></i></div><span class="bv">${fmt(valueOf(it))}</span></div>`).join('') : empty('chart', 'Nothing this month', '');
  }
  function heatmap(h) {
    const max = Math.max(1, ...h.flat());
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return `<div class="heat">${h.map((row, d) => `<span>${days[d]}</span>${row.map((n, hr) => `<i title="${days[d]} ${hr}:00 · ${n} bills" style="opacity:${n ? 0.15 + (0.85 * n) / max : 0.06}"></i>`).join('')}`).join('')}
      <span></span>${Array.from({ length: 24 }, (_, i) => `<span class="hh">${i % 3 === 0 ? i : ''}</span>`).join('')}</div>`;
  }
  function csv(rows, cols) {
    const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    return [cols.map((c) => q(c[0])).join(','), ...rows.map((r) => cols.map((c) => q(c[1](r))).join(','))].join('\r\n');
  }
  function download(name, text) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' }));
    a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  async function pageReports() {
    crumbs([['Monthly report']]);
    loading('Monthly report');
    if (!S.shops.length) { try { await loadShops(); } catch { /* ignore */ } }
    if (!S.categories.length && !isShop()) { try { await loadCategories(); } catch { /* ignore */ } }
    const now = new Date();
    const cur = S.reportMonth || `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const shopId = isShop() ? (S.reportShop || S.me.shops?.[0]?.id || '') : (S.reportShop || '');
    const r = await api('GET', `/v1/admin/reports/monthly?month=${cur}${shopId ? '&shopId=' + shopId : ''}`);
    const k = r.kpis, p = r.prev;
    const months = Array.from({ length: 12 }, (_, i) => { const d = new Date(now.getFullYear(), now.getMonth() - i, 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`; });
    const shopChoices = isShop() ? (S.me.shops || []) : S.shops;
    let sortKey = 'billsMinor';
    const v = mount(ph('Monthly report', `${monthName(r.month)} compared with ${monthName(r.prevMonth)} · ${shopId ? esc(shopChoices.find((x) => x.id === shopId)?.name || 'one shop') : 'all shops'}`,
      `<select class="in" id="m" style="width:auto">${months.map((m) => opt(m, monthName(m), cur)).join('')}</select>
       ${isShop() && shopChoices.length < 2 ? '' : `<select class="in" id="sh" style="width:auto">${isShop() ? '' : opt('', 'All shops', shopId)}${shopChoices.map((x) => opt(x.id, x.name, shopId)).join('')}</select>`}
       <button class="btn sec" id="csv">${ic('download', 'sm')} Export CSV</button>`) + `
      <div class="sect first">Business app · counters</div>
      <div class="grid g4">
        ${kpiTile('Bills collected', usd(k.billsMinor), k.billsMinor, p.billsMinor, `${num(k.bills)} invoices`, 'receipt', 'hero')}
        ${kpiTile('Average bill', usd(k.avgBillMinor), k.avgBillMinor, p.avgBillMinor, '', 'wallet')}
        ${kpiTile('Points given', num(k.pointsIssued), k.pointsIssued, p.pointsIssued, `${num(k.prepointsIssued)} as Pre-Points`, 'coins')}
        ${kpiTile('Points redeemed', num(k.pointsRedeemed), k.pointsRedeemed, p.pointsRedeemed, `${k.pointsIssued ? Math.round((k.pointsRedeemed * 100) / k.pointsIssued) : 0}% of given`, 'gift')}
      </div>
      <div class="sect">Customer app</div>
      <div class="grid g4">
        ${kpiTile('New customers', num(k.newCustomers), k.newCustomers, p.newCustomers, `${num(r.totals.customers)} in total`, 'userplus')}
        ${kpiTile('Active customers', num(k.activeCustomers), k.activeCustomers, p.activeCustomers, 'earned or redeemed', 'users')}
        ${kpiTile('Store orders', num(k.orders), k.orders, p.orders, `${usd(k.ordersMinor)} · ${num(k.ordersCompleted)} completed`, 'bag')}
        ${kpiTile('Offers used', num(k.bookingsUsed + k.walkinOffersUsed), k.bookingsUsed + k.walkinOffersUsed, p.bookingsUsed + p.walkinOffersUsed, `${num(k.bookingsRequested)} booking requests`, 'tag')}
      </div>
      <div class="card mt16"><div class="card-h"><h3>Every day</h3><span class="sp"></span><span class="muted">Bills in $</span></div>${lineChart(r.daily, [['billsMinor', 'Bills ($)', '#5B2BD6', (x) => x / 100]], { money: true })}</div>
      <div class="grid g2 mt16">
        <div class="card"><div class="card-h"><h3>Points given vs redeemed</h3></div>${lineChart(r.daily, [['pointsIssued', 'Given', '#E0A800'], ['pointsRedeemed', 'Redeemed', '#0F7B57']])}</div>
        <div class="card"><div class="card-h"><h3>New customers &amp; orders</h3></div>${lineChart(r.daily, [['newCustomers', 'New customers', '#5B2BD6'], ['orders', 'Orders', '#C0362C']])}</div>
        <div class="card"><div class="card-h"><h3>Bills by category</h3></div>${barList(r.categories, (c) => c.billsMinor, (c) => c.name, usd)}</div>
        <div class="card"><div class="card-h"><h3>Busiest hours</h3></div>${heatmap(r.heatmap)}</div>
        <div class="card"><div class="card-h"><h3>Customer tiers</h3></div>${barList(Object.entries(r.tiers || {}), (x) => x[1], (x) => x[0].charAt(0) + x[0].slice(1).toLowerCase(), num)}</div>
        <div class="card flush"><div class="card-h"><h3>Top cashiers</h3></div>${r.cashiers.length ? `<div class="tw nomax"><table class="tbl"><thead><tr><th>Cashier</th><th>Shop</th><th class="r">Bills</th><th class="r">Amount</th></tr></thead><tbody>${r.cashiers.map((c) => `<tr><td>${esc(c.name)}</td><td class="muted">${esc(c.shop)}</td><td class="r num">${num(c.bills)}</td><td class="r num">${usd(c.billsMinor)}</td></tr>`).join('')}</tbody></table></div>` : empty('users', 'No bills this month', '')}</div>
      </div>
      <div class="card flush mt16"><div class="card-h"><h3>Shops</h3></div><div class="tw"><table class="tbl" id="st"></table></div></div>`);
    const COLS = [
      ['Shop', (s) => s.name, null], ['Points back', (s) => s.earnPercent + '%', 'earnPercent'], ['Bills', (s) => num(s.bills), 'bills'], ['Amount', (s) => usd(s.billsMinor), 'billsMinor'],
      ['Customers', (s) => num(s.customers), 'customers'], ['Given', (s) => num(s.pointsIssued), 'pointsIssued'], ['Redeemed', (s) => num(s.pointsRedeemed), 'pointsRedeemed'],
      ['Redeem rate', (s) => s.redeemRate + '%', 'redeemRate'], ['Offers', (s) => num(s.offersUsed), 'offersUsed'], ['Rewards', (s) => num(s.rewardsRedeemed), 'rewardsRedeemed'],
      ['Orders', (s) => `${num(s.orders)} · ${usd(s.ordersMinor)}`, 'ordersMinor'], ['Rating', (s) => (s.rating == null ? '—' : s.rating), 'rating'],
    ];
    const drawTable = () => {
      const rows = [...r.shops].sort((a, b) => (b[sortKey] ?? -1) - (a[sortKey] ?? -1));
      $('#st', v).innerHTML = `<thead><tr>${COLS.map(([t, , key], i) => `<th class="${i ? 'r' : ''}">${key ? `<button class="sortb ${key === sortKey ? 'on' : ''}" data-sort="${key}">${esc(t)}${key === sortKey ? ' ↓' : ''}</button>` : esc(t)}</th>`).join('')}</tr></thead>
        <tbody>${rows.map((s) => `<tr><td><a href="#shop/${esc(s.id)}"><b>${esc(s.name)}</b></a><div class="muted">${esc(catName(s.category))}</div></td>${COLS.slice(1).map(([, f]) => `<td class="r num">${f(s)}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${COLS.length}">${empty('store', 'No shop activity this month', '')}</td></tr>`}</tbody>`;
    };
    drawTable();
    $('#st', v).addEventListener('click', (e) => { const b = e.target.closest('[data-sort]'); if (b) { sortKey = b.dataset.sort; drawTable(); } });
    $('#m', v).onchange = (e) => { S.reportMonth = e.target.value; pageReports(); };
    const sh = $('#sh', v); if (sh) sh.onchange = (e) => { S.reportShop = e.target.value; pageReports(); };
    $('#csv', v).onclick = () => {
      const text = csv(r.shops, [
        ['Shop', (s) => s.name], ['Category', (s) => s.category], ['Points back %', (s) => s.earnPercent], ['Bills', (s) => s.bills], ['Bills $', (s) => (s.billsMinor / 100).toFixed(2)],
        ['Customers', (s) => s.customers], ['Points given', (s) => s.pointsIssued], ['Points redeemed', (s) => s.pointsRedeemed], ['Redeem rate %', (s) => s.redeemRate],
        ['Offers used', (s) => s.offersUsed], ['Rewards redeemed', (s) => s.rewardsRedeemed], ['Orders', (s) => s.orders], ['Orders $', (s) => (s.ordersMinor / 100).toFixed(2)], ['Rating', (s) => s.rating ?? ''],
      ]) + '\r\n\r\n' + csv(r.daily, [['Date', (d) => d.date], ['Bills', (d) => d.bills], ['Bills $', (d) => (d.billsMinor / 100).toFixed(2)], ['Points given', (d) => d.pointsIssued], ['Points redeemed', (d) => d.pointsRedeemed], ['New customers', (d) => d.newCustomers], ['Orders', (d) => d.orders]]);
      download(`mukafaah-report-${r.month}${shopId ? '-shop' : ''}.csv`, text);
    };
  }

  // =====================================================================
  // Customer app content: phone preview, home sections, banners, categories
  // =====================================================================
  const bannerBox = (b, cls = '') => {
    const st = b.imageUrl ? 'IMAGE' : (b.style || 'PURPLE');
    const bg = b.imageUrl ? ` style="background-image:url('${esc(b.imageUrl)}')"` : '';
    return `<div class="bn ${esc(st)} ${cls}"${bg}>${b.titleEn ? `<b>${esc(b.titleEn)}</b>` : ''}${b.subtitleEn ? `<small>${esc(b.subtitleEn)}</small>` : ''}</div>`;
  };
  const liveBanners = (banners) => { const now = Date.now(); return banners.filter((b) => b.active && (!b.startsAt || new Date(b.startsAt).getTime() <= now) && (!b.endsAt || new Date(b.endsAt).getTime() >= now)); };
  function phonePreview(o) {
    const live = liveBanners(o.banners || []);
    const L = o.layout || 'UNO';
    const n = L === 'UNO' ? 1 : L === 'DUO' ? 2 : 3;
    const ban = live.length ? `<div class="pv-ban ${L}">${live.slice(0, n).map((b) => bannerBox(b)).join('')}</div>${L === 'UNO' && live.length > 1 ? `<div class="pv-dots">${live.slice(0, 6).map((_, i) => `<i class="${i ? '' : 'on'}"></i>`).join('')}</div>` : ''}` : '';
    const cats = S.categories.filter((c) => c.active);
    const secs = (o.sections || []).filter((s) => s.active);
    return `<div class="phone"><div class="scr"><div class="sb"><span>9:41</span><span class="notch"></span><span class="bat"></span></div>
      <div class="pv-hero"><div class="pv-hi"><span class="av">L</span><span><small>Good evening</small><b>Lara</b></span></div><small>Your points</small><b class="n">2,450</b><span class="tm">Gold member · 7 shops</span></div>
      <div class="pv-acts"><i><b>View Points</b></i><i class="y"><b>Offers &amp; Rewards</b></i></div>
      <div class="inner">${ban}
        ${(secs.length ? secs : [{ type: 'CATEGORIES', titleEn: 'Categories' }]).map((s) => {
          const title = `<div class="pv-sec">${esc(s.titleEn || SECTION_NAME[s.type] || s.type)}</div>`;
          if (s.type === 'CATEGORIES') return title + `<div class="pv-row">${cats.slice(0, 5).map((c) => `<div class="pv-cat"><div class="e" style="${c.color ? `background:${esc(c.color)}1f;color:${esc(c.color)}` : ''}">${c.iconUrl ? `<img src="${esc(c.iconUrl)}" alt="">` : esc(initials(c.nameEn))}</div>${esc(c.nameEn.split(' ')[0])}</div>`).join('')}</div>`;
          if (s.type === 'RECENT_ACTIVITY') return title + '<div class="pv-card wide"></div><div class="pv-card wide"></div>';
          if (s.layout === 'GRID') return title + '<div class="pv-grid"><div class="pv-card"></div><div class="pv-card"></div><div class="pv-card"></div><div class="pv-card"></div></div>';
          if (s.layout === 'CAROUSEL') return title + '<div class="pv-row"><div class="pv-card big"></div><div class="pv-card big"></div></div>';
          return title + '<div class="pv-row"><div class="pv-card"></div><div class="pv-card"></div><div class="pv-card"></div></div>';
        }).join('')}
      </div></div></div>${live.length ? '' : '<div class="pv-note">No live banners: the app hides the banner area.</div>'}`;
  }

  const SECTION_TYPES = [
    ['CATEGORIES', 'Categories row'], ['FEATURED_SHOPS', 'Featured shops'], ['NEW_OFFERS', 'New offers'], ['DISCOVER_SHOPS', 'More shops to discover'],
    ['REWARDS', 'Rewards for you'], ['CATEGORY_SHOPS', 'Shops from one category'], ['PICKED_SHOPS', 'Hand-picked shops'], ['RECENT_ACTIVITY', 'Customer’s recent transactions'],
  ];
  // Sections that can fill themselves or show only what the admin picks, and what they hold.
  const PICKABLE = { FEATURED_SHOPS: 'shops', DISCOVER_SHOPS: 'shops', PICKED_SHOPS: 'shops', NEW_OFFERS: 'offers', REWARDS: 'rewards' };
  const AUTO_TEXT = {
    FEATURED_SHOPS: 'Automatic: shops marked “Featured” in Shops',
    DISCOVER_SHOPS: 'Automatic: all other shops, nearest to the customer first',
    NEW_OFFERS: 'Automatic: the newest live offers',
    REWARDS: 'Automatic: rewards the customer can afford first',
  };
  const SHOP_LAYOUTS = [['CAROUSEL', 'Carousel', 'Big cards that slide'], ['GRID', 'Grid', 'Two per row, many shops'], ['ROW', 'Row', 'Small cards in one row']];
  const hasLayout = (t) => ['FEATURED_SHOPS', 'DISCOVER_SHOPS', 'CATEGORY_SHOPS', 'PICKED_SHOPS'].includes(t);
  const sectionSub = (s) => {
    const bits = [SECTION_NAME[s.type] || s.type];
    if (s.type === 'CATEGORY_SHOPS') bits.push(catName(s.categoryKey));
    const kind = PICKABLE[s.type];
    if (kind && (s.pickMode === 'PICKED' || s.type === 'PICKED_SHOPS')) {
      const n = (kind === 'shops' ? s.shopIds : kind === 'offers' ? s.offerIds : s.rewardIds).length;
      bits.push(`${n} picked`);
    } else if (kind) bits.push('automatic');
    if (hasLayout(s.type) && s.layout) bits.push(SHOP_LAYOUTS.find((l) => l[0] === s.layout)?.[1] || s.layout);
    bits.push(`up to ${s.maxItems}`);
    return bits.join(' · ');
  };
  const SECTION_NAME = Object.fromEntries(SECTION_TYPES);
  const SECTION_ICON = { CATEGORIES: 'grid', FEATURED_SHOPS: 'star', DISCOVER_SHOPS: 'store', NEW_OFFERS: 'tag', CATEGORY_SHOPS: 'store', PICKED_SHOPS: 'pin', REWARDS: 'gift', RECENT_ACTIVITY: 'receipt' };
  async function pageHome() {
    crumbs([['Customer app'], ['Home screen']]);
    loading('Home screen');
    const [sections, banners, settings] = await Promise.all([api('GET', '/v1/admin/sections'), api('GET', '/v1/admin/banners'), api('GET', '/v1/admin/settings'), loadCategories(), loadShops()]);
    const layout = settings['home.bannerLayout'] || 'UNO';
    const v = mount(ph('Home screen', 'What customers see when they open the app, top to bottom. Changes are live straight away.', `<button class="btn" id="add">${ic('plus', 'sm')} Add section</button>`) + `
      <div class="ban-wrap">
        <div class="list" id="list">${sections.map((s) => `
          <div class="item ${s.active ? '' : 'off'}" data-id="${esc(s.id)}">
            <span class="handle" title="Drag to reorder">${ic('drag', 'sm')}</span>
            <span class="ico">${s.type === 'CATEGORY_SHOPS' ? catTile(S.categories.find((c) => c.key === s.categoryKey)) : ic(SECTION_ICON[s.type] || 'grid', 'sm')}</span>
            <div class="body"><b>${esc(s.titleEn || SECTION_NAME[s.type])}</b><small>${esc(sectionSub(s))}</small></div>
            <div class="ctl">${toggle('active', s.active, 'data-active aria-label="Show in app"')}
              <button class="btn ghost icon sm" data-up aria-label="Move up">${ic('up', 'sm')}</button><button class="btn ghost icon sm" data-down aria-label="Move down">${ic('down', 'sm')}</button>
              <button class="btn ghost icon sm" data-edit aria-label="Edit">${ic('edit', 'sm')}</button><button class="btn ghost icon sm" data-del aria-label="Remove">${ic('trash', 'sm')}</button></div>
          </div>`).join('') || `<div class="card">${empty('phone', 'No sections', 'Add a section to build the home screen.')}</div>`}</div>
        <div class="sticky-col" id="pv"></div>
      </div>`);
    const drawPreview = () => {
      const order = $$('.item', $('#list', v)).map((x) => sections.find((s) => s.id === x.dataset.id)).filter(Boolean);
      $('#pv', v).innerHTML = phonePreview({ banners, layout, sections: order });
    };
    const list = $('#list', v);
    sortable(list, 'sections', drawPreview);
    list.addEventListener('click', async (e) => {
      const it = e.target.closest('.item'); if (!it) return;
      const s = sections.find((x) => x.id === it.dataset.id);
      if (e.target.closest('[data-up]')) moveItem(list, s.id, -1, 'sections', drawPreview);
      if (e.target.closest('[data-down]')) moveItem(list, s.id, 1, 'sections', drawPreview);
      if (e.target.closest('[data-edit]')) editSection(s);
      if (e.target.closest('[data-del]') && (await confirmBox('Remove section?', `“${s.titleEn || SECTION_NAME[s.type]}” will be removed from the home screen.`, 'Remove'))) {
        try { await api('DELETE', '/v1/admin/sections/' + s.id); toast('Section removed'); pageHome(); } catch (err) { fail(err); }
      }
    });
    list.addEventListener('change', async (e) => {
      if (!e.target.matches('[data-active]')) return;
      const it = e.target.closest('.item');
      const s = sections.find((x) => x.id === it.dataset.id);
      try { await api('PATCH', '/v1/admin/sections/' + s.id, { active: e.target.checked }); s.active = e.target.checked; it.classList.toggle('off', !s.active); drawPreview(); } catch (err) { fail(err); e.target.checked = !e.target.checked; }
    });
    $('#add', v).onclick = () => editSection(null);
    drawPreview();
  }
  async function editSection(s) {
    const type0 = s?.type || 'FEATURED_SHOPS';
    const picks = { shops: [...(s?.shopIds || [])], offers: [...(s?.offerIds || [])], rewards: [...(s?.rewardIds || [])] };
    let offers = null, rewards = null;
    const f = modal(s ? 'Edit section' : 'New home section', `
      <label class="f"><span>Type</span><select class="in" name="type">${SECTION_TYPES.map(([k, t]) => opt(k, t, type0)).join('')}</select></label>
      <div id="catbox"><label class="f"><span>Category</span><select class="in" name="categoryKey">${S.categories.map((c) => opt(c.key, c.nameEn, s?.categoryKey)).join('')}</select></label></div>
      <div id="modebox"><span class="flabel">What to show</span>
        <div class="seg2"><label><input type="radio" name="pickMode" value="AUTO" ${s?.pickMode !== 'PICKED' ? 'checked' : ''}><span id="autoText">Automatic</span></label>
        <label><input type="radio" name="pickMode" value="PICKED" ${s?.pickMode === 'PICKED' ? 'checked' : ''}><span>Only the ones I pick</span></label></div></div>
      <div id="pickbox"><label class="f"><span id="pickLabel">Pick</span><div class="picker"><div class="ps"><div class="inwrap">${ic('search', 'sm')}<input class="in sm" id="pq" placeholder="Search"></div></div><div class="pl" id="plist"></div><div class="pf" id="pcount"></div></div></label></div>
      <div id="layoutbox"><span class="flabel">How it looks</span><div class="layouts">${SHOP_LAYOUTS.map(([k, t, d]) => `<label class="lay"><input type="radio" name="layout" value="${k}" ${(s?.layout || (type0 === 'DISCOVER_SHOPS' ? 'GRID' : type0 === 'FEATURED_SHOPS' ? 'CAROUSEL' : 'ROW')) === k ? 'checked' : ''}><b>${t}</b><small>${d}</small></label>`).join('')}</div></div>
      <div class="fgrid">
        <label class="f"><span>Title (English)</span><input class="in" name="titleEn" maxlength="60" value="${esc(s?.titleEn)}"></label>
        <label class="f"><span>Title (Arabic)</span><input class="in ar" name="titleAr" maxlength="60" value="${esc(s?.titleAr)}"></label>
      </div>
      <label class="f"><span>Most items to show</span><input class="in" type="number" name="maxItems" min="1" max="50" value="${esc(s?.maxItems ?? 12)}"></label>`,
    async (form) => {
      const type = val(form, 'type');
      const kind = PICKABLE[type];
      const mode = type === 'PICKED_SHOPS' ? 'PICKED' : kind ? form.querySelector('[name="pickMode"]:checked')?.value || 'AUTO' : 'AUTO';
      const body = {
        type, titleEn: orNull(val(form, 'titleEn')), titleAr: orNull(val(form, 'titleAr')),
        maxItems: Math.max(1, Math.min(50, Math.round(Number(val(form, 'maxItems')) || 12))),
        pickMode: mode,
        layout: hasLayout(type) ? form.querySelector('[name="layout"]:checked')?.value || null : null,
        categoryKey: type === 'CATEGORY_SHOPS' ? val(form, 'categoryKey') : null,
        shopIds: kind === 'shops' && mode === 'PICKED' ? picks.shops : [],
        offerIds: kind === 'offers' && mode === 'PICKED' ? picks.offers : [],
        rewardIds: kind === 'rewards' && mode === 'PICKED' ? picks.rewards : [],
      };
      if (mode === 'PICKED' && kind && !body[kind === 'shops' ? 'shopIds' : kind === 'offers' ? 'offerIds' : 'rewardIds'].length) { toast(`Pick at least one ${kind.slice(0, -1)}.`, true); return false; }
      if (type === 'CATEGORY_SHOPS' && !body.titleEn) { body.titleEn = catName(body.categoryKey); body.titleAr = body.titleAr || S.categories.find((c) => c.key === body.categoryKey)?.nameAr || null; }
      if (s) await api('PATCH', '/v1/admin/sections/' + s.id, body); else await api('POST', '/v1/admin/sections', body);
      toast('Home screen updated');
      pageHome();
    });
    const kindNow = () => PICKABLE[val(f, 'type')];
    const items = async (kind) => {
      if (kind === 'shops') return S.shops.map((x) => ({ id: x.id, name: x.name, sub: x.city || '' }));
      if (kind === 'offers') { offers ??= await api('GET', '/v1/admin/offers'); return offers.filter((o) => o.status === 'ACTIVE' && !o.hidden).map((o) => ({ id: o.id, name: o.title, sub: o.businessName })); }
      rewards ??= await api('GET', '/v1/admin/rewards'); return rewards.filter((r) => r.status === 'ACTIVE').map((r) => ({ id: r.id, name: r.title, sub: `${r.businessName} · ${r.pointsCost.toLocaleString()} pts` }));
    };
    const drawPicks = async () => {
      const kind = kindNow(); if (!kind) return;
      const list = await items(kind).catch(() => []);
      const chosen = picks[kind];
      const q = ($('#pq', f).value || '').toLowerCase();
      const shown = [...chosen.map((id) => list.find((x) => x.id === id)).filter(Boolean), ...list.filter((x) => !chosen.includes(x.id) && (!q || (x.name + ' ' + x.sub).toLowerCase().includes(q)))].slice(0, 120);
      $('#plist', f).innerHTML = shown.map((x) => `<label><input type="checkbox" data-pick="${esc(x.id)}" ${chosen.includes(x.id) ? 'checked' : ''}><span>${esc(x.name)}</span><span class="spacer"></span><small class="muted">${esc(x.sub)}</small></label>`).join('') || `<div class="empty-s muted" style="padding:12px">Nothing to pick yet.</div>`;
      $('#pcount', f).textContent = `${chosen.length} picked · shown in the order you pick them`;
    };
    let layoutTouched = !!s?.layout;
    f.querySelectorAll('[name="layout"]').forEach((r) => r.addEventListener('change', () => (layoutTouched = true)));
    const sync = () => {
      const t = val(f, 'type'); const kind = PICKABLE[t];
      if (!layoutTouched) {
        const def = t === 'DISCOVER_SHOPS' ? 'GRID' : t === 'FEATURED_SHOPS' ? 'CAROUSEL' : 'ROW';
        const r = f.querySelector(`[name="layout"][value="${def}"]`); if (r) r.checked = true;
      }
      const mode = t === 'PICKED_SHOPS' ? 'PICKED' : f.querySelector('[name="pickMode"]:checked')?.value;
      $('#catbox', f).hidden = t !== 'CATEGORY_SHOPS';
      $('#modebox', f).hidden = !kind || t === 'PICKED_SHOPS';
      $('#autoText', f).textContent = AUTO_TEXT[t] || 'Automatic';
      $('#pickbox', f).hidden = !kind || mode !== 'PICKED';
      $('#pickLabel', f).textContent = kind === 'offers' ? 'Offers to show' : kind === 'rewards' ? 'Rewards to show' : 'Shops to show';
      $('#layoutbox', f).hidden = !hasLayout(t);
      drawPicks();
    };
    $('#plist', f).addEventListener('change', (e) => {
      const c = e.target.closest('[data-pick]'); if (!c) return;
      const arr = picks[kindNow()]; const id = c.dataset.pick;
      if (c.checked) { if (!arr.includes(id)) arr.push(id); } else arr.splice(arr.indexOf(id), 1);
      $('#pcount', f).textContent = `${arr.length} picked · shown in the order you pick them`;
    });
    $('#pq', f).oninput = drawPicks;
    f.elements.type.onchange = sync;
    f.querySelectorAll('[name="pickMode"]').forEach((r) => (r.onchange = sync));
    sync();
  }

  // ---------- Banners ----------
  const ACTIONS = [['NONE', 'Nothing (just a picture)'], ['OFFERS', 'Open all offers'], ['SHOP', 'Open a shop'], ['CATEGORY', 'Open a category'], ['URL', 'Open a web link']];
  const LAYOUTS = [['UNO', 'Uno', 'One wide banner, slides'], ['DUO', 'Duo', 'Two side by side'], ['TRIO', 'Trio', 'One tall and two small']];
  const bannerLive = (b) => {
    const now = Date.now();
    if (!b.active) return '<span class="pill">Off</span>';
    if (b.startsAt && new Date(b.startsAt).getTime() > now) return `<span class="pill pur">Starts ${esc(day(b.startsAt))}</span>`;
    if (b.endsAt && new Date(b.endsAt).getTime() < now) return '<span class="pill bad">Ended</span>';
    return `<span class="pill ok">Live${b.endsAt ? ' until ' + esc(day(b.endsAt)) : ''}</span>`;
  };
  const actionLabel = (b) => (b.actionType === 'SHOP' ? S.shops.find((s) => s.id === b.actionValue)?.name || 'shop' : b.actionType === 'CATEGORY' ? catName(b.actionValue) : b.actionValue);
  async function pageBanners() {
    crumbs([['Customer app'], ['Banners']]);
    loading('Banners');
    const [banners, settings, sections] = await Promise.all([api('GET', '/v1/admin/banners'), api('GET', '/v1/admin/settings'), api('GET', '/v1/admin/sections'), loadCategories(), loadShops()]);
    let layout = settings['home.bannerLayout'] || 'UNO';
    const v = mount(ph('Banners', 'Pick a layout, then add banners. The customer home updates straight away. With no banners, the app hides the banner area.', `<button class="btn" id="add">${ic('plus', 'sm')} New banner</button>`) + `
      <div class="ban-wrap">
        <div class="stack">
          <div class="card"><div class="card-h"><h3>Layout</h3><div class="sub">How banners sit at the top of the home screen.</div></div>
            <div class="layouts" id="lays">${LAYOUTS.map(([k, t, d]) => `<button class="lay ${k === layout ? 'on' : ''}" data-l="${k}" type="button"><span class="ck">${ic('check', 'xs')}</span><div class="lp ${k}">${k === 'UNO' ? '<i></i>' : k === 'DUO' ? '<i></i><i class="y"></i>' : '<i></i><i class="y"></i><i class="l"></i>'}</div><div class="lt"><div><b>${t}</b><small>${d}</small></div></div></button>`).join('')}</div></div>
          <div class="card flush"><div class="card-h"><h3>Banners (${banners.length})</h3><div class="sub">Drag to reorder. ${layout === 'UNO' ? 'Uno slides through all live banners.' : `${layout === 'DUO' ? 'Duo shows the first 2' : 'Trio shows the first 3'} live banners.`}</div></div>
            <div class="list" id="list" style="padding:0 16px 16px">${banners.length ? banners.map((b) => `
              <div class="item ${b.active ? '' : 'off'}" data-id="${esc(b.id)}">
                <span class="handle" title="Drag to reorder">${ic('drag', 'sm')}</span>
                ${bannerBox(b, 'thumbn')}
                <div class="body"><b>${esc(b.titleEn || '(no title)')}</b><small>${esc(ACTIONS.find((a) => a[0] === b.actionType)?.[1] || '')}${b.actionValue ? ' · ' + esc(actionLabel(b)) : ''}</small>${bannerLive(b)}</div>
                <div class="ctl">${toggle('active', b.active, 'data-active aria-label="Show in app"')}
                  <button class="btn ghost icon sm" data-up aria-label="Move up">${ic('up', 'sm')}</button><button class="btn ghost icon sm" data-down aria-label="Move down">${ic('down', 'sm')}</button>
                  <button class="btn ghost icon sm" data-edit aria-label="Edit">${ic('edit', 'sm')}</button><button class="btn ghost icon sm" data-del aria-label="Delete">${ic('trash', 'sm')}</button></div>
              </div>`).join('') : empty('image', 'No banners yet', 'Add one and it shows in the app right away.', `<button class="btn" data-addb>${ic('plus', 'sm')} New banner</button>`)}</div></div>
        </div>
        <div class="sticky-col" id="pv"></div>
      </div>`);
    const drawPreview = () => {
      const order = $$('.item', $('#list', v)).map((x) => banners.find((b) => b.id === x.dataset.id)).filter(Boolean);
      $('#pv', v).innerHTML = phonePreview({ banners: order.length ? order : banners, layout, sections });
    };
    $('#lays', v).onclick = async (e) => {
      const b = e.target.closest('[data-l]'); if (!b || b.dataset.l === layout) return;
      const prev = layout; layout = b.dataset.l;
      $$('.lay', v).forEach((x) => x.classList.toggle('on', x === b)); drawPreview();
      try { await api('PUT', '/v1/admin/settings/home.bannerLayout', layout); toast(`Layout set to ${b.querySelector('b').textContent}. The app uses it now.`); }
      catch (err) { fail(err); layout = prev; $$('.lay', v).forEach((x) => x.classList.toggle('on', x.dataset.l === prev)); drawPreview(); }
    };
    const list = $('#list', v);
    sortable(list, 'banners', drawPreview);
    list.addEventListener('click', async (e) => {
      if (e.target.closest('[data-addb]')) return editBanner(null);
      const it = e.target.closest('.item'); if (!it) return;
      const b = banners.find((x) => x.id === it.dataset.id);
      if (e.target.closest('[data-up]')) moveItem(list, b.id, -1, 'banners', drawPreview);
      if (e.target.closest('[data-down]')) moveItem(list, b.id, 1, 'banners', drawPreview);
      if (e.target.closest('[data-edit]')) editBanner(b);
      if (e.target.closest('[data-del]') && (await confirmBox('Delete banner?', 'It disappears from the app straight away.'))) {
        try { await api('DELETE', '/v1/admin/banners/' + b.id); toast('Banner deleted'); pageBanners(); } catch (err) { fail(err); }
      }
    });
    list.addEventListener('change', async (e) => {
      if (!e.target.matches('[data-active]')) return;
      const it = e.target.closest('.item'); const b = banners.find((x) => x.id === it.dataset.id);
      try { await api('PATCH', '/v1/admin/banners/' + b.id, { active: e.target.checked }); b.active = e.target.checked; it.classList.toggle('off', !b.active); drawPreview(); toast(b.active ? 'Banner is on' : 'Banner is off'); } catch (err) { fail(err); e.target.checked = !e.target.checked; }
    });
    $('#add', v).onclick = () => editBanner(null);
    drawPreview();
  }
  const toLocal = (iso) => { if (!iso) return ''; const d = new Date(iso); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };
  const fromLocal = (s) => (s ? new Date(s).toISOString() : null);
  function editBanner(b) {
    const f = modal(b ? 'Edit banner' : 'New banner', `
      <div id="pvb" style="margin-bottom:16px"></div>
      <label class="f"><span>Look</span><div class="seg" id="styles">${[['PURPLE', 'Purple'], ['YELLOW', 'Yellow'], ['IMAGE', 'Photo']].map(([k, t]) => `<button type="button" class="${(b?.style || 'PURPLE') === k ? 'on' : ''}" data-style="${k}">${t}</button>`).join('')}</div><input type="hidden" name="style" value="${esc(b?.style || 'PURPLE')}"></label>
      <div id="imgbox">${dropHtml('mediaId', b?.imageUrl, 'Banner photo', 'Wide photo, about 3:1')}</div>
      <div class="fgrid">
        <label class="f"><span>Title (English)</span><input class="in" name="titleEn" maxlength="80" value="${esc(b?.titleEn)}"></label>
        <label class="f"><span>Title (Arabic)</span><input class="in ar" name="titleAr" maxlength="80" value="${esc(b?.titleAr)}"></label>
        <label class="f"><span>Subtitle (English)</span><input class="in" name="subtitleEn" maxlength="160" value="${esc(b?.subtitleEn)}"></label>
        <label class="f"><span>Subtitle (Arabic)</span><input class="in ar" name="subtitleAr" maxlength="160" value="${esc(b?.subtitleAr)}"></label>
      </div>
      <label class="f"><span>When tapped</span><select class="in" name="actionType">${ACTIONS.map(([k, t]) => opt(k, t, b?.actionType || 'NONE')).join('')}</select></label>
      <div id="act"></div>
      <div class="fgrid">
        <label class="f"><span>Show from</span><input class="in" type="datetime-local" name="startsAt" value="${esc(toLocal(b?.startsAt))}"><em>Optional</em></label>
        <label class="f"><span>Show until</span><input class="in" type="datetime-local" name="endsAt" value="${esc(toLocal(b?.endsAt))}"><em>Optional</em></label>
      </div>`,
    async (form) => {
      const style = val(form, 'style'), actionType = val(form, 'actionType');
      const img = val(form, 'mediaId');
      const hasImg = !!$('[data-drop=mediaId] img', form);
      if (style === 'IMAGE' && !hasImg) { toast('Upload a photo for a photo banner.', true); return false; }
      const actionValue = orNull(form.elements.actionValue ? String(form.elements.actionValue.value).trim() : '');
      if (['SHOP', 'CATEGORY', 'URL'].includes(actionType) && !actionValue) { toast('Choose where the banner should open.', true); return false; }
      if (actionType === 'URL' && !/^https:\/\//i.test(actionValue)) { toast('Links must start with https://', true); return false; }
      const body = {
        style, actionType, actionValue: ['SHOP', 'CATEGORY', 'URL'].includes(actionType) ? actionValue : null,
        titleEn: orNull(val(form, 'titleEn')), titleAr: orNull(val(form, 'titleAr')),
        subtitleEn: orNull(val(form, 'subtitleEn')), subtitleAr: orNull(val(form, 'subtitleAr')),
        startsAt: fromLocal(val(form, 'startsAt')), endsAt: fromLocal(val(form, 'endsAt')),
      };
      if (img) body.mediaId = img; else if (!hasImg) body.mediaId = null;
      if (body.startsAt && body.endsAt && body.endsAt <= body.startsAt) { toast('“Show until” must be after “Show from”.', true); return false; }
      if (b) await api('PATCH', '/v1/admin/banners/' + b.id, body); else { if (body.mediaId === null) delete body.mediaId; await api('POST', '/v1/admin/banners', body); }
      toast(b ? 'Banner saved. It’s in the app now.' : 'Banner added. It’s in the app now.');
      pageBanners();
    }, { size: 'lg' });
    wireDrop(f, 'mediaId', 1800);
    const act = () => {
      const t = val(f, 'actionType');
      const cur = b && b.actionType === t ? b.actionValue : '';
      $('#act', f).innerHTML =
        t === 'SHOP' ? `<label class="f"><span>Shop</span><select class="in" name="actionValue">${opt('', 'Choose a shop', cur)}${S.shops.map((s) => opt(s.id, s.name, cur)).join('')}</select></label>`
        : t === 'CATEGORY' ? `<label class="f"><span>Category</span><select class="in" name="actionValue">${S.categories.map((c) => opt(c.key, c.nameEn, cur)).join('')}</select></label>`
        : t === 'URL' ? `<label class="f"><span>Link</span><input class="in" name="actionValue" maxlength="300" value="${esc(cur)}" placeholder="https://"></label>` : '';
    };
    const preview = () => {
      const style = val(f, 'style');
      $('#imgbox', f).hidden = style !== 'IMAGE';
      const imgEl = $('[data-drop=mediaId] img', f);
      $('#pvb', f).innerHTML = bannerBox({ style, titleEn: val(f, 'titleEn'), subtitleEn: val(f, 'subtitleEn'), imageUrl: style === 'IMAGE' && imgEl ? imgEl.getAttribute('src') : null }, 'big');
    };
    $('#styles', f).onclick = (e) => {
      const c = e.target.closest('[data-style]'); if (!c) return;
      $$('button', $('#styles', f)).forEach((x) => x.classList.toggle('on', x === c));
      f.elements.style.value = c.dataset.style; preview();
    };
    f.elements.actionType.onchange = act;
    f.addEventListener('input', preview);
    f.addEventListener('change', preview);
    act(); preview();
  }

  // ---------- Categories ----------
  const SWATCHES = ['#C2410C', '#B45309', '#BE185D', '#1D4ED8', '#047857', '#9333EA', '#0E7490', '#B91C1C', '#2C123F', '#5B2BD6'];
  async function pageCategories() {
    crumbs([['Customer app'], ['Categories']]);
    loading('Categories');
    await loadCategories();
    const v = mount(ph('Categories', 'Logo, colour and name for each category on the customer home and shop filters. Drag to reorder.', `<button class="btn" id="add">${ic('plus', 'sm')} New category</button>`) + `
      <div class="cgrid" id="list">${S.categories.map((c) => `
        <div class="ccard ${c.active ? '' : 'off'}" data-id="${esc(c.key)}">
          <div class="top-r">${catTile(c)}<div class="nm"><b>${esc(c.nameEn)}</b><span class="ar">${esc(c.nameAr)}</span></div><span class="handle" title="Drag to reorder">${ic('drag', 'sm')}</span></div>
          <div class="meta"><span class="mono">${esc(c.key)}</span><span>·</span><span>${num(c.shops)} shops</span>${c.color ? `<span class="tier-dot" style="background:${esc(c.color)}"></span>` : ''}</div>
          <div class="cf">${toggle('active', c.active, 'data-active aria-label="Show in app"')}<span class="lbl">${c.active ? 'Shown' : 'Hidden'}</span><span class="spacer"></span><button class="btn ghost sm" data-edit>${ic('edit', 'sm')} Edit</button></div>
        </div>`).join('')}</div>`);
    const list = $('#list', v);
    sortable(list, 'categories');
    list.addEventListener('click', (e) => { const it = e.target.closest('.ccard'); if (it && e.target.closest('[data-edit]')) editCategory(S.categories.find((c) => c.key === it.dataset.id)); });
    list.addEventListener('change', async (e) => {
      if (!e.target.matches('[data-active]')) return;
      const it = e.target.closest('.ccard');
      try {
        await api('PATCH', '/v1/admin/categories/' + it.dataset.id, { active: e.target.checked });
        it.classList.toggle('off', !e.target.checked); $('.lbl', it).textContent = e.target.checked ? 'Shown' : 'Hidden';
        toast(e.target.checked ? 'Category is visible' : 'Category hidden from the app');
      } catch (err) { fail(err); e.target.checked = !e.target.checked; }
    });
    $('#add', v).onclick = () => editCategory(null);
  }
  function editCategory(c) {
    let color = c?.color || '';
    const f = modal(c ? 'Edit category' : 'New category', `
      <div class="cat-pv" id="cpv"></div>
      ${c ? '' : '<label class="f"><span>Key</span><input class="in mono" name="key" maxlength="40" required placeholder="PETS"><em>English capitals, numbers and _ only. Can’t be changed later.</em></label>'}
      <div class="fgrid">
        <label class="f"><span>Name (English)</span><input class="in" name="nameEn" maxlength="60" value="${esc(c?.nameEn)}" required></label>
        <label class="f"><span>Name (Arabic)</span><input class="in ar" name="nameAr" maxlength="60" value="${esc(c?.nameAr)}" required></label>
      </div>
      ${dropHtml('iconMediaId', c?.iconUrl, 'Logo', 'Square PNG with a transparent background works best')}
      <label class="f"><span>Colour</span><div class="swatches" id="sw"><button type="button" class="swatch none ${color ? '' : 'on'}" data-c="" aria-label="No colour"></button>${SWATCHES.map((h) => `<button type="button" class="swatch ${color.toUpperCase() === h ? 'on' : ''}" style="background:${h}" data-c="${h}" aria-label="Colour ${h}"></button>`).join('')}</div>
        <div class="colorrow"><input type="color" class="cpick" id="cp" value="${esc(color || '#5B2BD6')}" aria-label="Pick any colour"><input class="in" id="hex" value="${esc(color)}" placeholder="#5B2BD6" maxlength="7"></div></label>`,
    async (form) => {
      const body = { nameEn: val(form, 'nameEn'), nameAr: val(form, 'nameAr'), color: color || null };
      if (!body.nameEn || !body.nameAr) { toast('Both names are needed.', true); return false; }
      if (color && !/^#[0-9A-Fa-f]{6}$/.test(color)) { toast('Use a colour like #5B2BD6.', true); return false; }
      const icon = val(form, 'iconMediaId');
      if (icon) body.iconMediaId = icon; else if (dropCleared(form, 'iconMediaId')) body.iconMediaId = null;
      if (c) await api('PATCH', '/v1/admin/categories/' + c.key, body);
      else {
        const key = val(form, 'key').toUpperCase();
        if (!/^[A-Z0-9_]{2,40}$/.test(key)) { toast('The key uses English capitals, numbers and _ only.', true); return false; }
        if (!body.color) delete body.color;
        await api('POST', '/v1/admin/categories', { key, ...body });
      }
      toast(c ? 'Category saved. The app shows it now.' : 'Category added');
      pageCategories();
    });
    wireDrop(f, 'iconMediaId', 512);
    if (c) {
      const del = document.createElement('button');
      del.type = 'button'; del.className = 'btn ghost danger'; del.style.marginRight = 'auto';
      del.innerHTML = `${ic('trash', 'sm')} Delete category`;
      del.onclick = async () => {
        if (c.shops) { toast(`Move its ${c.shops} shop${c.shops === 1 ? '' : 's'} to another category first.`, true); return; }
        if (!(await confirmBox('Delete category?', `“${c.nameEn}” disappears from the app.`))) return;
        try { await api('DELETE', '/v1/admin/categories/' + c.key); f.close(); toast('Category deleted'); pageCategories(); } catch (err) { fail(err); }
      };
      $('.mf', f).prepend(del);
    }
    const preview = () => {
      const img = $('[data-drop=iconMediaId] img', f);
      const tile = { nameEn: val(f, 'nameEn') || 'Category', color, iconUrl: img ? img.getAttribute('src') : null };
      $('#cpv', f).innerHTML = `<div class="appchip">${catTile(tile, 'big')}${esc(tile.nameEn.split(' ')[0])}</div><div class="t"><span class="lbl">How it looks in the app</span><b>${esc(tile.nameEn)}</b><span class="muted">${esc(val(f, 'nameAr'))}</span></div>`;
    };
    const setColor = (h) => {
      color = h;
      $$('.swatch', f).forEach((s) => s.classList.toggle('on', (s.dataset.c || '').toUpperCase() === (h || '').toUpperCase()));
      $('#hex', f).value = h; if (h) $('#cp', f).value = h;
      preview();
    };
    $('#sw', f).onclick = (e) => { const s = e.target.closest('[data-c]'); if (s) setColor(s.dataset.c); };
    $('#cp', f).oninput = (e) => setColor(e.target.value.toUpperCase());
    $('#hex', f).oninput = (e) => { const h = e.target.value.trim(); color = h; if (/^#[0-9A-Fa-f]{6}$/.test(h)) setColor(h.toUpperCase()); else preview(); };
    f.addEventListener('input', preview); f.addEventListener('change', preview);
    preview();
  }

  // ---------- Offers moderation ----------
  async function pageOffers() {
    crumbs([['Customer app'], ['Offers']]);
    loading('Offers');
    const offers = await api('GET', '/v1/admin/offers');
    const v = mount(ph('Offers', 'Shops publish offers straight away. Hide anything that shouldn’t be in the app.') + `
      <div class="card flush"><div class="toolbar"><div class="inwrap">${ic('search', 'sm')}<input class="in" id="q" placeholder="Search offers or shops"></div><span class="cnt" id="cnt"></span></div>
      <div class="tw"><table class="tbl"><thead><tr><th>Offer</th><th>Type</th><th class="r">Cost</th><th>How</th><th>Activity</th><th>Status</th><th></th></tr></thead><tbody id="tb"></tbody></table></div></div>`);
    const draw = () => {
      const q = $('#q', v).value.trim().toLowerCase();
      const list = offers.filter((o) => !q || (o.title + ' ' + o.businessName).toLowerCase().includes(q));
      $('#cnt', v).textContent = `${list.length} offers`;
      $('#tb', v).innerHTML = list.length ? list.map((o) => `
        <tr data-id="${esc(o.id)}" class="${o.hidden ? 'off' : ''}">
          <td><div class="who"><span class="thumb">${o.imageUrl ? `<img src="${esc(o.imageUrl)}" alt="">` : ic('tag', 'sm')}</span><div class="t"><b>${esc(o.title)}</b><small>${esc(o.businessName)}</small></div></div></td>
          <td>${esc(KIND[o.kind] || o.kind)}</td><td class="r num">${o.pointsCost ? num(o.pointsCost) + ' pts' : 'Free'}</td><td>${o.requiresBooking ? 'Book first' : 'Walk in'}</td>
          <td class="muted">${num(o.bookings)} bookings${o.validTo ? ' · until ' + esc(day(o.validTo)) : ''}</td>
          <td>${o.hidden ? '<span class="pill bad">Hidden by Mukafaah</span>' : o.status === 'ACTIVE' ? '<span class="pill ok">Live</span>' : pill(o.status)}</td>
          <td><div class="acts"><button class="btn ${o.hidden ? 'sec' : 'danger'} sm" data-hide>${ic(o.hidden ? 'eye' : 'eyeoff', 'sm')} ${o.hidden ? 'Show again' : 'Hide'}</button></div></td>
        </tr>`).join('') : `<tr><td colspan="7">${empty('tag', 'No offers', '')}</td></tr>`;
    };
    draw();
    $('#q', v).oninput = draw;
    $('#tb', v).addEventListener('click', async (e) => {
      if (!e.target.closest('[data-hide]')) return;
      const o = offers.find((x) => x.id === e.target.closest('tr').dataset.id);
      try { await api('PATCH', '/v1/admin/offers/' + o.id, { hidden: !o.hidden }); o.hidden = !o.hidden; toast(o.hidden ? 'Offer hidden from the app' : 'Offer is visible again'); draw(); } catch (err) { fail(err); }
    });
  }

  // ---------- Customers ----------
  async function pageCustomers() {
    crumbs([['Customers']]);
    const v = mount(ph('Customers', 'Read only. Phone numbers are masked for privacy.') + `
      <div class="card flush"><form class="toolbar" id="sf"><div class="inwrap">${ic('search', 'sm')}<input class="in" id="q" placeholder="Name, last 4 digits or referral code"></div><button class="btn sec sm">Search</button><span class="cnt" id="cnt"></span></form>
      <div class="tw"><table class="tbl"><thead><tr><th>Customer</th><th class="r">Shop points</th><th class="r">Mukafaah Points</th><th class="r">Total spend</th><th>Tier</th><th class="r">Visits</th><th>Code · joined</th></tr></thead><tbody id="tb"></tbody></table></div></div>`);
    const run = async (q = '') => {
      $('#tb', v).innerHTML = `<tr><td colspan="7"><div class="skel h20"></div></td></tr>`;
      try {
        const rows = await api('GET', '/v1/admin/customers' + (q ? '?q=' + encodeURIComponent(q) : ''));
        $('#cnt', v).textContent = `${rows.length} shown`;
        $('#tb', v).innerHTML = rows.length ? rows.map((u) => `
          <tr><td><div class="who"><span class="avatar lt">${esc(initials(u.name))}</span><div class="t"><b>${esc(u.name || 'No name yet')}</b><small>${esc(u.phone)}</small></div></div></td>
          <td class="r num">${num(u.balance)}</td><td class="r num">${num(u.mukafaahPoints)}</td><td class="r num">${usd(u.lifetimeSpendMinor)}</td><td><span class="pill pur">${esc(String(u.tier || '').charAt(0) + String(u.tier || '').slice(1).toLowerCase())}</span></td>
          <td class="r num">${num(u.visits)}</td><td class="muted"><span class="mono">${esc(u.referralCode || '')}</span> · ${esc(day(u.createdAt))}</td></tr>`).join('') : `<tr><td colspan="7">${empty('users', 'No customers found', '')}</td></tr>`;
      } catch (e) { fail(e); }
    };
    $('#sf', v).onsubmit = (e) => { e.preventDefault(); run($('#q', v).value.trim()); };
    run();
  }

  // =====================================================================
  // Loyalty: tiers and Mukafaah Points
  // =====================================================================
  async function pageTiers() {
    crumbs([['Loyalty'], ['Tiers']]);
    loading('Tiers');
    const r = await api('GET', '/v1/admin/tiers');
    let tiers = r.tiers.map((t) => ({ ...t }));
    let dirty = false;
    const v = mount(ph('Tiers', 'Customers move up by their total spend at all Mukafaah shops. Reaching a tier gives its bonus in Mukafaah Points, once.', `<button class="btn sec" id="addT">${ic('plus', 'sm')} Add tier</button>`) + `
      <div id="ladder"></div>
      <div class="card flush mt16"><div class="tw nomax"><table class="tbl"><thead><tr><th>Tier</th><th>Name (Arabic)</th><th class="r">Total spend from</th><th class="r">Bonus Mukafaah Points</th><th>Colour</th><th>Perks</th><th>On</th><th></th></tr></thead><tbody id="tb"></tbody></table></div><div id="vmsg"></div></div>
      <div id="sb"></div>`);
    const check = () => {
      const errs = [];
      const act = tiers.filter((t) => t.active);
      if (!tiers.length) errs.push('Add at least one tier.');
      if (tiers[0] && tiers[0].minSpendMinor !== 0) errs.push('The first tier must start at $0.');
      tiers.forEach((t, i) => { if (i && !(t.minSpendMinor > tiers[i - 1].minSpendMinor)) errs.push(`${t.name || t.code}: needs more spend than ${tiers[i - 1].name || tiers[i - 1].code}.`); if (!/^[A-Z_]{2,20}$/.test(t.code)) errs.push(`Code “${t.code}” must be capitals or _.`); if (!t.name) errs.push('Every tier needs a name.'); });
      if (new Set(tiers.map((t) => t.code)).size !== tiers.length) errs.push('Tier codes must be different.');
      if (!act.length) errs.push('Keep at least one tier on.');
      return errs;
    };
    const draw = () => {
      $('#ladder', v).innerHTML = `<div class="ladder">${tiers.map((t) => `<div class="st ${t.active ? '' : 'off'}"><div class="sw-c" style="background:${esc(t.color || '#9AA0A6')}"></div><b>${esc(t.name || t.code)}</b><small>${t.minSpendMinor ? 'From ' + usd(t.minSpendMinor) + ' spent' : 'Everyone starts here'}</small>${t.bonusPoints ? `<span class="pill y bp nodot">+${num(t.bonusPoints)} Mukafaah Points</span>` : ''}<small>${num(t.customers || 0)} customers</small></div>`).join('')}</div>`;
      $('#tb', v).innerHTML = tiers.map((t, i) => `<tr data-i="${i}" class="${t.active ? '' : 'off'}">
        <td><div class="row nw"><span class="tier-dot" style="background:${esc(t.color || '#9AA0A6')}"></span><input class="in sm" data-f="name" value="${esc(t.name)}" maxlength="40" style="width:130px" aria-label="Name"></div><div class="muted mono" style="margin-top:4px">${t.customers == null ? `<input class="in sm mono" data-f="code" value="${esc(t.code)}" maxlength="20" style="width:120px;text-transform:uppercase" aria-label="Code">` : esc(t.code)}</div></td>
        <td><input class="in sm ar" data-f="nameAr" value="${esc(t.nameAr || '')}" maxlength="40" style="width:110px" aria-label="Arabic name"></td>
        <td class="r"><div class="inwrap" style="width:120px;margin-left:auto"><span class="pre">$</span><input class="in sm haspre" data-f="min" type="number" min="0" step="1" value="${t.minSpendMinor / 100}" ${i === 0 ? 'disabled' : ''} aria-label="Minimum spend"></div></td>
        <td class="r"><input class="in sm" data-f="bonusPoints" type="number" min="0" max="100000" value="${esc(t.bonusPoints)}" style="width:100px;text-align:right" aria-label="Bonus points"></td>
        <td><div class="tcolor"><input type="color" data-f="colorp" value="${esc(t.color || '#9AA0A6')}" aria-label="Colour"><input class="in sm" data-f="color" value="${esc(t.color || '')}" maxlength="7" aria-label="Colour hex"></div></td>
        <td><input class="in sm" data-f="perks" value="${esc(t.perks || '')}" maxlength="1000" style="min-width:220px" aria-label="Perks"></td>
        <td>${toggle('on' + i, t.active, 'data-f="active" aria-label="On"')}</td>
        <td><div class="acts">${i > 0 ? `<button class="btn ghost icon sm" data-rm aria-label="Remove">${ic('trash', 'sm')}</button>` : ''}</div></td></tr>`).join('');
      const errs = check();
      $('#vmsg', v).innerHTML = errs.length ? `<div class="vlist">${errs.map((e) => `<div class="vmsg">${ic('alert', 'xs')} ${esc(e)}</div>`).join('')}</div>` : '';
      $('#sb', v).innerHTML = dirty ? `<div class="savebar"><span>${ic('info', 'sm')} Unsaved changes to tiers.</span><span class="spacer"></span><button class="btn sec sm" id="undo">Discard</button><button class="btn accent sm" id="save" ${errs.length ? 'disabled' : ''}>Save tiers</button></div>` : '';
      if (dirty) {
        $('#undo', v).onclick = () => pageTiers();
        $('#save', v).onclick = async () => {
          try {
            const out = await api('PUT', '/v1/admin/tiers', { tiers: tiers.map((t) => ({ code: t.code, name: t.name, ...(t.nameAr ? { nameAr: t.nameAr } : {}), minSpendMinor: t.minSpendMinor, bonusPoints: t.bonusPoints, color: t.color || null, perks: t.perks || null, active: t.active })) });
            tiers = out.tiers.map((t) => ({ ...t })); dirty = false; draw(); toast('Tiers saved. Customers were placed by their spend.');
          } catch (e) { fail(e); }
        };
      }
    };
    const tb = $('#tb', v);
    tb.addEventListener('input', (e) => {
      const tr = e.target.closest('tr'); const f = e.target.dataset.f; if (!tr || !f) return;
      const t = tiers[Number(tr.dataset.i)];
      if (f === 'min') t.minSpendMinor = Math.max(0, Math.round(Number(e.target.value) * 100) || 0);
      else if (f === 'bonusPoints') t.bonusPoints = Math.max(0, Math.round(Number(e.target.value) || 0));
      else if (f === 'colorp') { t.color = e.target.value.toUpperCase(); $('[data-f=color]', tr).value = t.color; }
      else if (f === 'color') { const h = e.target.value.trim(); if (/^#[0-9A-Fa-f]{6}$/.test(h)) { t.color = h.toUpperCase(); $('[data-f=colorp]', tr).value = h; } else if (!h) t.color = null; }
      else if (f === 'code') t.code = e.target.value.trim().toUpperCase();
      else if (f === 'active') return;
      else t[f] = e.target.value.trim();
      dirty = true;
      const errs = check();
      $('#vmsg', v).innerHTML = errs.length ? `<div class="vlist">${errs.map((x) => `<div class="vmsg">${ic('alert', 'xs')} ${esc(x)}</div>`).join('')}</div>` : '';
      if (!$('#save', v)) draw(); else $('#save', v).disabled = !!errs.length;
    });
    tb.addEventListener('change', (e) => {
      const tr = e.target.closest('tr'); if (!tr) return;
      if (e.target.dataset.f === 'active') { tiers[Number(tr.dataset.i)].active = e.target.checked; dirty = true; }
      draw();
    });
    tb.addEventListener('click', (e) => { const b = e.target.closest('[data-rm]'); if (!b) return; tiers.splice(Number(b.closest('tr').dataset.i), 1); dirty = true; draw(); });
    $('#addT', v).onclick = () => {
      const last = tiers[tiers.length - 1];
      tiers.push({ code: 'TIER_' + (tiers.length + 1), name: '', nameAr: '', minSpendMinor: (last?.minSpendMinor || 0) + 10000, bonusPoints: 0, color: '#0E7490', perks: '', active: true, customers: null });
      dirty = true; draw();
    };
    draw();
  }

  async function pageMukafaah() {
    crumbs([['Loyalty'], ['Mukafaah Points']]);
    loading('Mukafaah Points');
    const [m] = await Promise.all([api('GET', '/v1/admin/mukafaah'), loadShops()]);
    const friendIds = new Set(m.friends.map((f) => f.id));
    const others = S.shops.filter((s) => !friendIds.has(s.id));
    const v = mount(ph('Mukafaah Points', 'Company points you give for joining, referrals and tasks. Customers spend them at Mukafaah Friends shops, up to each shop’s limit per bill. 100 points = $1.') + `
      <div class="grid g4">
        ${kpi('Given to customers', num(m.totals.issued), 'gift', `≈ ${usd(m.totals.issued)}`, 'hero')}
        ${kpi('Spent at shops', num(m.totals.redeemed), 'bag', `≈ ${usd(m.totals.redeemed)} owed to shops`, '', 'y')}
        ${kpi('Still with customers', num(m.totals.outstanding), 'wallet', `≈ ${usd(m.totals.outstanding)}`, '', 'g')}
        ${kpi('Friends shops', num(m.friends.filter((f) => f.friendsEnabled).length), 'handshake', 'Accept Mukafaah Points')}
      </div>
      <div class="grid g21 mt16">
        <div class="card flush"><div class="card-h"><h3>How customers earn them</h3><div class="sub">Given automatically. Tier bonuses are set on the Tiers page.</div></div>
          <div class="tw nomax"><table class="tbl"><thead><tr><th>Rule</th><th class="r">Points</th><th>On</th></tr></thead><tbody id="rules">${m.rules.map((r) => `<tr data-code="${esc(r.code)}" class="${r.active ? '' : 'off'}"><td><input class="in sm" data-f="title" value="${esc(r.title)}" maxlength="120" style="min-width:220px" aria-label="Title"><div class="muted mono" style="margin-top:4px">${esc(r.code)}</div></td><td class="r"><input class="in sm" data-f="points" type="number" min="0" max="100000" value="${esc(r.points)}" style="width:100px;text-align:right" aria-label="Points"></td><td>${toggle('r', r.active, 'data-f="active" aria-label="On"')}</td></tr>`).join('')}</tbody></table></div></div>
        <form class="card" id="gf" novalidate><div class="card-h"><h3>Give points to a customer</h3><div class="sub">For contests, apologies or tasks. They get a notification.</div></div>
          <label class="f"><span>Customer phone</span><div class="phone-in sm"><span class="cc">${flag}+961</span><input name="phone" inputmode="tel" placeholder="70 111 222" required></div></label>
          <label class="f"><span>Points</span><input class="in" name="points" type="number" min="1" max="100000" required></label>
          <label class="f"><span>Reason</span><input class="in" name="reason" maxlength="200" placeholder="Instagram contest winner" required></label>
          <button class="btn block">${ic('send', 'sm')} Give points</button></form>
      </div>
      <div class="card flush mt16"><div class="card-h"><h3>Mukafaah Friends shops</h3><span class="sp"></span>${others.length ? `<select class="in sm" id="addF" style="width:auto">${opt('', 'Add a shop…', '')}${others.map((s) => opt(s.id, s.name, '')).join('')}</select>` : ''}</div>
        <div class="tw nomax"><table class="tbl"><thead><tr><th>Shop</th><th>Accepts Mukafaah Points</th><th class="r">Max per bill</th><th class="r">Redeemed so far</th></tr></thead><tbody id="fr">${m.friends.map((f) => `<tr data-id="${esc(f.id)}" class="${f.friendsEnabled ? '' : 'off'}"><td><a href="#shop/${esc(f.id)}"><b>${esc(f.name)}</b></a></td><td>${toggle('f', f.friendsEnabled, 'data-f="on" aria-label="Accepts"')}</td><td class="r"><div class="inwrap" style="width:130px;margin-left:auto"><input class="in sm hasuf" data-f="max" type="number" min="0" max="100000" value="${esc(f.maxPoints)}" aria-label="Max per bill"><span class="suf">pts</span></div></td><td class="r num">${num(f.redeemedPoints)} <span class="muted">· ${usd(f.redeemedPoints)}</span></td></tr>`).join('') || `<tr><td colspan="4">${empty('handshake', 'No Friends shops yet', 'Add a shop so customers can spend Mukafaah Points there.')}</td></tr>`}</tbody></table></div></div>`);
    const saveRule = async (tr, body) => {
      try { await api('PATCH', '/v1/admin/mukafaah/rules/' + tr.dataset.code, body); toast('Rule saved'); } catch (e) { fail(e); }
    };
    $('#rules', v).addEventListener('change', (e) => {
      const tr = e.target.closest('tr'), f = e.target.dataset.f; if (!tr || !f) return;
      if (f === 'active') { tr.classList.toggle('off', !e.target.checked); saveRule(tr, { active: e.target.checked }); }
      if (f === 'points') { const n = Math.max(0, Math.min(100000, Math.round(Number(e.target.value) || 0))); e.target.value = n; saveRule(tr, { points: n }); }
      if (f === 'title' && e.target.value.trim()) saveRule(tr, { title: e.target.value.trim() });
    });
    const saveFriend = async (id, enabled, maxPoints, name) => {
      try { await api('PATCH', `/v1/admin/shops/${id}/friends`, { enabled, maxPoints }); const row = S.shops.find((s) => s.id === id); if (row) { row.friendsEnabled = enabled; row.friendsMaxPoints = maxPoints; } toast(enabled ? `${name}: up to ${num(maxPoints)} Mukafaah Points per bill` : `${name} no longer accepts Mukafaah Points`); return true; }
      catch (e) { fail(e); return false; }
    };
    $('#fr', v).addEventListener('change', async (e) => {
      const tr = e.target.closest('tr'); if (!tr) return;
      const on = $('[data-f=on]', tr).checked, max = Math.max(0, Math.min(100000, Math.round(Number($('[data-f=max]', tr).value) || 0)));
      const name = $('b', tr).textContent;
      if (await saveFriend(tr.dataset.id, on, max, name)) tr.classList.toggle('off', !on);
    });
    const addF = $('#addF', v);
    if (addF) addF.onchange = async () => { const s = S.shops.find((x) => x.id === addF.value); if (s && (await saveFriend(s.id, true, 300, s.name))) pageMukafaah(); };
    $('#gf', v).onsubmit = async (e) => {
      e.preventDefault();
      const f = e.target, pts = Math.round(Number(val(f, 'points')) || 0);
      if (!val(f, 'phone') || pts < 1 || !val(f, 'reason')) { toast('Add the phone, the points and a reason.', true); return; }
      const btn = $('button', f); btn.disabled = true;
      try { const r = await api('POST', '/v1/admin/mukafaah/grant', { phone: val(f, 'phone'), points: pts, reason: val(f, 'reason') }); toast(`${num(pts)} Mukafaah Points sent. Their balance is ${num(r.balance)}.`); f.reset(); }
      catch (err) { fail(err); } finally { btn.disabled = false; }
    };
  }

  // =====================================================================
  // Accounts and settings
  // =====================================================================
  const ROLE_DESC = {
    ADMIN: 'Everything: shops, content, loyalty and accounts.',
    EDITOR: 'Shops and app content. No accounts, tiers or giving points.',
    SHOP: 'Only their own shop: profile, offers, store, orders, bills and its report.',
  };
  async function pageAccounts() {
    crumbs([['Admin'], ['Accounts']]);
    loading('Accounts');
    const [r] = await Promise.all([api('GET', '/v1/admin/accounts'), loadShops()]);
    const accounts = r.accounts;
    const v = mount(ph('Accounts', 'Only accounts created here can sign in to Mukafaah Manager. Shop accounts see their own shop and nothing about the rest of Mukafaah.', `<button class="btn" id="add">${ic('userplus', 'sm')} New account</button>`) + `
      <div class="card flush"><div class="tw"><table class="tbl"><thead><tr><th>Person</th><th>Role</th><th>Access</th><th>Since</th><th>Active</th><th></th></tr></thead><tbody id="tb">
      ${accounts.map((a) => `<tr data-id="${esc(a.userId)}" class="${a.active ? '' : 'off'}"><td><div class="who"><span class="avatar ${a.role === 'SHOP' ? 'lt' : ''}">${esc(initials(a.name))}</span><div class="t"><b>${esc(a.name || 'No name')}</b><small>•••• ${esc(a.phoneLast4)}${a.userId === S.me.userId ? ' · you' : ''}</small></div></div></td>
        <td><span class="role ${esc(a.role)}">${esc(ROLE_NAME[a.role] || a.role)}</span></td>
        <td>${a.role === 'SHOP' ? `<div class="shopchips">${a.shops.map((s) => `<span>${esc(s.name)}</span>`).join('') || '<span>No shop</span>'}</div>` : '<span class="muted">All of Mukafaah</span>'}</td>
        <td class="muted">${esc(day(a.createdAt))}</td>
        <td>${toggle('a', a.active, `data-active aria-label="Active" ${a.userId === S.me.userId || (a.role === 'OWNER' && S.me.role !== 'OWNER') ? 'disabled' : ''}`)}</td>
        <td><div class="acts">${a.userId === S.me.userId || (a.role === 'OWNER' && S.me.role !== 'OWNER') ? '' : `<button class="btn ghost sm" data-edit>${ic('edit', 'sm')} Edit</button>`}</div></td></tr>`).join('')}
      </tbody></table></div></div>`);
    $('#add', v).onclick = () => editAccount(null);
    $('#tb', v).addEventListener('click', (e) => { if (e.target.closest('[data-edit]')) editAccount(accounts.find((a) => a.userId === e.target.closest('tr').dataset.id)); });
    $('#tb', v).addEventListener('change', async (e) => {
      if (!e.target.matches('[data-active]')) return;
      const tr = e.target.closest('tr');
      try { await api('PATCH', '/v1/admin/accounts/' + tr.dataset.id, { active: e.target.checked }); tr.classList.toggle('off', !e.target.checked); toast(e.target.checked ? 'Account can sign in' : 'Account switched off'); } catch (err) { fail(err); e.target.checked = !e.target.checked; }
    });
  }
  function editAccount(a) {
    const picked = new Set((a?.shops || []).map((s) => s.id));
    let role = a?.role && a.role !== 'OWNER' ? a.role : 'SHOP';
    const f = modal(a ? 'Edit account' : 'New account', `
      ${a ? '' : `<label class="f"><span>Phone number</span><div class="phone-in"><span class="cc">${flag}+961</span><input name="phone" inputmode="tel" placeholder="70 123 456" required></div><em>They sign in with this number and a code we text them.</em></label>`}
      <label class="f"><span>Full name</span><input class="in" name="name" maxlength="60" value="${esc(a?.name || '')}" required></label>
      <span class="flabel">Role</span>
      <div class="rolepick" id="rp">${['SHOP', 'EDITOR', 'ADMIN'].map((k) => `<label class="${k === role ? 'on' : ''}"><input type="radio" name="role" value="${k}" ${k === role ? 'checked' : ''}><b><span class="role ${k}">${esc(ROLE_NAME[k])}</span></b><small>${esc(ROLE_DESC[k])}</small></label>`).join('')}</div>
      <div id="shopbox" class="mt16"><label class="f"><span>Shops they can manage</span><div class="picker"><div class="ps"><div class="inwrap">${ic('search', 'sm')}<input class="in sm" id="sq" placeholder="Search shops"></div></div><div class="pl" id="pl"></div><div class="pf" id="pc"></div></div></label></div>`,
    async (form) => {
      const body = { name: val(form, 'name'), role };
      if (!body.name) { toast('Add their name.', true); return false; }
      if (role === 'SHOP') { if (!picked.size) { toast('Pick the shop they can manage.', true); return false; } body.shopIds = [...picked]; }
      if (a) await api('PATCH', '/v1/admin/accounts/' + a.userId, body);
      else { body.phone = val(form, 'phone'); if (!body.phone) { toast('Add their phone number.', true); return false; } await api('POST', '/v1/admin/accounts', body); }
      toast(a ? 'Account saved' : 'Account created. They can sign in now.');
      pageAccounts();
    }, { save: a ? 'Save' : 'Create account', size: 'lg' });
    const drawShops = () => {
      const q = ($('#sq', f).value || '').toLowerCase();
      $('#pl', f).innerHTML = S.shops.filter((s) => picked.has(s.id) || !q || s.name.toLowerCase().includes(q)).slice(0, 100)
        .map((s) => `<label><input type="checkbox" data-s="${esc(s.id)}" ${picked.has(s.id) ? 'checked' : ''}><span class="thumb" style="width:24px;height:24px;font-size:11px">${esc(initials(s.name))}</span><span>${esc(s.name)}</span><span class="spacer"></span><small class="muted">${esc(s.city || '')}</small></label>`).join('') || '<div class="muted" style="padding:12px">No shops.</div>';
      $('#pc', f).textContent = `${picked.size} selected`;
    };
    const sync = () => { $('#shopbox', f).hidden = role !== 'SHOP'; $$('#rp label', f).forEach((l) => l.classList.toggle('on', $('input', l).value === role)); };
    $('#rp', f).addEventListener('change', (e) => { if (e.target.name === 'role') { role = e.target.value; sync(); } });
    $('#pl', f).addEventListener('change', (e) => { const c = e.target.closest('[data-s]'); if (!c) return; c.checked ? picked.add(c.dataset.s) : picked.delete(c.dataset.s); $('#pc', f).textContent = `${picked.size} selected`; });
    $('#sq', f).oninput = drawShops;
    drawShops(); sync();
  }

  async function pageSettings() {
    crumbs([['Admin'], ['Settings']]);
    loading('Settings');
    const s = await api('GET', '/v1/admin/settings');
    const tr = s.transfer || {}, rf = s.referral || {}, sp = s.support || {}, df = s.defaults || {};
    const v = mount(ph('Settings', 'Rules for the whole app. Saved changes reach the apps within a few seconds.') + `
      <div class="grid g2">
        <form class="card" data-key="defaults"><div class="card-h"><h3>New shops</h3></div>
          <label class="f"><span>Points back for new shops</span><span class="pct" style="width:100%"><input class="in" type="number" name="earnPercent" min="0" max="100" value="${esc(df.earnPercent ?? 10)}" style="width:100%"></span><em>100 points = $1. A shop at 10% gives 100 points on a $10 bill.</em></label>
          <div class="row end"><button class="btn">Save</button></div></form>
        <form class="card" data-key="transfer"><div class="card-h"><h3>Sending points to friends</h3></div>
          <div class="fgrid">
            <label class="f"><span>Smallest transfer</span><input class="in" type="number" name="minPoints" min="1" value="${esc(tr.minPoints ?? 10)}"></label>
            <label class="f"><span>Who can send</span><select class="in" name="minTier">${opt('SILVER', 'Everyone', tr.minTier)}${opt('GOLD', 'Gold and up', tr.minTier)}${opt('PLATINUM', 'Platinum only', tr.minTier)}</select></label>
            <label class="f"><span>Most points per day</span><input class="in" type="number" name="dailyMaxPoints" min="1" value="${esc(tr.dailyMaxPoints ?? 20000)}"></label>
            <label class="f"><span>Most transfers per day</span><input class="in" type="number" name="dailyMaxCount" min="1" value="${esc(tr.dailyMaxCount ?? 10)}"></label>
          </div><div class="row end"><button class="btn">Save</button></div></form>
        <form class="card" data-key="referral"><div class="card-h"><h3>Referral codes</h3></div>
          <label class="f"><span>Days a new customer has to enter a friend’s code</span><input class="in" type="number" name="windowDays" min="0" max="365" value="${esc(rf.windowDays ?? 14)}"></label>
          <div class="row end"><button class="btn">Save</button></div></form>
        <form class="card" data-key="support"><div class="card-h"><h3>Support contacts</h3></div>
          <label class="f"><span>Support WhatsApp</span><input class="in" name="whatsapp" inputmode="tel" placeholder="+961 …" value="${esc(sp.whatsapp || '')}"></label>
          <label class="f"><span>Instagram username</span><input class="in" name="instagram" maxlength="60" value="${esc(sp.instagram || '')}"></label>
          <div class="row end"><button class="btn">Save</button></div></form>
      </div>`);
    $$('form[data-key]', v).forEach((form) => {
      form.onsubmit = async (e) => {
        e.preventDefault();
        const key = form.dataset.key;
        const n = (x) => Math.round(Number(val(form, x)));
        const body = key === 'defaults' ? { earnPercent: n('earnPercent') }
          : key === 'transfer' ? { minPoints: n('minPoints'), dailyMaxPoints: n('dailyMaxPoints'), dailyMaxCount: n('dailyMaxCount'), minTier: val(form, 'minTier') }
          : key === 'referral' ? { windowDays: n('windowDays') }
          : { whatsapp: orNull(val(form, 'whatsapp')), instagram: orNull(val(form, 'instagram').replace(/^@/, '')) };
        const btn = $('button', form); btn.disabled = true;
        try { await api('PUT', '/v1/admin/settings/' + key, body); toast('Saved'); } catch (err) { fail(err); } finally { btn.disabled = false; }
      };
    });
  }

  // =====================================================================
  // Router
  // =====================================================================
  const ROUTES = {
    overview: [pageOverview, isContent], shops: [pageShops, isContent], reports: [pageReports, () => true], customers: [pageCustomers, isContent],
    home: [pageHome, isContent], banners: [pageBanners, isContent], categories: [pageCategories, isContent], offers: [pageOffers, isContent],
    tiers: [pageTiers, isFull], mukafaah: [pageMukafaah, isFull], accounts: [pageAccounts, isFull], settings: [pageSettings, isFull], myshops: [pageMyShops, isShop],
  };
  function homeHash() {
    if (!isShop()) return 'overview';
    const shops = S.me.shops || [];
    return shops.length === 1 ? 'shop/' + shops[0].id : 'myshops';
  }
  async function route() {
    if (!S.me) return;
    $$('.mbg, .pop, .scrim').forEach((m) => m.remove());
    $('#shell')?.classList.remove('nav-open');
    const h = location.hash.slice(1);
    const shopM = h.match(/^shop\/([0-9a-f-]{36})(?:\/([a-z]+))?$/);
    if (shopM && isShop() && !(S.me.shops || []).some((s) => s.id === shopM[1])) { location.hash = homeHash(); return; }
    const r = ROUTES[h];
    if (!shopM && (!r || !r[1]())) { if (h !== homeHash()) { location.hash = homeHash(); return; } }
    const key = shopM ? (isShop() ? 'shop/' + shopM[1] : 'shops') : h;
    $$('[data-nav]').forEach((b) => b.classList.toggle('on', b.dataset.nav === key));
    window.scrollTo(0, 0);
    try { await (shopM ? pageShop(shopM[1], shopM[2] || 'overview') : r[0]()); } catch (e) {
      if (e.status === 401) return;
      mount(ph('Couldn’t load this page') + `<div class="card">${empty('alert', e.status === 403 ? 'No access' : 'Something went wrong', errText(e), '<button class="btn sec" id="retry">Try again</button>')}</div>`);
      const b = $('#retry'); if (b) b.onclick = route;
    }
  }
  window.addEventListener('hashchange', route);

  async function boot() {
    if (!S.access && !S.refresh) return renderLogin();
    try {
      S.me = await api('GET', '/v1/admin/me');
    } catch (e) {
      if (e.status === 401 || e.status === 403) { setTokens(null, null); renderLogin(e.status === 403 ? ERR.NOT_ADMIN : ''); return; }
      $('#app').innerHTML = `<div class="noaccess card">${empty('alert', 'Can’t open Mukafaah Manager', errText(e), '<button class="btn" id="retry">Try again</button>')}</div>`;
      $('#retry').onclick = boot;
      return;
    }
    renderShell();
    if (!location.hash || location.hash === '#') location.hash = homeHash(); else route();
  }
  boot();
})();
