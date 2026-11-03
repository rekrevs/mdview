/* mdview author-HTML policy: a GitHub-style allowlist (after html-pipeline's sanitizer).
 *
 * Author HTML never reaches WebKit as source. Every html_block/html_inline token is scanned
 * with the CommonMark tag grammar and re-emitted as escaped text plus tags rebuilt from fixed
 * allowlisted names and attributes whose decoded values were validated; values are emitted
 * double-quoted and escaped. Nothing outside the allowlist (svg, math, style, template, ...)
 * is ever emitted, so the HTML parser cannot enter foreign or raw-text modes (no mXSS).
 * Disallowed markup stays visible as text, comments are hidden, unsafe attributes are dropped.
 */
(() => {
  'use strict';
  const WS = '[ \\t\\n\\r\\f]';
  const ATTRIBUTE = `${WS}+[A-Za-z_:][A-Za-z0-9_.:-]*(?:${WS}*=${WS}*(?:[^"'=<>\`\\x00-\\x20]+|'[^']*'|"[^"]*"))?`;
  const OPEN_TAG = new RegExp(`<([A-Za-z][A-Za-z0-9-]*)((?:${ATTRIBUTE})*)${WS}*(/?)>`, 'y');
  const ATTRIBUTE_PARTS = new RegExp(`${WS}+([A-Za-z_:][A-Za-z0-9_.:-]*)(?:${WS}*=${WS}*(?:([^"'=<>\`\\x00-\\x20]+)|'([^']*)'|"([^"]*)"))?`, 'g');
  const CLOSE_TAG = new RegExp(`</([A-Za-z][A-Za-z0-9-]*)${WS}*>`, 'y');
  const COMMENT = /<!---?>|<!--[\s\S]*?-->/y;
  const PROCESSING = /<\?[\s\S]*?\?>/y, CDATA = /<!\[CDATA\[[\s\S]*?\]\]>/y, DECLARATION = /<![A-Za-z][^>]*>/y;

  const INLINE = ['a', 'b', 'i', 'strong', 'em', 'del', 'ins', 's', 'strike', 'sub', 'sup', 'kbd', 'code', 'tt', 'samp', 'var', 'q', 'cite', 'dfn', 'abbr', 'mark', 'small', 'span', 'time', 'ruby', 'rt', 'rp', 'bdo'];
  const CONTAINERS = new Set(['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'div', 'blockquote', 'pre', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'caption', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'details', 'summary', 'figure', 'figcaption', 'picture']);
  const VOID = new Set(['hr', 'br', 'wbr', 'img', 'source']);
  const ALLOWED = new Set([...CONTAINERS, ...VOID, ...INLINE]);
  // Inside a paragraph, heading or cell only phrasing tags are emitted: block tags such as
  // <li>, <td> or <h2> would make the HTML parser close trusted renderer structure.
  const PHRASING = new Set([...INLINE, 'br', 'wbr', 'img', 'picture', 'source']);
  // Shown verbatim through the matching close tag: their content is not markup in a browser.
  const RAW_TEXT = new Set(['script', 'style', 'textarea', 'title', 'xmp', 'iframe', 'noembed', 'noframes', 'noscript', 'plaintext', 'template', 'svg', 'math', 'select', 'object']);

  const pattern = (regex, lower = true) => value => {
    value = value.trim();
    return regex.test(value) ? (lower ? value.toLowerCase() : value) : null;
  };
  const text = value => value;
  const dimension = pattern(/^\d{1,5}%?$/);
  const integer = pattern(/^-?\d{1,9}$/);
  const align = pattern(/^(left|center|right|justify)$/i);
  const valign = pattern(/^(top|middle|bottom|baseline)$/i);
  const identifier = value => (/^[^\t\n\f\r ]{1,200}$/.test(value) ? `user-content-${value}` : null);
  const GLOBAL = { title: text, lang: pattern(/^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$/, false), dir: pattern(/^(ltr|rtl|auto)$/i),
    'aria-label': text, 'aria-hidden': pattern(/^(true|false)$/i), id: identifier };
  const cell = { align, valign, width: dimension, colspan: pattern(/^\d{1,4}$/), rowspan: pattern(/^\d{1,4}$/) };
  const ATTRIBUTES = {
    a: { href: 'link', name: identifier },
    img: { src: 'image', alt: text, width: dimension, height: dimension, align: pattern(/^(left|right|top|middle|bottom|center)$/i), loading: pattern(/^(lazy|eager)$/i) },
    source: { srcset: 'srcset', media: pattern(/^[a-z0-9 ():,.-]{1,200}$/i, false), type: pattern(/^image\/[a-z0-9.+-]{1,50}$/i), width: dimension, height: dimension },
    div: { align }, p: { align }, h1: { align }, h2: { align }, h3: { align }, h4: { align }, h5: { align }, h6: { align }, caption: { align }, hr: { align },
    table: { align, width: dimension, border: pattern(/^\d{1,3}$/) },
    thead: { align, valign }, tbody: { align, valign }, tfoot: { align, valign }, tr: { align, valign },
    td: cell, th: { ...cell, scope: pattern(/^(row|col|rowgroup|colgroup)$/i) },
    ol: { start: integer, type: pattern(/^[1aAiI]$/, false) }, li: { value: integer },
    details: { open: 'boolean' }, time: { datetime: pattern(/^[0-9A-Za-z:.+ -]{1,64}$/, false) },
    del: { datetime: pattern(/^[0-9A-Za-z:.+ -]{1,64}$/, false) }, ins: { datetime: pattern(/^[0-9A-Za-z:.+ -]{1,64}$/, false) }
  };

  function create(md) {
    const escape = md.utils.escapeHtml;
    // Character references as a browser would decode them, so validation sees the real value.
    const decode = value => value.replace(/&(?:#[xX]([0-9a-fA-F]{1,8});?|#([0-9]{1,9});?|([A-Za-z][A-Za-z0-9]{1,31});)/g, (match, hex, decimal, name) => {
      if (name) return md.utils.unescapeAll(match);
      const code = parseInt(hex ?? decimal, hex ? 16 : 10);
      return md.utils.isValidEntityCode(code) ? md.utils.fromCodePoint(code) : '�';
    });
    const escapeText = value => escape(decode(value));

    // WHATWG URL preprocessing: tab/CR/LF vanish anywhere, C0 controls and spaces at the ends.
    const clean = value => value.replace(/[\t\n\r]/g, '').replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, '');
    function url(value, schemes, extra) {
      value = clean(value);
      if (!value || /^[/\\]{2}/.test(value) || value.includes('\\')) return null;
      const scheme = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(value);
      if (scheme ? !(schemes.includes(scheme[1].toLowerCase()) || extra?.test(value)) : /^[^/?#]*:/.test(value)) return null;
      const normalized = md.normalizeLink(value);
      return md.validateLink(normalized) ? normalized : null;
    }
    const linkURL = value => (clean(value).startsWith('#') ? url(value, []) : url(value, ['http', 'https', 'mailto']));
    const imageURL = value => url(value, ['http', 'https'], /^data:image\/(png|gif|jpeg|webp);/i);
    function parseSrcset(value) {
      const candidates = [];
      let rest = value;
      while ((rest = rest.replace(/^[ \t\n\r\f,]+/, ''))) {
        const location = /^[^ \t\n\r\f]+/.exec(rest)[0];
        rest = rest.slice(location.length);
        let descriptor = '';
        if (location.endsWith(',')) candidates.push({ url: location.replace(/,+$/, ''), descriptor });
        else {
          const end = rest.indexOf(',');
          descriptor = (end < 0 ? rest : rest.slice(0, end)).trim();
          rest = end < 0 ? '' : rest.slice(end + 1);
          candidates.push({ url: location, descriptor });
        }
      }
      return candidates;
    }
    function srcset(value) {
      const candidates = parseSrcset(value);
      if (!candidates.length) return null;
      const out = [];
      for (const candidate of candidates) {
        const location = imageURL(candidate.url);
        if (!location || !/^(\d{1,5}w|\d{1,3}(\.\d{1,3})?x)?$/.test(candidate.descriptor)) return null;
        out.push(candidate.descriptor ? `${location} ${candidate.descriptor}` : location);
      }
      return out.join(', ');
    }

    function attributes(name, source) {
      const allowed = ATTRIBUTES[name] || {}, seen = new Set(), out = [];
      let unsafeURL = false;
      for (const match of source.matchAll(ATTRIBUTE_PARTS)) {
        const key = match[1].toLowerCase();
        if (seen.has(key)) continue; // As in the HTML parser, the first duplicate wins.
        seen.add(key);
        const rule = Object.prototype.hasOwnProperty.call(allowed, key) ? allowed[key] : Object.prototype.hasOwnProperty.call(GLOBAL, key) ? GLOBAL[key] : null;
        if (!rule) continue;
        if (rule === 'boolean') { out.push(key); continue; }
        const raw = match[2] ?? match[3] ?? match[4];
        if (raw === undefined) continue;
        const value = decode(raw);
        const safe = rule === 'link' ? linkURL(value) : rule === 'image' ? imageURL(value) : rule === 'srcset' ? srcset(value) : rule(value);
        if (safe === null) { if (rule === 'link' || rule === 'image') unsafeURL = true; continue; }
        out.push(`${key}="${escape(safe)}"`);
      }
      return { html: out.length ? ' ' + out.join(' ') : '', unsafeURL };
    }

    // Split author HTML into text, tags, comments and other markup using CommonMark's grammar.
    function scan(source, block) {
      const pieces = [];
      let position = 0, textStart = 0;
      const flush = end => { if (end > textStart) pieces.push({ type: 'text', raw: source.slice(textStart, end) }); };
      // A construct can only match if its terminator occurs later; this keeps scanning linear
      // for inputs full of unterminated "<!--" or "<?" openers.
      const last = { open: '>', close: '>', comment: '-->', processing: '?>', cdata: ']]>', declaration: '>' };
      for (const key in last) last[key] = source.lastIndexOf(last[key]);
      while ((position = source.indexOf('<', position)) !== -1) {
        let piece = null, match;
        for (const [kind, regex] of [['open', OPEN_TAG], ['close', CLOSE_TAG], ['comment', COMMENT], ['processing', PROCESSING], ['cdata', CDATA], ['declaration', DECLARATION]]) {
          if (position > last[kind]) continue;
          regex.lastIndex = position;
          if ((match = regex.exec(source))) { piece = { type: ['open', 'close', 'comment'].includes(kind) ? kind : 'other', raw: match[0], match }; break; }
        }
        if (!piece) { position++; continue; }
        flush(position);
        position += piece.raw.length;
        if (piece.type === 'open' || piece.type === 'close') piece.name = piece.match[1].toLowerCase();
        if (block && piece.type === 'open' && RAW_TEXT.has(piece.name)) {
          // The whole raw-text element, through its close tag (or the block's end), is text.
          const close = new RegExp(`</${piece.name}${WS}*>`, 'i').exec(source.slice(position));
          const end = close ? position + close.index + close[0].length : source.length;
          piece = { type: 'other', raw: source.slice(position - piece.raw.length, end) };
          position = end;
        }
        pieces.push(piece);
        textStart = position;
      }
      flush(source.length);
      return pieces;
    }

    // A stack of author elements. depth = trusted nesting at which the element was opened; it
    // only closes at that same depth and is closed before trusted structure around it closes.
    function closeFrom(stack, index) {
      let html = '';
      while (stack.length > index) { const entry = stack.pop(); if (!entry.phantom) html += `</${entry.name}>`; }
      return html;
    }
    function closeDeeper(stack, depth) {
      const index = stack.findIndex(entry => entry.depth >= depth);
      return index < 0 ? '' : closeFrom(stack, index);
    }
    function tag(piece, stack, depth, scope, phrasingOnly = false) {
      if (piece.type === 'text') return escapeText(piece.raw);
      if (piece.type === 'comment') return ''; // Hidden, as on GitHub.
      if (piece.type === 'other' || !ALLOWED.has(piece.name)) return escape(piece.raw);
      const name = piece.name;
      if (phrasingOnly && !PHRASING.has(name)) return piece.type === 'close' ? '' : escape(piece.raw);
      if (piece.type === 'close') {
        if (VOID.has(name)) return '';
        for (let index = stack.length - 1; index >= 0; index--) {
          const entry = stack[index];
          if (entry.depth !== depth) break;
          if (entry.name === name) return closeFrom(stack, index);
        }
        return ''; // An unmatched close tag must not close trusted structure.
      }
      const { html, unsafeURL } = attributes(name, piece.match[2]);
      if (name === 'a' && unsafeURL) { // An unsafe link keeps its content as plain text.
        if (!piece.match[3]) stack.push({ name, depth, scope, inline: true, phantom: true });
        return '';
      }
      if (VOID.has(name)) return `<${name}${html}>`;
      if (piece.match[3]) return `<${name}${html}></${name}>`;
      stack.push({ name, depth, scope, inline: !CONTAINERS.has(name) });
      return `<${name}${html}>`;
    }

    function authorToken(state, content, block) {
      const token = new state.Token('author_html', '', 0);
      token.content = content; token.block = block;
      return token;
    }

    // Inline run: every author tag is closed at the end of its own paragraph, heading or cell.
    function inline(state, children) {
      const out = [], stack = [];
      let depth = 0, raw = null;
      for (const child of children) {
        if (child.nesting === -1) {
          const closing = closeDeeper(stack, depth);
          if (closing) out.push(authorToken(state, closing, false));
          depth--;
        }
        if (child.type === 'html_inline') {
          const pieces = scan(child.content, false), piece = pieces[0];
          if (raw) { // Inside <script>, <svg>, ...: show everything up to the matching close tag.
            if (pieces.length === 1 && piece.type === 'close' && piece.name === raw) raw = null;
            out.push(authorToken(state, escape(child.content), false));
            continue;
          }
          if (pieces.length === 1 && piece.type === 'open' && RAW_TEXT.has(piece.name)) {
            if (!piece.match[3]) raw = piece.name;
            out.push(authorToken(state, escape(child.content), false));
            continue;
          }
          out.push(authorToken(state, pieces.map(piece => tag(piece, stack, depth, null, true)).join(''), false));
          continue;
        }
        out.push(child);
        if (child.nesting === 1) depth++;
      }
      const closing = closeFrom(stack, 0);
      if (closing) out.push(authorToken(state, closing, false));
      return out;
    }

    function rule(state) {
      const out = [], stack = [];
      let depth = 0, scope = 0;
      for (const token of state.tokens) {
        if (token.type === 'footnote_block_open') {
          const closing = closeFrom(stack, 0); // The footnote section stays a top-level section.
          if (closing) out.push(authorToken(state, closing, true));
        }
        if (token.nesting === -1) {
          const closing = closeDeeper(stack, depth);
          if (closing) out.push(authorToken(state, closing, true));
          depth--;
        }
        if (token.type === 'html_block') {
          scope++;
          let html = scan(token.content, true).map(piece => tag(piece, stack, depth, scope)).join('');
          // Inline elements end with their block; containers such as <details> may span blocks.
          const index = stack.findIndex(entry => entry.scope === scope && entry.inline);
          if (index >= 0) {
            const trailing = /\n*$/.exec(html)[0];
            html = html.slice(0, html.length - trailing.length) + closeFrom(stack, index) + trailing;
          }
          if (html.trim()) out.push(authorToken(state, html, true)); // A comment-only block leaves nothing.
          continue;
        }
        if (token.type === 'inline' && token.children) token.children = inline(state, token.children);
        out.push(token);
        if (token.nesting === 1) depth++;
      }
      const closing = closeFrom(stack, 0);
      if (closing) out.push(authorToken(state, closing + '\n', true));
      state.tokens = out;
    }

    return { rule, parseSrcset, imageURL, linkURL };
  }

  function installHTMLPolicy(md) {
    const policy = create(md);
    md.set({ html: true });
    // Pushed last: runs after footnotes, alerts and reader metadata have shaped the token stream.
    md.core.ruler.push('author_html', policy.rule);
    md.renderer.rules.author_html = (tokens, index) => tokens[index].content;
    // Fail closed: anything that escaped the policy is shown as text, never as markup.
    md.renderer.rules.html_block = (tokens, index) => md.utils.escapeHtml(tokens[index].content);
    md.renderer.rules.html_inline = (tokens, index) => md.utils.escapeHtml(tokens[index].content);
    return policy;
  }

  window.installHTMLPolicy = installHTMLPolicy;
})();
