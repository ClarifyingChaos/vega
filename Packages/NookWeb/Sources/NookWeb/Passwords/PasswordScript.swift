// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordScript.swift
//  NookWeb
//
//  FORK: the page side of the password manager. It runs in its own content world, so the page's
//  own scripts can neither read it nor call the native handler. Nothing is filled until the person
//  clicks a saved login in the menu this script draws; the click must be a real one (isTrusted).
//

import Foundation

enum PasswordScript {
    static let handlerName = "vegaPasswords"

    /// Starts with "// Nook" so the app keeps it when it rebuilds a view's scripts (see WKUserScript+NookOwned).
    static let source = #"""
    // Nook Passwords (Vega)
    (function () {
      if (window.__vegaPasswords) return;
      window.__vegaPasswords = true;
      const handler = () => window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vegaPasswords;
      const ask = (msg) => { const h = handler(); return h ? h.postMessage(msg) : Promise.resolve(null); };

      const visible = (el) => {
        if (!el || !el.isConnected) return false;
        const r = el.getBoundingClientRect();
        if (r.width < 4 || r.height < 4) return false;
        const s = getComputedStyle(el);
        return s.visibility !== 'hidden' && s.display !== 'none';
      };
      const passwordFields = (root) => Array.from((root || document).querySelectorAll('input[type=password]'))
        .filter((el) => visible(el) && !el.disabled && !el.readOnly);
      const isUserField = (el) => el && el.tagName === 'INPUT' && ['text', 'email', 'tel', ''].includes((el.getAttribute('type') || '').toLowerCase()) && visible(el) && !el.disabled && !el.readOnly;

      // The username field: the closest visible text-like input before the password field.
      const usernameFor = (pw) => {
        const scope = pw.form || document;
        const fields = Array.from(scope.querySelectorAll('input')).filter(isUserField);
        const before = fields.filter((el) => el.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING);
        const byHint = before.concat(fields).find((el) => /user|email|login|name/i.test((el.autocomplete || '') + (el.name || '') + (el.id || '')));
        return byHint || before[before.length - 1] || null;
      };
      // The password field a focused field belongs to: itself, or the one after a username field.
      const passwordFor = (el) => {
        if (el.type === 'password') return el;
        const scope = el.form || document;
        const pws = passwordFields(scope);
        return pws.find((pw) => el.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) || null;
      };

      const setValue = (el, value) => {
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };

      // ---- The menu of saved logins ---------------------------------------------------------
      let menu = null, cache = null;
      const closeMenu = () => { if (menu) { menu.host.remove(); menu = null; } };
      const logins = async () => { if (!cache) cache = Promise.resolve(ask({ op: 'list' })).then((r) => Array.isArray(r) ? r : []); return cache; };

      const openMenu = async (field) => {
        const pw = passwordFor(field);
        if (!pw) return;
        const list = await logins();
        if (!list.length || document.activeElement !== field) return;
        closeMenu();
        const host = document.createElement('div');
        host.style.cssText = 'all:initial;position:absolute;z-index:2147483647;';
        const root = host.attachShadow({ mode: 'closed' });
        const rect = field.getBoundingClientRect();
        host.style.left = (rect.left + scrollX) + 'px';
        host.style.top = (rect.bottom + scrollY + 4) + 'px';
        const style = document.createElement('style');
        style.textContent = ':host{color-scheme:light dark}.m{font:13px -apple-system,system-ui;min-width:' + Math.max(rect.width, 220) +
          'px;background:Canvas;color:CanvasText;border:1px solid rgba(128,128,128,.4);border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,.25);padding:4px}' +
          '.i{padding:7px 10px;border-radius:7px;cursor:default;display:flex;gap:8px;align-items:center}.i:hover{background:rgba(10,132,255,.9);color:#fff}' +
          '.h{font-size:11px;opacity:.6;padding:4px 10px}';
        const box = document.createElement('div');
        box.className = 'm';
        const head = document.createElement('div');
        head.className = 'h';
        head.textContent = 'Saved passwords';
        box.appendChild(head);
        list.forEach((login) => {
          const row = document.createElement('div');
          row.className = 'i';
          row.textContent = '🔑 ' + login.u;
          row.addEventListener('mousedown', (e) => e.preventDefault());
          row.addEventListener('click', async (e) => {
            if (!e.isTrusted) return;
            const secret = await ask({ op: 'fill', u: login.u });
            if (!secret) return;
            const user = pw === field ? usernameFor(pw) : field;
            if (user) setValue(user, login.u);
            setValue(pw, secret);
            closeMenu();
          });
          box.appendChild(row);
        });
        root.append(style, box);
        document.documentElement.appendChild(host);
        menu = { host, field };
      };

      document.addEventListener('focusin', (e) => {
        const el = e.target;
        if (el && el.tagName === 'INPUT' && (el.type === 'password' || isUserField(el))) openMenu(el);
      }, true);
      document.addEventListener('mousedown', (e) => { if (menu && e.target !== menu.field && !e.composedPath().includes(menu.host)) closeMenu(); }, true);
      document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeMenu(); }, true);

      // ---- Noticing a login ---------------------------------------------------------------------
      let candidate = null, timer = null;
      const sendCandidate = () => { if (candidate) { ask({ op: 'submit', u: candidate.u, p: candidate.p }); candidate = null; } };
      const capture = (scope) => {
        const pws = passwordFields(scope).filter((el) => el.value);
        if (!pws.length) return;
        // A sign-up form repeats the password; the login one has a single field.
        const pw = pws.find((el) => /current-password|new-password/.test(el.autocomplete || '')) || pws[0];
        const user = usernameFor(pw);
        candidate = { u: user ? user.value : '', p: pw.value, el: pw };
        clearTimeout(timer);
        // If the form is still there a moment later the login most likely failed: nothing to save.
        timer = setTimeout(() => { if (candidate && (!visible(candidate.el) || !candidate.el.value)) sendCandidate(); else candidate = null; }, 1800);
      };
      document.addEventListener('submit', (e) => capture(e.target), true);
      document.addEventListener('click', (e) => {
        const b = e.target.closest && e.target.closest('button, input[type=submit], [role=button]');
        if (b && e.isTrusted) capture(b.form || b.closest('form') || document);
      }, true);
      document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.isTrusted && e.target.tagName === 'INPUT') capture(e.target.form || document); }, true);
      // Leaving the page after a submit is the usual sign of success.
      addEventListener('pagehide', sendCandidate);
    })();
    """#
}
