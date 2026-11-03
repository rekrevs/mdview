/* mdview's offline document pipeline. Document HTML is deliberately treated as text. */
(() => {
  'use strict';
  const root = document.getElementById('document');
  const post = message => window.webkit?.messageHandlers?.reader?.postMessage(message);
  const md = window.markdownit({ html: false, linkify: true, typographer: false });
  const escape = md.utils.escapeHtml;
  let lastMarkdown = null, lastBaseURL = null, documentURL = null, headingList = [];
  let findQuery = '', findRanges = [], findIndex = -1;

  function mathHTML(source, display, originalSource) {
    const original = originalSource || (display ? `$$${source}$$` : `$${source}$`);
    let html;
    try {
      html = window.katex.renderToString(source, { displayMode: display, throwOnError: true,
        trust: false, strict: 'warn', maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml' });
    } catch (error) {
      html = `<span class="math-error" title="${escape(error.message)}">${escape(original)}</span>`;
    }
    return `<${display ? 'div' : 'span'} class="math-${display ? 'display' : 'inline'}" data-math="${escape(original)}">${html}</${display ? 'div' : 'span'}>`;
  }

  // These rules run on the original source, before Markdown consumes TeX escapes,
  // asterisks or underscores. Code spans/fences and escaped dollars remain literal.
  md.inline.ruler.before('escape', 'math', (state, silent) => {
    const start = state.pos;
    if (state.src[start] !== '$') return false;
    const double = state.src[start + 1] === '$';
    const width = double ? 2 : 1;
    const first = state.src[start + width];
    if (!first || (!double && /\s/.test(first))) return false;
    let end = start + width;
    while ((end = state.src.indexOf('$'.repeat(width), end)) !== -1) {
      let slashes = 0;
      for (let i = end - 1; i >= 0 && state.src[i] === '\\'; i--) slashes++;
      if (slashes % 2) { end += width; continue; }
      if (!double && (state.src[end + 1] === '$' || /\s/.test(state.src[end - 1]))) return false;
      const content = state.src.slice(start + width, end);
      if (!double && (content.includes('\n') || /\d/.test(state.src[end + 1] || ''))) return false;
      if (!content.trim() || (!double && content.includes('`') && !(content.startsWith('`') && content.endsWith('`')))) return false;
      if (!silent) {
        const token = state.push('math_inline', '', 0);
        token.content = !double && content.startsWith('`') && content.endsWith('`') ? content.slice(1, -1) : content;
        token.meta = { display: double, original: '$'.repeat(width) + content + '$'.repeat(width) };
      }
      state.pos = end + width;
      return true;
    }
    return false;
  });
  md.renderer.rules.math_inline = (tokens, index) => {
    const token = tokens[index];
    // Inline $$ still participates in the paragraph's continuous inline flow.
    if (token.meta.display) return mathHTML(token.content, false, `$$${token.content}$$`);
    return mathHTML(token.content, false, token.meta.original);
  };
  md.block.ruler.before('fence', 'math_block', (state, startLine, endLine, silent) => {
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const first = state.src.slice(start, state.eMarks[startLine]);
    if (!first.startsWith('$$') || state.sCount[startLine] - state.blkIndent >= 4) return false;
    let content = first.slice(2), next = startLine;
    let close = content.indexOf('$$');
    if (close >= 0 && content.slice(close + 2).trim()) return false;
    if (close < 0) {
      const lines = [content];
      for (next = startLine + 1; next < endLine; next++) {
        if (state.sCount[next] < state.blkIndent && state.src.slice(state.bMarks[next], state.eMarks[next]).trim()) break;
        const line = state.src.slice(state.bMarks[next] + state.tShift[next], state.eMarks[next]);
        close = line.indexOf('$$');
        if (close >= 0) {
          if (line.slice(close + 2).trim()) return false;
          lines.push(line.slice(0, close)); break;
        }
        lines.push(line);
      }
      if (close < 0) return false;
      content = lines.join('\n');
    } else content = content.slice(0, close);
    if (silent) return true;
    const token = state.push('math_block', 'div', 0);
    token.block = true; token.content = content; token.map = [startLine, next + 1];
    state.line = next + 1;
    return true;
  }, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
  md.renderer.rules.math_block = (tokens, index) => mathHTML(tokens[index].content, true) + '\n';

  function codeHTML(source, language) {
    let highlighted = escape(source);
    if (language && window.hljs.getLanguage(language)) {
      try { highlighted = window.hljs.highlight(source, { language, ignoreIllegals: true }).value; } catch (_) { /* Plain text is always safe. */ }
    }
    return `<div class="code-block"><button class="copy-code" type="button" aria-label="Copy code">Copy</button><pre><code${language ? ` class="language-${escape(language)}"` : ''}>${highlighted}</code></pre></div>\n`;
  }
  md.renderer.rules.fence = (tokens, index) => {
    const token = tokens[index];
    const language = token.info.trim().split(/\s+/)[0].toLowerCase();
    return language === 'math' ? mathHTML(token.content, true) + '\n' : codeHTML(token.content, language);
  };
  md.renderer.rules.code_block = (tokens, index) => codeHTML(tokens[index].content, '');

  // Leading front matter. A deliberately small YAML subset (flat keys, scalars and
  // scalar lists) becomes a GitHub-style table; anything else stays visible as source.
  md.core.ruler.after('normalize', 'strip_bom', state => { state.src = state.src.replace(/^\uFEFF/, ''); });
  md.block.ruler.before('table', 'front_matter', (state, startLine, endLine, silent) => {
    if (startLine !== 0 || state.parentType !== 'root' || state.bMarks[0] !== 0) return false;
    const line = number => state.src.slice(state.bMarks[number], state.eMarks[number]);
    const open = /^(---|\+\+\+)[ \t]*$/.exec(line(0));
    if (!open) return false;
    const kind = open[1] === '+++' ? 'toml' : 'yaml';
    const closer = kind === 'toml' ? /^\+\+\+[ \t]*$/ : /^(---|\.\.\.)[ \t]*$/;
    let close = 1;
    while (close < endLine && !closer.test(line(close))) close++;
    if (close >= endLine) return false;
    if (silent) return true;
    const token = state.push('front_matter', '', 0);
    token.block = true; token.content = state.getLines(1, close, 0, false);
    token.meta = { kind }; token.map = [0, close + 1];
    state.line = close + 1;
    return true;
  });
  function frontMatterScalar(text) {
    text = text.trim();
    let match;
    if (text.startsWith('"')) return (match = /^"([^"\\]*)"\s*(?:#.*)?$/.exec(text)) ? match[1] : null;
    if (text.startsWith("'")) return (match = /^'((?:[^']|'')*)'\s*(?:#.*)?$/.exec(text)) ? match[1].replace(/''/g, "'") : null;
    text = text.replace(/(^|\s+)#.*$/, '').trim();
    if (/^[&*!{}[\]|>%@`,]/.test(text) || /:(\s|$)/.test(text)) return null;
    return text;
  }
  function parseFrontMatter(content) {
    const lines = content.replace(/\n$/, '').split('\n'), pairs = [], keys = new Set();
    for (let i = 0; i < lines.length; i++) {
      const text = lines[i];
      if (!text.trim() || /^\s*#/.test(text)) continue;
      const match = /^(?:"([^"\\]*)"|'((?:[^']|'')*)'|([^\s:#'"&*!{}[\]|>%@`,-][^:]*?))[ \t]*:(?:[ \t]+(.*?))?[ \t]*$/.exec(text);
      if (!match) return null;
      const key = match[1] ?? (match[2] !== undefined ? match[2].replace(/''/g, "'") : match[3]);
      if (keys.has(key)) return null;
      keys.add(key);
      const raw = match[4] ?? '';
      let value;
      if (/^(#.*)?$/.test(raw)) {
        value = ''; let indent = null;
        while (i + 1 < lines.length) {
          const item = /^([ ]*)-(?:[ \t]+(.*))?$/.exec(lines[i + 1]);
          if (!item) { if (!lines[i + 1].trim()) { i++; continue; } break; }
          if (indent === null) { indent = item[1]; value = []; } else if (item[1] !== indent) return null;
          const scalar = frontMatterScalar(item[2] ?? '');
          if (scalar === null) return null;
          value.push(scalar); i++;
        }
      } else if (raw.startsWith('[')) {
        const list = /^\[([^[\]{}"']*)\]\s*(?:#.*)?$/.exec(raw);
        if (!list) return null;
        value = list[1].trim() ? list[1].split(',').map(frontMatterScalar) : [];
        if (value.some(item => item === null)) return null;
      } else if ((value = frontMatterScalar(raw)) === null) return null;
      pairs.push([key, value]);
    }
    return pairs.length ? pairs : null;
  }
  md.renderer.rules.front_matter = (tokens, index) => {
    const { content, meta } = tokens[index];
    if (!content.trim()) return '';
    const pairs = meta.kind === 'yaml' ? parseFrontMatter(content) : null;
    if (!pairs) return `<div class="front-matter-source">${codeHTML(content, meta.kind).trim()}</div>\n`;
    const cell = value => Array.isArray(value) ? `<table><tbody><tr>${value.map(item => `<td>${escape(item)}</td>`).join('')}</tr></tbody></table>` : escape(value);
    return `<table class="front-matter"><thead><tr>${pairs.map(([key]) => `<th>${escape(key)}</th>`).join('')}</tr></thead><tbody><tr>${pairs.map(([, value]) => `<td>${cell(value)}</td>`).join('')}</tr></tbody></table>\n`;
  };

  // GitHub alerts: a top-level quote whose first line is only [!TYPE] (cmark-gfm behaviour,
  // checked against GitHub's renderer). Icon paths come from vendor/octicons (Primer Octicons, MIT).
  const alertIcons = {
    note: 'M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z',
    tip: 'M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z',
    important: 'M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z',
    warning: 'M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z',
    caution: 'M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z'
  };
  md.core.ruler.after('block', 'github_alerts', state => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const open = tokens[i];
      if (open.type !== 'blockquote_open' || open.level !== 0 || tokens[i + 1]?.type !== 'paragraph_open') continue;
      const inline = tokens[i + 2];
      const match = /^\\?\[!(note|tip|important|warning|caution)\][ \t]*(?:\n|$)/i.exec(inline.content);
      if (!match) continue;
      const rest = inline.content.slice(match[0].length);
      // A marker without any following content stays an ordinary quote, as on GitHub.
      if (!rest && tokens[i + 4]?.type === 'blockquote_close') continue;
      if (rest) inline.content = rest; else tokens.splice(i + 1, 3);
      let depth = 0, close = i;
      while (++close < tokens.length) {
        if (tokens[close].type === 'blockquote_open') depth++;
        else if (tokens[close].type === 'blockquote_close' && depth-- === 0) break;
      }
      const kind = match[1].toLowerCase();
      open.type = 'alert_open'; open.tag = 'div'; open.attrs = [['class', `markdown-alert markdown-alert-${kind}`]];
      tokens[close].type = 'alert_close'; tokens[close].tag = 'div';
      const title = new state.Token('alert_title', '', 0);
      title.block = true; title.meta = { kind }; title.level = 1;
      tokens.splice(i + 1, 0, title);
    }
  });
  md.renderer.rules.alert_title = (tokens, index) => {
    const kind = tokens[index].meta.kind;
    return `<p class="markdown-alert-title"><svg class="octicon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false"><path d="${alertIcons[kind]}"></path></svg>${kind[0].toUpperCase() + kind.slice(1)}</p>\n`;
  };

  // Footnotes (markdown-it-footnote) with cmark-gfm/GitHub label rules and markup.
  md.use(window.markdownitFootnote);
  md.disable('footnote_inline'); // ^[inline] notes are not GitHub syntax.
  const footnoteLabel = label => String(label).toUpperCase().toLowerCase();
  md.core.ruler.after('block', 'footnote_labels', state => {
    if (!state.env.footnotes?.refs) return;
    const refs = {}, seen = new Set();
    state.tokens.forEach((token, index) => {
      if (token.type !== 'footnote_reference_open') return;
      const label = footnoteLabel(token.meta.label);
      // The first definition wins; a later duplicate is parked under an unreachable label.
      if (seen.has(label)) token.meta.label = `\u0000duplicate-${index}`;
      else { seen.add(label); token.meta.label = label; refs[':' + label] = -1; }
    });
    const key = property => typeof property === 'string' && property.startsWith(':') ? ':' + footnoteLabel(property.slice(1)) : property;
    state.env.footnotes.refs = new Proxy(refs, {
      get: (target, property) => Object.prototype.hasOwnProperty.call(target, key(property)) ? target[key(property)] : undefined,
      set: (target, property, value) => { target[key(property)] = value; return true; }
    });
  });
  md.core.ruler.before('footnote_tail', 'footnote_list_labels', state => {
    state.env.footnotes?.list?.forEach(item => { if (item.label !== undefined) item.label = footnoteLabel(item.label); });
  });
  const footnoteIds = (label, subId) => ({ item: `fn-${label}`, ref: subId > 0 ? `fnref-${label}-${subId + 1}` : `fnref-${label}` });
  md.renderer.rules.footnote_ref = (tokens, index) => {
    const { id, subId, label } = tokens[index].meta, ids = footnoteIds(footnoteLabel(label), subId);
    return `<sup class="footnote-ref"><a href="#${escape(encodeURIComponent(ids.item))}" id="${escape(ids.ref)}" data-footnote-ref aria-describedby="footnote-label">${id + 1}</a></sup>`;
  };
  md.renderer.rules.footnote_block_open = () => '<section class="footnotes" data-footnotes>\n<h2 id="footnote-label" class="sr-only">Footnotes</h2>\n<ol>\n';
  md.renderer.rules.footnote_block_close = () => '</ol>\n</section>\n';
  md.renderer.rules.footnote_open = (tokens, index) => `<li id="${escape(footnoteIds(tokens[index].meta.label, 0).item)}" class="footnote-item">\n`;
  md.renderer.rules.footnote_anchor = (tokens, index) => {
    const { id, subId, label } = tokens[index].meta, ids = footnoteIds(label, subId);
    const reference = subId > 0 ? `${id + 1}-${subId + 1}` : `${id + 1}`;
    return ` <a href="#${escape(encodeURIComponent(ids.ref))}" class="footnote-backref" data-footnote-backref aria-label="Back to reference ${reference}">↩︎${subId > 0 ? `<sup>${subId + 1}</sup>` : ''}</a>`;
  };

  // Runs after footnote_tail so unused definitions never reach the outline.
  md.core.ruler.after('footnote_tail', 'reader_metadata', state => {
    const used = new Set(['footnote-label']);
    for (const item of state.env.footnotes?.list || []) {
      if (item.label === undefined) continue;
      used.add(footnoteIds(item.label, 0).item);
      for (let sub = 0; sub < Math.max(1, item.count); sub++) used.add(footnoteIds(item.label, sub).ref);
    }
    state.env.headings = [];
    for (let i = 0; i < state.tokens.length; i++) {
      const token = state.tokens[i];
      if (token.type === 'heading_open') {
        const inline = state.tokens[i + 1];
        const title = (inline.children || []).filter(t => !['html_inline', 'link_open', 'link_close'].includes(t.type)).map(t => t.type === 'image' ? t.content : t.content || '').join('');
        const slug = title.toLowerCase().replace(/[^\p{L}\p{N}\p{M}\s_-]/gu, '').replace(/\s/g, '-') || 'section';
        let id = slug, suffix = 0;
        while (used.has(id)) id = `${slug}-${++suffix}`;
        used.add(id); token.attrSet('id', id);
        state.env.headings.push({ id, title, level: Number(token.tag.slice(1)) });
      }
      if (token.type === 'inline' && state.tokens[i - 1]?.type === 'paragraph_open' && state.tokens[i - 2]?.type === 'list_item_open') {
        const first = token.children?.[0];
        const match = first?.type === 'text' && /^\[([ xX])\](?:\s|$)/.exec(first.content);
        if (match) {
          first.content = first.content.slice(match[0].length);
          const checkbox = new state.Token('html_inline', '', 0);
          checkbox.content = `<input class="task-checkbox" type="checkbox" disabled${match[1] !== ' ' ? ' checked' : ''} aria-label="${match[1] !== ' ' ? 'Completed' : 'Not completed'}">`;
          token.children.unshift(checkbox); state.tokens[i - 2].attrJoin('class', 'task-list-item');
        }
      }
    }
  });

  function imageURL(source, baseURL) {
    try {
      const url = new URL(source, baseURL || 'file:///');
      if (url.protocol === 'file:' && (!url.hostname || url.hostname === 'localhost')) return 'mdview-image://local' + url.pathname;
      if (['https:', 'http:', 'data:'].includes(url.protocol)) return url.href;
    } catch (_) { /* A broken image gets a visible alt-text fallback. */ }
    return '';
  }

  function clearFind() {
    if (window.CSS?.highlights) {
      CSS.highlights.delete('search-results'); CSS.highlights.delete('search-active');
    }
    findRanges = []; findIndex = -1;
  }

  function render(markdown, options = {}) {
    markdown = String(markdown ?? '');
    const baseURL = options.baseURL || '';
    documentURL = options.documentURL || null;
    if (markdown === lastMarkdown && baseURL === lastBaseURL) {
      post({ type: 'rendered' }); return { headings: headingList, changed: false };
    }
    const oldScroll = window.scrollY;
    clearFind();
    const env = {};
    root.innerHTML = md.render(markdown, env);
    headingList = env.headings;
    root.querySelectorAll('img').forEach(img => {
      img.referrerPolicy = 'no-referrer';
      img.addEventListener('error', () => {
        const fallback = document.createElement('span'); fallback.className = 'image-error';
        fallback.textContent = img.alt ? `Image unavailable: ${img.alt}` : 'Image unavailable';
        img.replaceWith(fallback);
      }, { once: true });
      img.src = imageURL(img.getAttribute('src'), baseURL);
    });
    lastMarkdown = markdown; lastBaseURL = baseURL;
    window.scrollTo(0, oldScroll);
    if (findQuery) find(findQuery, 1, true);
    post({ type: 'headings', headings: headingList });
    post({ type: 'rendered' });
    return { headings: headingList, changed: true };
  }

  function scrollToHeading(id) {
    const raw = String(id ?? '').replace(/^#/, '');
    if (!raw) { window.scrollTo(0, 0); return true; }
    // Try the id as written, then percent-decoded, then without GitHub's user-content- prefix.
    const candidates = [raw];
    try { candidates.push(decodeURIComponent(raw)); } catch (_) { /* Keep the raw candidate. */ }
    for (const candidate of [...candidates]) if (candidate.startsWith('user-content-')) candidates.push(candidate.slice(13));
    for (const candidate of candidates) {
      const target = candidate && document.getElementById(candidate);
      if (target && root.contains(target)) { target.scrollIntoView({ block: 'start' }); return true; }
    }
    return false;
  }

  function indexText() {
    let text = ''; const segments = [];
    const blocks = new Set(['P', 'DIV', 'PRE', 'LI', 'BLOCKQUOTE', 'TR', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6']);
    function visit(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        segments.push({ node, start: text.length, end: text.length + node.data.length }); text += node.data; return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.matches('button,input,[data-math],.sr-only')) { text += '\n'; return; }
      const block = blocks.has(node.tagName);
      if (block && text && !text.endsWith('\n')) text += '\n';
      for (const child of node.childNodes) visit(child);
      if (block || node.tagName === 'BR' || node.tagName === 'TD' || node.tagName === 'TH') text += '\n';
    }
    visit(root); return { text, segments };
  }

  function find(query, direction = 1, reset = false) {
    query = String(query || '');
    if (query !== findQuery || reset) {
      clearFind(); findQuery = query;
      if (query) {
        const { text, segments } = indexText();
        const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'giu');
        for (const match of text.matchAll(pattern)) {
          const start = match.index, end = start + match[0].length;
          const first = segments.find(s => s.start <= start && s.end > start);
          const last = segments.find(s => s.start < end && s.end >= end);
          if (!first || !last) continue;
          const range = document.createRange(); range.setStart(first.node, start - first.start); range.setEnd(last.node, end - last.start);
          findRanges.push(range);
        }
      }
    }
    if (!findRanges.length) return { count: 0, index: 0 };
    findIndex = reset || findIndex < 0 ? (direction < 0 ? findRanges.length - 1 : 0) : (findIndex + (direction < 0 ? -1 : 1) + findRanges.length) % findRanges.length;
    const active = findRanges[findIndex];
    if (window.CSS?.highlights && window.Highlight) {
      CSS.highlights.set('search-results', new Highlight(...findRanges));
      CSS.highlights.set('search-active', new Highlight(active));
    } else {
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(active);
    }
    active.startContainer.parentElement?.scrollIntoView({ block: 'center' });
    return { count: findRanges.length, index: findIndex + 1 };
  }

  function selectionContents() {
    const selection = window.getSelection();
    if (!selection?.rangeCount || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0).cloneRange();
    if (!range.intersectsNode(root)) return null;
    // WebKit Select All can anchor the range on BODY instead of MAIN.
    const documentRange = document.createRange(); documentRange.selectNodeContents(root);
    if (range.compareBoundaryPoints(Range.START_TO_START, documentRange) < 0) range.setStart(root, 0);
    if (range.compareBoundaryPoints(Range.END_TO_END, documentRange) > 0) range.setEnd(root, root.childNodes.length);
    // Selecting any visual part of a formula copies that formula's source once.
    for (const boundary of ['start', 'end']) {
      const node = range[boundary + 'Container'];
      const math = (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)?.closest('[data-math]');
      if (math) boundary === 'start' ? range.setStartBefore(math) : range.setEndAfter(math);
    }
    const holder = document.createElement('div');
    let fragment = range.cloneContents();
    // cloneContents omits the common ancestor: a word selected inside STRONG,
    // H1 or PRE otherwise becomes an unformatted text node on the clipboard.
    let context = range.commonAncestorContainer;
    if (context.nodeType === Node.TEXT_NODE) context = context.parentElement;
    while (context && context !== root && root.contains(context)) {
      const wrapper = context.cloneNode(false); wrapper.append(fragment);
      fragment = wrapper; context = context.parentElement;
    }
    holder.append(fragment);
    // Preserve the first visible ordinal when copying only the tail of a list.
    const lists = Array.from(root.querySelectorAll('ol')).filter(list => range.intersectsNode(list));
    holder.querySelectorAll('ol').forEach((copy, index) => {
      const source = lists[index];
      if (!source) return;
      const children = Array.from(source.children).filter(node => node.tagName === 'LI');
      const offset = children.findIndex(node => range.intersectsNode(node));
      if (offset >= 0) copy.start = (source.hasAttribute('start') ? Number(source.getAttribute('start')) : 1) + offset;
    });
    holder.querySelectorAll('button,svg.octicon,.sr-only').forEach(node => node.remove());
    holder.querySelectorAll('.footnote-backref').forEach(node => {
      const before = node.previousSibling;
      if (before?.nodeType === Node.TEXT_NODE) before.data = before.data.replace(/[ \t]+$/, '');
      node.remove();
    });
    // Footnote items copy with their visible number, e.g. "[1] Note text".
    const footnoteItems = Array.from(root.querySelectorAll('section.footnotes > ol > li'));
    holder.querySelectorAll('section.footnotes li[id], li.footnote-item').forEach(copy => {
      const number = footnoteItems.findIndex(item => item.id === copy.id) + 1;
      if (number) copy.dataset.footnoteNumber = String(number);
    });
    holder.querySelectorAll('[data-math]').forEach(node => node.replaceWith(document.createTextNode(node.classList.contains('math-display') ? '\n\n' + node.dataset.math + '\n\n' : node.dataset.math)));
    holder.querySelectorAll('input[type="checkbox"]').forEach(node => node.replaceWith(document.createTextNode(node.checked ? '[x] ' : '[ ] ')));
    holder.querySelectorAll('img').forEach(node => node.replaceWith(document.createTextNode(node.alt)));
    return holder;
  }
  function plainText(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      // Ignore HTML formatter line breaks between blocks, preserving every code byte.
      if (/^\s*\n\s*$/.test(node.data) && (['DIV', 'MAIN', 'TABLE', 'THEAD', 'TBODY', 'TR', 'UL', 'OL', 'BLOCKQUOTE', 'SECTION'].includes(node.parentElement?.tagName) || node.parentElement?.classList.contains('footnote-item'))) return '';
      return node.data;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    if (node.tagName === 'BR') return '\n';
    let text = Array.from(node.childNodes, plainText).join('');
    if (node.matches('sup.footnote-ref')) return `[${text}]`;
    if (node.dataset.footnoteNumber) text = `[${node.dataset.footnoteNumber}] ` + text.replace(/^\s+/, '').replace(/\n+$/, '');
    if (['TD', 'TH'].includes(node.tagName)) text += '\t';
    else if (node.tagName === 'TR') text = text.replace(/\t$/, '') + '\n';
    else if (['P', 'PRE', 'UL', 'OL', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6'].includes(node.tagName)) text += '\n\n';
    else if (node.tagName === 'LI') text += '\n';
    return text;
  }
  function richHTML(holder) {
    const rich = holder.cloneNode(true);
    // Portable, light-document styles, not WebKit's theme, zoom or class names.
    // Keep native heading/list/link semantics for the receiving application.
    const styles = {
      TABLE: 'border-collapse:collapse',
      TH: 'border:1px solid #b7b7b7;padding:6px 10px;background-color:#f2f2f2;font-weight:bold',
      TD: 'border:1px solid #b7b7b7;padding:6px 10px',
      PRE: 'font-family:"Courier New",monospace;font-size:10pt;white-space:pre;background-color:#f5f5f5;color:#222222;padding:10px',
      CODE: 'font-family:"Courier New",monospace;font-size:10pt;white-space:pre-wrap',
      BLOCKQUOTE: 'border-left:3px solid #b7b7b7;padding-left:12px;margin-left:12px',
      STRONG: 'font-weight:bold', EM: 'font-style:italic', S: 'text-decoration:line-through'
    };
    // Alerts and footnotes are recognised by class, so collect their styles before classes go.
    const alertColors = { note: '#0969da', tip: '#1a7f37', important: '#8250df', warning: '#9a6700', caution: '#d1242f' };
    const classStyles = new Map();
    rich.querySelectorAll('.markdown-alert').forEach(alert => {
      const color = alertColors[/\bmarkdown-alert-(note|tip|important|warning|caution)\b/.exec(alert.className)?.[1]] || '#57606a';
      classStyles.set(alert, `border-left:4px solid ${color};padding:4px 12px;margin:0 0 12px`);
      alert.querySelectorAll(':scope > .markdown-alert-title').forEach(title => classStyles.set(title, `font-weight:bold;color:${color}`));
    });
    rich.querySelectorAll('section.footnotes').forEach(section => classStyles.set(section, 'border-top:1px solid #d0d7de;margin-top:16px;padding-top:8px;font-size:smaller;color:#57606a'));
    for (const node of rich.querySelectorAll('*')) {
      const alignment = node.style.textAlign;
      node.removeAttribute('style');
      if (styles[node.tagName]) node.setAttribute('style', styles[node.tagName]);
      if (classStyles.has(node)) node.setAttribute('style', classStyles.get(node));
      // In-document footnote anchors mean nothing after pasting; the number is enough.
      if (node.matches('a[data-footnote-ref]')) { node.replaceWith(...node.childNodes); continue; }
      if (['TD', 'TH'].includes(node.tagName) && ['left', 'right', 'center'].includes(alignment)) {
        node.style.textAlign = alignment; node.setAttribute('align', alignment);
      }
      if (node.tagName === 'A') {
        try {
          const target = new URL(node.getAttribute('href'), documentURL || lastBaseURL || undefined);
          if (!['http:', 'https:', 'mailto:', 'file:'].includes(target.protocol)) throw new Error('Unsupported link');
          node.setAttribute('href', target.href);
        } catch (_) { node.removeAttribute('href'); }
      }
      for (const attribute of Array.from(node.attributes)) {
        if (['class', 'id', 'tabindex'].includes(attribute.name) || /^(data-|aria-)/.test(attribute.name)) node.removeAttribute(attribute.name);
      }
    }
    return rich.innerHTML;
  }
  document.addEventListener('copy', event => {
    const holder = selectionContents();
    if (!holder || !event.clipboardData) return;
    event.clipboardData.setData('text/plain', plainText(holder).replace(/\n+$/, ''));
    event.clipboardData.setData('text/html', richHTML(holder));
    event.preventDefault();
  });
  root.addEventListener('click', event => {
    const button = event.target.closest('.copy-code');
    if (button) {
      post({ type: 'copy', text: button.parentElement.querySelector('code').textContent });
      button.textContent = 'Copied'; window.setTimeout(() => { button.textContent = 'Copy'; }, 1200); return;
    }
    const link = event.target.closest('a[href]');
    if (link) {
      event.preventDefault();
      const href = link.getAttribute('href');
      if (href.startsWith('#')) scrollToHeading(href);
      post({ type: 'link', href });
    }
  });
  window.mdview = { render, find, scrollToHeading, setZoom(scale) {
    document.documentElement.style.fontSize = `${16 * Math.max(0.5, Math.min(3, Number(scale) || 1))}px`;
  } };
  post({ type: 'ready' });
})();
