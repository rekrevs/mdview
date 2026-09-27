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

  md.core.ruler.after('inline', 'reader_metadata', state => {
    const used = new Set();
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
    try { id = decodeURIComponent(String(id).replace(/^#/, '')); } catch (_) { return false; }
    if (!id) { window.scrollTo(0, 0); return true; }
    const target = document.getElementById(id);
    if (!target || !root.contains(target)) return false;
    target.scrollIntoView({ block: 'start' });
    return true;
  }

  function indexText() {
    let text = ''; const segments = [];
    const blocks = new Set(['P', 'DIV', 'PRE', 'LI', 'BLOCKQUOTE', 'TR', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6']);
    function visit(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        segments.push({ node, start: text.length, end: text.length + node.data.length }); text += node.data; return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.matches('button,input,[data-math]')) { text += '\n'; return; }
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
    holder.querySelectorAll('button').forEach(node => node.remove());
    holder.querySelectorAll('[data-math]').forEach(node => node.replaceWith(document.createTextNode(node.classList.contains('math-display') ? '\n\n' + node.dataset.math + '\n\n' : node.dataset.math)));
    holder.querySelectorAll('input[type="checkbox"]').forEach(node => node.replaceWith(document.createTextNode(node.checked ? '[x] ' : '[ ] ')));
    holder.querySelectorAll('img').forEach(node => node.replaceWith(document.createTextNode(node.alt)));
    return holder;
  }
  function plainText(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      // Ignore HTML formatter line breaks between blocks, preserving every code byte.
      if (/^\s*\n\s*$/.test(node.data) && ['DIV', 'MAIN', 'TABLE', 'THEAD', 'TBODY', 'TR', 'UL', 'OL', 'BLOCKQUOTE'].includes(node.parentElement?.tagName)) return '';
      return node.data;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    if (node.tagName === 'BR') return '\n';
    let text = Array.from(node.childNodes, plainText).join('');
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
    for (const node of rich.querySelectorAll('*')) {
      const alignment = node.style.textAlign;
      node.removeAttribute('style');
      if (styles[node.tagName]) node.setAttribute('style', styles[node.tagName]);
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
