const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const web = path.resolve(__dirname, '../../Sources/Resources/Web');
function reader(options = {}) {
  const dom = new JSDOM('<!doctype html><head></head><main id="document"></main>', { runScripts: 'outside-only', url: 'file:///reader/index.html' });
  const window = dom.window, messages = [];
  window.webkit = { messageHandlers: { reader: { postMessage: message => messages.push(message) } } };
  window.scrollTo = () => {};
  window.scrollBy = (x, y) => { (window.scrolledBy ||= []).push(y); };
  // Appearance stub: tests flip `dark` and fire change listeners like WebKit does.
  const scheme = { matches: !!options.dark, listeners: [], addEventListener(type, listener) { if (type === 'change') this.listeners.push(listener); } };
  window.matchMedia = query => query === '(prefers-color-scheme: dark)' ? scheme : { matches: false, addEventListener() {} };
  window.setDark = dark => { scheme.matches = dark; scheme.listeners.forEach(listener => listener({ matches: dark })); };
  window.HTMLElement.prototype.scrollIntoView = () => {};
  for (const file of ['vendor/markdown-it.min.js', 'vendor/markdown-it-footnote.min.js', 'vendor/markdown-it-emoji.min.js', 'vendor/katex.min.js', 'vendor/highlight.min.js', 'html-policy.js', 'renderer.js']) window.eval(fs.readFileSync(path.join(web, file), 'utf8'));
  const root = window.document.getElementById('document');
  return { window, root, messages, render: (text, options = {}) => window.mdview.render(text, options), close: () => window.close() };
}
function clipboard(r, start, end) {
  const range = r.window.document.createRange();
  if (start) { range.setStart(start, 0); range.setEnd(end, end.length); } else range.selectNodeContents(r.root);
  const selection = r.window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
  const data = {};
  const event = new r.window.Event('copy', { bubbles: true, cancelable: true });
  event.clipboardData = { setData(type, value) { data[type] = value; } };
  r.root.dispatchEvent(event); assert.equal(event.defaultPrevented, true);
  return data;
}
test('review math reproductions preserve TeX before Markdown parsing in every supported context', () => {
  const r = reader();
  const matrix = String.raw`\begin{pmatrix} a & b \\ c & d \end{pmatrix}`;
  r.render(`$$${matrix}$$\n\n$$\nx^2 + y^2\n$$\n\n# Math $x^2$\n\n**bold $a*b*c$**\n\n| Math |\n| --- |\n| $x_i$ |\n\n\`\`\`math\n${matrix}\n\`\`\`\n\n$a$ then $$b$$`);
  assert.equal(r.root.querySelectorAll('[data-math]').length, 8);
  assert.equal(r.root.querySelectorAll('mtable').length, 2);
  assert.equal(r.root.querySelector('mtable').querySelectorAll('mtr').length, 2);
  assert.equal(r.root.querySelector('annotation').textContent, matrix);
  assert.equal(r.root.querySelector('strong [data-math]').dataset.math, '$a*b*c$');
  assert.ok(r.root.querySelector('h1 .katex'));
  assert.ok(r.root.querySelector('td .katex'));
  assert.equal(r.root.querySelectorAll('.math-error').length, 0); r.close();
});
test('escaped dollars, currency and code do not turn into formulas', () => {
  const r = reader();
  r.render(String.raw`Prices \$5 and \$10; $5 and $10; $20.00 plus $30.00. Code: ` + '`$x$`' + '\n\n```tex\n$x$\n```\n\nUnclosed $formula');
  assert.equal(r.root.querySelectorAll('[data-math]').length, 0);
  assert.ok(r.root.textContent.includes('$5 and $10')); r.close();
});
test('nested blocks, images, checkbox states and aligned tables preserve content', () => {
  const r = reader();
  r.render('> # QUOTE HEADING\n>\n> - QUOTE ITEM\n>\n> ```python\n> print("QUOTE CODE")\n> ```\n\n- parent\n\n  ```python\n  print("NESTED CODE")\n  ```\n\n- [ ] waiting\n- [x] complete\n\n| Left | Center | Right |\n| :--- | :---: | ---: |\n| A | B | C |\n\n![Local icon](images/a%20b.png)', { baseURL: 'file:///tmp/report/' });
  assert.ok(r.root.querySelector('blockquote h1'));
  assert.match(r.root.querySelector('blockquote').textContent, /QUOTE ITEM/);
  assert.match(r.root.querySelector('blockquote code').textContent, /QUOTE CODE/);
  assert.match(r.root.querySelector('li code').textContent, /NESTED CODE/);
  const checkboxes = r.root.querySelectorAll('input[type="checkbox"]');
  assert.equal(checkboxes.length, 2); assert.equal(checkboxes[0].checked, false); assert.equal(checkboxes[1].checked, true);
  assert.deepEqual(Array.from(r.root.querySelectorAll('th'), n => n.style.textAlign), ['left', 'center', 'right']);
  assert.equal(r.root.querySelector('img').src, 'mdview-image://local/tmp/report/images/a%20b.png');
  r.root.querySelector('img').dispatchEvent(new r.window.Event('error'));
  assert.match(r.root.querySelector('.image-error').textContent, /Local icon/); r.close();
});
test('copy button preserves code indentation, blank lines and final newline with highlighting', () => {
  const r = reader(), source = '    first = 1\n\n\n    second = 2\n';
  r.render('```python\n' + source + '```');
  assert.equal(r.root.querySelector('code').textContent, source);
  assert.ok(r.root.querySelector('.hljs-number'));
  r.root.querySelector('button').click();
  assert.equal(r.messages.at(-1).type, 'copy'); assert.equal(r.messages.at(-1).text, source); r.close();
});
test('continuous clipboard includes paragraphs, list, code, table and formula source once', () => {
  const r = reader();
  r.render('Alpha first paragraph.\n\nBravo **second** paragraph with $x^2$.\n\n- list item\n\n```\n    indent\n\n\n    preserved\n```\n\n| A | B |\n| - | - |\n| cell | value |');
  const copied = clipboard(r)['text/plain'];
  for (const expected of ['Alpha first paragraph.', 'Bravo second paragraph with $x^2$.', 'list item', '    indent\n\n\n    preserved', 'cell\tvalue']) assert.ok(copied.includes(expected), `${expected}: ${copied}`);
  assert.equal(copied.match(/x\^2/g).length, 1); assert.ok(!copied.includes('Copy'));
  assert.ok(!clipboard(r)['text/html'].includes('katex')); r.close();
});
test('partial formula selection copies its entire source once', () => {
  const r = reader(); r.render('before $x^2$ after');
  const node = r.root.querySelector('.katex-html .mord.mathnormal').firstChild;
  const copied = clipboard(r, node, node)['text/plain'];
  assert.equal(copied, '$x^2$'); r.close();
});
test('same-source render preserves DOM nodes and selected text', () => {
  const r = reader(); r.render('Alpha\n\nBravo'); clipboard(r);
  const first = r.root.firstChild, selection = r.window.getSelection().toString();
  assert.equal(r.render('Alpha\n\nBravo').changed, false);
  assert.equal(r.root.firstChild, first); assert.equal(r.window.getSelection().toString(), selection); r.close();
});
test('real anchors and accessible heading metadata, Unicode, duplicates, links dispatched', () => {
  const r = reader();
  r.render('# Hello *world*\n\n# Hello world\n\n## Åäö\n\n[External](https://example.org/a) [Local](<other file.md#target>) [Anchor](#hello-world) [Mail](mailto:a@example.org)');
  assert.deepEqual(Array.from(r.messages.find(m => m.type === 'headings').headings, h => h.id), ['hello-world', 'hello-world-1', 'åäö']);
  for (const link of r.root.querySelectorAll('a')) link.click();
  assert.deepEqual(r.messages.filter(m => m.type === 'link').map(m => m.href), ['https://example.org/a', 'other%20file.md#target', '#hello-world', 'mailto:a@example.org']);
  assert.equal(r.window.mdview.scrollToHeading('%C3%A5%C3%A4%C3%B6'), true); r.close();
});
test('find spans formatted inline nodes, cycles both ways and ignores hidden duplicate math', () => {
  const r = reader(); r.render('First **formatted** text.\n\nSecond formatted text. $formatted$\n\n`formatted text`');
  let result = r.window.mdview.find('formatted text', 1, true);
  assert.equal(result.count, 3); assert.equal(result.index, 1);
  assert.equal(r.window.getSelection().toString(), 'formatted text');
  assert.equal(r.window.mdview.find('formatted text').index, 2);
  assert.equal(r.window.mdview.find('formatted text', -1).index, 1);
  assert.equal(r.window.mdview.find('formatted text', -1).index, 3);
  assert.equal(r.window.mdview.find('formatted', 1, true).count, 3);
  assert.equal(r.window.mdview.find('[no match]', 1, true).count, 0); r.close();
});
test('unsafe raw HTML is inert, unsafe link/image schemes never produce active elements', () => {
  const r = reader();
  r.render('<script>window.evil = true</script>\n\n<img src=x onerror="window.evil=true">\n\n[evil](javascript:alert(1))\n\n![evil](javascript:alert(1))\n\n$\\href{javascript:alert(1)}{x}$');
  assert.equal(r.window.evil, undefined);
  // T-0021: <img> is in the GitHub subset, but only with canonical, validated attributes.
  assert.equal(r.root.querySelectorAll('script,[onerror],a[href^="javascript:"]').length, 0);
  assert.equal(r.root.querySelectorAll('img').length, 1); r.close();
});
test('local image URL resolution decodes only once and permits remote https images', () => {
  const r = reader(); r.render('![a](../fig%2520name.png) ![b](https://example.org/image.png)', { baseURL: 'file:///tmp/docs/' });
  assert.equal(r.root.querySelectorAll('img')[0].src, 'mdview-image://local/tmp/fig%2520name.png');
  assert.equal(r.root.querySelectorAll('img')[1].src, 'https://example.org/image.png'); r.close();
});
test('all saved review fixtures render without exceptions and expected content survives', () => {
  const r = reader(), fixtures = path.resolve(__dirname, '../../review/2026-09-27/evidence');
  for (const file of fs.readdirSync(fixtures).filter(f => /^0[1-6].*\.md$/.test(f))) {
    const source = fs.readFileSync(path.join(fixtures, file), 'utf8');
    assert.doesNotThrow(() => r.render(source, { baseURL: 'file://' + fixtures + '/' }), file);
    assert.ok(r.root.childElementCount > 0, file);
    if (file.startsWith('03-')) assert.match(r.root.textContent, /SHOULD APPEAR/);
    assertInert(r, file);
  }
  r.close();
});

test('numeric math and GitHub backtick math remain formulas without treating prices as math', () => {
  const r = reader();
  r.render('$2$ and $2 + 2 = 4$ and $`a*b*c`$; costs $5 and $10.');
  assert.equal(r.root.querySelectorAll('[data-math]').length, 3);
  assert.equal(r.root.querySelectorAll('annotation')[2].textContent, 'a*b*c');
  assert.equal(r.window.mdview.scrollToHeading(''), true);
  r.close();
});

test('native-style Select All anchored at body still uses the math-safe copy handler', () => {
  const r = reader(); r.render('Alpha\n\n$$x^2$$\n\nBravo');
  const range = r.window.document.createRange(); range.selectNodeContents(r.window.document.body);
  r.window.getSelection().addRange(range);
  const data = {}, event = new r.window.Event('copy', { bubbles: true, cancelable: true });
  event.clipboardData = { setData(type, value) { data[type] = value; } };
  r.window.document.dispatchEvent(event);
  assert.equal(event.defaultPrevented, true);
  assert.equal(data['text/plain'].match(/x\^2/g).length, 1);
  assert.ok(data['text/plain'].includes('$$x^2$$\n\nBravo'));
  r.close();
});

test('malformed formulas visibly retain their original source instead of dropping content', () => {
  const r = reader(); r.render('$\\unknowncommand{x}$');
  assert.equal(r.root.querySelector('.math-error').textContent, '$\\unknowncommand{x}$');
  r.close();
});

test('partial rich copy retains bold, heading and code ancestors without surrounding text', () => {
  const r = reader(); r.render('# A heading\n\nBefore **bold words** after\n\n```\n    source line\n```');
  for (const selector of ['h1', 'strong', 'pre code']) {
    const node = r.root.querySelector(selector).firstChild;
    const data = clipboard(r, node, node);
    const html = new JSDOM(data['text/html']).window.document;
    assert.ok(html.querySelector(selector), data['text/html']);
    assert.equal(html.body.textContent, node.textContent);
    assert.ok(!data['text/plain'].includes('Before'));
  }
  r.close();
});
test('rich clipboard tables and code are styled independently of viewer CSS', () => {
  const r = reader(); r.render('| Left | Right |\n| :--- | ---: |\n| A | 123 |\n\n```python\n    value = 42\n```');
  const data = clipboard(r), doc = new JSDOM(data['text/html']).window.document;
  assert.equal(doc.querySelector('table').style.borderCollapse, 'collapse');
  assert.match(doc.querySelector('td').style.border, /solid/);
  assert.equal(doc.querySelectorAll('td')[1].style.textAlign, 'right');
  assert.match(doc.querySelector('code').style.fontFamily, /Courier New/);
  assert.equal(doc.querySelector('pre').style.whiteSpace, 'pre');
  assert.equal(doc.querySelector('code').textContent, '    value = 42\n');
  assert.equal(doc.querySelectorAll('[class],button').length, 0);
  r.close();
});
test('copied links resolve against the source document rather than the receiving app', () => {
  const r = reader(); r.render('[Relative](other%20file.md#next) [Anchor](#here) [External](https://example.com)', {baseURL:'file:///tmp/docs/', documentURL:'file:///tmp/docs/report.md'});
  const doc = new JSDOM(clipboard(r)['text/html']).window.document;
  assert.deepEqual(Array.from(doc.querySelectorAll('a'), a => a.getAttribute('href')), ['file:///tmp/docs/other%20file.md#next','file:///tmp/docs/report.md#here','https://example.com/']);
  assert.equal(r.root.querySelector('a').getAttribute('href'),'other%20file.md#next');
  r.close();
});
test('copying a numbered-list excerpt keeps its original starting number', () => {
  const r = reader(); r.render('3. first\n4. second\n5. third');
  const items=r.root.querySelectorAll('li');
  const data=clipboard(r,items[1].firstChild,items[2].firstChild);
  const doc=new JSDOM(data['text/html']).window.document;
  assert.equal(doc.querySelector('ol').getAttribute('start'),'4');
  assert.equal(doc.querySelectorAll('li').length,2);
  assert.ok(!doc.body.textContent.includes('first'));
  r.render('0. zero\n1. one');
  assert.equal(new JSDOM(clipboard(r)['text/html']).window.document.querySelector('ol').start, 0);
  r.close();
});
test('leading YAML front matter renders as a GitHub-style metadata table outside the outline', () => {
  const r = reader();
  r.render('---\ntitle: Hello\ntags: [a, b]\nauthors:\n  - Ada\n  - Bob\ndraft: true\n---\n\n# Body\n\nText $x^2$');
  const table = r.root.firstElementChild;
  assert.equal(table.tagName, 'TABLE'); assert.ok(table.classList.contains('front-matter'));
  assert.deepEqual(Array.from(table.querySelectorAll(':scope > thead th'), n => n.textContent), ['title', 'tags', 'authors', 'draft']);
  const cells = table.querySelectorAll(':scope > tbody > tr > td');
  assert.equal(cells[0].textContent, 'Hello');
  assert.deepEqual(Array.from(cells[1].querySelectorAll('td'), n => n.textContent), ['a', 'b']);
  assert.deepEqual(Array.from(cells[2].querySelectorAll('td'), n => n.textContent), ['Ada', 'Bob']);
  assert.equal(cells[3].textContent, 'true');
  assert.equal(r.root.querySelectorAll('hr').length, 0);
  assert.deepEqual(Array.from(r.messages.find(m => m.type === 'headings').headings, h => h.title), ['Body']);
  assert.equal(r.root.querySelectorAll('[data-math]').length, 1);
  const data = clipboard(r);
  assert.match(data['text/plain'], /title/); assert.match(data['text/plain'], /Hello/);
  assert.ok(!/class=/.test(data['text/html']));
  assert.equal(r.window.mdview.find('Hello').count, 1); r.close();
});
test('front matter tolerates BOM and CRLF and ignores non-leading or unclosed rules', () => {
  const r = reader();
  r.render('\uFEFF---\r\ntitle: Win\r\n---\r\nBody');
  assert.ok(r.root.querySelector('table.front-matter')); assert.ok(!r.root.textContent.includes('\uFEFF'));
  for (const text of ['\n---\na: b\n---\n', 'Intro\n\n---\na: b\n---\n', '---\na: b\n\nno close', '> ---\n> a: b\n\n---\n', '----\na: b\n----\n']) {
    r.render(text);
    assert.equal(r.root.querySelectorAll('.front-matter,.front-matter-source').length, 0, JSON.stringify(text));
  }
  r.render('---\na: b\n---\nTitle\n---\n\nText\n\n---\n\nEnd');
  assert.equal(r.root.querySelectorAll('table.front-matter').length, 1);
  assert.equal(r.root.querySelector('h2').textContent, 'Title'); assert.equal(r.root.querySelectorAll('hr').length, 1);
  r.render('---\n---\nBody'); assert.equal(r.root.innerHTML.trim(), '<p>Body</p>');
  r.render('---\nonly: front\n...'); assert.equal(r.root.children.length, 1); assert.ok(r.root.querySelector('table.front-matter'));
  r.close();
});
test('unsupported front matter stays visible as highlighted source and values stay inert', () => {
  const r = reader();
  for (const yaml of ['a:\n  b: c', 'a: |\n  text', 'a: &x 1\nb: *x', 'a: !!binary aGk=', 'a: !js/function x', 'a: "open', 'a: 1\na: 2', '- a\n- b']) {
    r.render(`---\n${yaml}\n---\nBody`);
    const code = r.root.querySelector('.front-matter-source code.language-yaml');
    assert.ok(code, yaml); assert.equal(code.textContent, yaml, yaml);
    assert.equal(r.root.querySelectorAll('table').length, 0, yaml);
  }
  r.render('---\nmath: $x^2$\nhtml: <script>window.evil=1</script>\nurl: http://x:80/a\ntime: 12:30\nbold: a **b**\nq: "x # y"\n---\n');
  assert.equal(r.root.querySelectorAll('[data-math],a,script,strong').length, 0);
  assert.equal(r.window.evil, undefined);
  assert.deepEqual(Array.from(r.root.querySelectorAll('td'), n => n.textContent), ['$x^2$', '<script>window.evil=1</script>', 'http://x:80/a', '12:30', 'a **b**', 'x # y']);
  r.render('+++\ntitle = "T"\n+++\nBody');
  assert.ok(r.root.querySelector('.front-matter-source code.language-toml')); r.close();
});

// GitHub alerts and footnotes (T-0020). Expectations follow GitHub /markdown (gfm) output recorded 2026-11-03.
const alertTypes = { note: 'info', tip: 'light-bulb', important: 'report', warning: 'alert', caution: 'stop' };
test('all five GitHub alert types render as titled, iconed alerts; marker is case-insensitive', () => {
  const r = reader();
  r.render('> [!NOTE]\n> n\n\n> [!tip]\n> t\n\n> [!Important]\n> i\n\n> [!WARNING]   \n> w\n\n> [!CAUTION]\n> c');
  const alerts = r.root.querySelectorAll(':scope > div.markdown-alert');
  assert.equal(alerts.length, 5); assert.equal(r.root.querySelectorAll('blockquote').length, 0);
  Object.keys(alertTypes).forEach((type, index) => {
    const alert = alerts[index];
    assert.ok(alert.classList.contains(`markdown-alert-${type}`), type);
    const title = alert.firstElementChild;
    assert.ok(title.matches('p.markdown-alert-title'), type);
    assert.equal(title.textContent, type[0].toUpperCase() + type.slice(1));
    const svg = title.querySelector('svg.octicon');
    assert.equal(svg.getAttribute('aria-hidden'), 'true'); assert.equal(svg.getAttribute('width'), '16');
    assert.equal(alert.children.length, 2); assert.equal(alert.children[1].textContent, type[0]);
    assert.ok(!alert.textContent.includes('[!'));
  });
  r.close();
});
test('alert icons are the vendored Primer Octicons paths', () => {
  const r = reader();
  r.render(Object.keys(alertTypes).map(type => `> [!${type}]\n> x`).join('\n\n'));
  for (const [type, icon] of Object.entries(alertTypes)) {
    const svg = fs.readFileSync(path.join(web, `vendor/octicons/${icon}-16.svg`), 'utf8');
    const expected = /<path d="([^"]+)"/.exec(svg)[1];
    assert.equal(r.root.querySelector(`.markdown-alert-${type} svg path`).getAttribute('d'), expected, type);
  }
  r.close();
});
test('non-alert quotes stay ordinary blockquotes as on GitHub', () => {
  const r = reader();
  for (const text of ['> [!NOTE] text\n> more', '> [!INFO]\n> x', '> intro\n> [!NOTE]\n> x', '> > [!NOTE]\n> > x', '- > [!NOTE]\n  > x', '> [!NOTE]', '> [!NOTE]\n>\n', '> # [!NOTE]\n> x', '[!NOTE]\nx']) {
    r.render(text);
    assert.equal(r.root.querySelectorAll('.markdown-alert').length, 0, JSON.stringify(text));
    assert.ok(r.root.textContent.includes('[!'), JSON.stringify(text));
  }
  r.close();
});
test('alert edge cases follow GitHub: escaped marker, lazy line, blank line after marker', () => {
  const r = reader();
  r.render('> \\[!NOTE]\n> x'); assert.ok(r.root.querySelector('.markdown-alert-note')); assert.equal(r.root.querySelector('.markdown-alert').children[1].textContent, 'x');
  r.render('> [!NOTE]\nlazy'); assert.equal(r.root.querySelector('.markdown-alert-note').children[1].textContent, 'lazy');
  r.render('> [!NOTE]\n>\n> para'); assert.equal(r.root.querySelector('.markdown-alert-note').children[1].textContent, 'para');
  r.close();
});
test('alerts keep nested headings (in outline), math, code and lists', () => {
  const r = reader();
  r.render('> [!TIP]\n> # Inside alert\n> text $x^2$\n>\n> - item\n>\n> ```python\n> print(1)\n> ```\n\n# After');
  const alert = r.root.querySelector('.markdown-alert-tip');
  assert.equal(alert.querySelector('h1').id, 'inside-alert');
  assert.ok(alert.querySelector('[data-math] .katex')); assert.ok(alert.querySelector('li'));
  assert.equal(alert.querySelector('code.language-python').textContent, 'print(1)\n');
  assert.deepEqual(Array.from(r.messages.filter(m => m.type === 'headings').at(-1).headings, h => h.title), ['Inside alert', 'After']);
  r.close();
});
test('footnotes number by first reference with GitHub ids, repeated refs and back-links', () => {
  const r = reader();
  r.render('A[^b] B[^a] C[^b]\n\n[^a]: Alpha\n[^b]: Bravo\n[^unused]: Unused\n\n    # Unused heading\n\n# fn a');
  const refs = r.root.querySelectorAll('sup.footnote-ref > a[data-footnote-ref]');
  assert.deepEqual(Array.from(refs, a => a.textContent), ['1', '2', '1']);
  assert.deepEqual(Array.from(refs, a => a.getAttribute('href')), ['#fn-b', '#fn-a', '#fn-b']);
  assert.deepEqual(Array.from(refs, a => a.id), ['fnref-b', 'fnref-a', 'fnref-b-2']);
  assert.equal(refs[0].getAttribute('aria-describedby'), 'footnote-label');
  const section = r.root.querySelector('section.footnotes[data-footnotes]');
  assert.equal(section, r.root.lastElementChild); assert.equal(r.root.querySelectorAll('hr').length, 0);
  assert.ok(section.querySelector('h2#footnote-label.sr-only'));
  const items = section.querySelectorAll('ol > li');
  assert.deepEqual(Array.from(items, li => li.id), ['fn-b', 'fn-a']);
  assert.ok(!section.textContent.includes('Unused'));
  const back = items[0].querySelectorAll('a.footnote-backref[data-footnote-backref]');
  assert.deepEqual(Array.from(back, a => a.getAttribute('href')), ['#fnref-b', '#fnref-b-2']);
  assert.deepEqual(Array.from(back, a => a.getAttribute('aria-label')), ['Back to reference 1', 'Back to reference 1-2']);
  assert.equal(back[1].querySelector('sup').textContent, '2');
  assert.equal(items[0].querySelector('p').firstChild.textContent, 'Bravo ');
  const headings = Array.from(r.messages.filter(m => m.type === 'headings').at(-1).headings);
  assert.deepEqual(headings.map(h => h.title), ['fn a']);
  assert.notEqual(headings[0].id, 'fn-a'); assert.equal(r.root.querySelectorAll('#fn-a').length, 1);
  r.close();
});
test('footnote labels are case-insensitive and the first duplicate definition wins, as on GitHub', () => {
  const r = reader();
  r.render('X[^Note] Y[^note]\n\n[^note]: lower');
  assert.deepEqual(Array.from(r.root.querySelectorAll('[data-footnote-ref]'), a => a.textContent), ['1', '1']);
  assert.equal(r.root.querySelectorAll('section.footnotes li').length, 1);
  assert.match(r.root.querySelector('section.footnotes li').textContent, /lower/);
  r.render('X[^a]\n\n[^a]: one\n[^a]: two');
  assert.equal(r.root.querySelectorAll('section.footnotes li').length, 1);
  assert.match(r.root.querySelector('section.footnotes li').textContent, /one/);
  assert.ok(!r.root.textContent.includes('two'));
  r.close();
});
test('multi-paragraph footnotes keep code and math; missing and inline notes stay literal', () => {
  const r = reader();
  r.render('X[^1] and [^missing] and ^[inline]\n\n[^1]: First $x^2$\n\n    ```\n    code\n    ```\n\n    Second para');
  const item = r.root.querySelector('section.footnotes li#fn-1');
  assert.ok(item.querySelector('[data-math] .katex')); assert.equal(item.querySelector('pre code').textContent, 'code\n');
  const paragraphs = item.querySelectorAll('p');
  assert.equal(paragraphs.length, 2); assert.ok(paragraphs[1].querySelector('.footnote-backref'));
  assert.ok(r.root.querySelector('p').textContent.includes('[^missing] and ^[inline]'));
  assert.equal(r.root.querySelectorAll('[data-footnote-ref]').length, 1);
  r.render('No definitions [^a].'); assert.equal(r.root.querySelectorAll('section.footnotes').length, 0);
  r.close();
});
test('footnote labels with special characters produce escaped ids and encoded hrefs', () => {
  const r = reader();
  r.render('Z[^ä] Q[^a"b]\n\n[^ä]: umlaut\n[^a"b]: quote');
  const refs = r.root.querySelectorAll('[data-footnote-ref]');
  assert.equal(refs[0].getAttribute('href'), '#fn-%C3%A4'); assert.equal(refs[0].id, 'fnref-ä');
  assert.equal(refs[1].id, 'fnref-a"b');
  assert.ok(r.root.querySelector('li[id="fn-a\\"b"]'));
  assert.equal(r.window.mdview.scrollToHeading(refs[0].getAttribute('href')), true);
  r.close();
});
test('footnote and back-link clicks scroll and post the anchor; legacy GitHub ids resolve', () => {
  const r = reader(); r.render('A[^b]\n\n[^b]: Bravo');
  const scrolled = [];
  r.window.HTMLElement.prototype.scrollIntoView = function () { scrolled.push(this.id); };
  r.root.querySelector('[data-footnote-ref]').click();
  r.root.querySelector('.footnote-backref').click();
  assert.deepEqual(r.messages.filter(m => m.type === 'link').map(m => m.href), ['#fn-b', '#fnref-b']);
  assert.deepEqual(scrolled, ['fn-b', 'fnref-b']);
  assert.equal(r.window.mdview.scrollToHeading('#user-content-fn-b'), true);
  assert.equal(r.window.mdview.scrollToHeading('fn-b'), true);
  assert.equal(r.window.mdview.scrollToHeading('#nothing-here'), false);
  r.close();
});
test('copy turns footnote refs into [n], drops icons, back-links and hidden labels', () => {
  const r = reader();
  r.render('> [!WARNING]\n> Careful[^b].\n\nText[^a] more[^b].\n\n[^a]: Alpha note\n[^b]: Bravo note');
  const data = clipboard(r), plain = data['text/plain'];
  assert.ok(plain.includes('Warning\n\nCareful[1].'), plain);
  assert.ok(plain.includes('Text[2] more[1].'), plain);
  assert.ok(plain.includes('[1] Bravo note\n[2] Alpha note'), plain);
  assert.ok(!plain.includes('↩') && !plain.includes('Footnotes'), plain);
  const html = data['text/html'], doc = new JSDOM(html).window.document;
  assert.ok(!html.includes('<svg') && !html.includes('↩') && !html.includes('Footnotes'), html);
  assert.equal(doc.querySelectorAll('[class]').length, 0);
  assert.equal(doc.querySelector('sup').textContent, '1'); assert.equal(doc.querySelectorAll('sup a').length, 0);
  const alert = doc.body.firstElementChild;
  assert.match(alert.style.borderLeft, /solid/); assert.equal(alert.firstElementChild.style.fontWeight, 'bold');
  assert.equal(alert.firstElementChild.style.color, alert.style.borderLeftColor);
  assert.match(doc.querySelector('section').style.borderTop, /solid/);
  r.close();
});
test('find counts visible footnote text but not the hidden Footnotes label', () => {
  const r = reader(); r.render('> [!NOTE]\n> Alert body\n\nText[^a]\n\n[^a]: Footnote body');
  assert.equal(r.window.mdview.find('Footnote body', 1, true).count, 1);
  assert.equal(r.window.mdview.find('Footnotes', 1, true).count, 0);
  assert.equal(r.window.mdview.find('Alert body', 1, true).count, 1);
  r.close();
});
test('front matter still works alongside alerts and footnotes', () => {
  const r = reader(); r.render('---\ntitle: T\n---\n\n> [!NOTE]\n> x[^a]\n\n[^a]: y');
  assert.ok(r.root.firstElementChild.matches('table.front-matter'));
  assert.ok(r.root.querySelector('.markdown-alert-note [data-footnote-ref]'));
  r.close();
});

// Sanitized GitHub-style HTML subset (T-0021). Author HTML is re-emitted canonically by html-policy.js.
const policyTags = new Set(['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'div', 'blockquote', 'pre', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'caption', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'details', 'summary', 'figure', 'figcaption', 'picture', 'source', 'hr', 'br', 'wbr', 'img', 'a', 'b', 'i', 'strong', 'em', 'del', 'ins', 's', 'strike', 'sub', 'sup', 'kbd', 'code', 'tt', 'samp', 'var', 'q', 'cite', 'dfn', 'abbr', 'mark', 'small', 'span', 'time', 'ruby', 'rt', 'rp', 'bdo']);
const safeHref = /^(#|https?:|mailto:|[^:/?#\\]*(?:[/?#]|$))/i, safeImage = /^(mdview-image:\/\/local\/|https?:\/\/|data:image\/(png|gif|jpeg|webp);)/i;
function assertInert(r, label = '') {
  const { root, window } = r;
  for (const node of root.querySelectorAll('*')) {
    const tag = node.localName, katex = node.closest('.katex'), octicon = node.closest('.markdown-alert-title svg.octicon');
    assert.ok(policyTags.has(tag) || ['section', 'button', 'input'].includes(tag) || katex || octicon, `${label}: unexpected <${tag}>`);
    if (tag === 'button') assert.ok(node.matches('.code-block > button.copy-code'), label);
    if (tag === 'input') assert.ok(node.matches('input.task-checkbox[type="checkbox"][disabled]'), `${label}: forged input`);
    for (const { name, value } of node.attributes) {
      assert.ok(!/^on/i.test(name) && !['srcdoc', 'formaction', 'action', 'xlink:href', 'background', 'poster'].includes(name), `${label}: <${tag} ${name}>`);
      if (name === 'style') assert.ok(katex || (/^t[hd]$/.test(tag) && /^text-align:(left|center|right)$/.test(value)), `${label}: style on <${tag}>`);
      if (name === 'id' || name === 'name') assert.ok(!['mdview', 'document', 'getElementById', 'body', 'cookie'].includes(value), `${label}: clobbering ${name}=${value}`);
    }
    if (node.hasAttribute('href')) assert.ok(tag === 'a' && safeHref.test(node.getAttribute('href')) && !/^[/\\]{2}/.test(node.getAttribute('href')), `${label}: href ${node.getAttribute('href')}`);
    if (node.hasAttribute('src')) assert.ok(tag === 'img' && safeImage.test(node.getAttribute('src')), `${label}: src ${node.getAttribute('src')}`);
    if (node.hasAttribute('srcset')) for (const candidate of node.getAttribute('srcset').split(/,\s+/)) assert.ok(tag === 'source' && safeImage.test(candidate), `${label}: srcset ${candidate}`);
  }
  assert.equal(window.__pwned, undefined, label);
  const reparsed = window.document.createElement('main'); reparsed.innerHTML = root.innerHTML;
  assert.equal(reparsed.innerHTML, root.innerHTML, `${label}: serialization is not stable`);
}
test('allowed GitHub HTML renders as exact canonical markup', () => {
  const r = reader(), markup = text => r.window.mdview.markup(text);
  const same = ['<details open><summary>Open</summary>Shown</details>\n',
    '<p align="center">\n  <a href="https://example.org/ci"><img src="badge.svg" alt="CI" width="64" height="20"></a>\n</p>\n',
    '<img src="shot.png" alt="Shot" width="50%" height="120" align="right" loading="lazy">\n',
    '<picture>\n  <source media="(prefers-color-scheme: dark)" srcset="dark.png 1x, dark@2x.png 2x">\n  <img src="light.png" alt="Logo">\n</picture>\n',
    '<table border="1">\n<thead><tr><th scope="col" align="left">A</th></tr></thead>\n<tbody><tr><td colspan="2" valign="top" width="40">B</td></tr></tbody>\n</table>\n',
    '<dl>\n<dt>Term</dt>\n<dd>Definition</dd>\n</dl>\n', '<pre>\nline &lt;1&gt;\n  indented\n</pre>\n',
    '<ol start="3" type="a"><li value="5">x</li></ol>\n', '<figure><img src="f.png" alt="F"><figcaption>Cap <mark>tion</mark></figcaption></figure>\n',
    '<div dir="rtl" lang="ar-EG"><time datetime="2026-11-03">Today</time> <abbr title="HyperText">HTML</abbr> <del>old</del><ins>new</ins></div>\n'];
  for (const html of same) assert.equal(markup(html), html);
  assert.equal(markup('<details>\n<summary>More <b>info</b></summary>\n\n**Markdown**\n\n</details>\n'), '<details>\n<summary>More <b>info</b></summary>\n<p><strong>Markdown</strong></p>\n</details>\n');
  assert.equal(markup('Press <kbd>Ctrl</kbd>+<kbd>C</kbd>, H<sub>2</sub>O, x<sup>2</sup><br>next\n'), '<p>Press <kbd>Ctrl</kbd>+<kbd>C</kbd>, H<sub>2</sub>O, x<sup>2</sup><br>next</p>\n');
  assert.equal(markup('<ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby>\n'), '<p><ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby></p>\n');
  assert.equal(markup('<p>&copy; &amp; &#169; &#xA9; &bogus; a < b</p>\n'), '<p>© &amp; © © &amp;bogus; a &lt; b</p>\n');
  assert.equal(markup('<br/> <a name="top"/> <hr/>\n'), '<p><br> <a name="user-content-top"></a> &lt;hr/&gt;</p>\n');
  r.close();
});
test('allowed HTML becomes real elements with Markdown, math and images inside', () => {
  const r = reader();
  r.render('<details>\n<summary>More</summary>\n\n**Markdown** $x^2$\n\n</details>\n\n<p align="center"><img src="a b.png" alt="A" width="64"></p>\n\n<kbd>K</kbd>', { baseURL: 'file:///tmp/docs/' });
  const details = r.root.querySelector('details');
  assert.equal(details.parentElement, r.root); assert.equal(details.open, false);
  assert.ok(details.querySelector('p strong')); assert.ok(details.querySelector('[data-math] .katex'));
  const img = r.root.querySelector('p[align="center"] img');
  assert.equal(img.src, 'mdview-image://local/tmp/docs/a%20b.png'); assert.equal(img.width, 64);
  assert.equal(img.referrerPolicy, 'no-referrer'); assert.ok(r.root.querySelector('p > kbd')); r.close();
});
test('disallowed tags stay visible as text and comments are hidden', () => {
  const r = reader(), markup = text => r.window.mdview.markup(text);
  assert.equal(markup('<script>window.__pwned=1</script>\n'), '&lt;script&gt;window.__pwned=1&lt;/script&gt;\n');
  assert.equal(markup('<style>body{display:none}</style>\n'), '&lt;style&gt;body{display:none}&lt;/style&gt;\n');
  assert.equal(markup('<iframe src="https://evil.example"></iframe>\n'), '&lt;iframe src=&quot;https://evil.example&quot;&gt;&lt;/iframe&gt;\n');
  assert.equal(markup('<center>Centered <font color="red">red</font> <u>u</u></center>\n'), '&lt;center&gt;Centered &lt;font color=&quot;red&quot;&gt;red&lt;/font&gt; &lt;u&gt;u&lt;/u&gt;&lt;/center&gt;\n');
  assert.equal(markup('<svg onload="x"><a href="https://e.example">y</a></svg>\n'), '<p>&lt;svg onload=&quot;x&quot;&gt;&lt;a href=&quot;https://e.example&quot;&gt;y&lt;/a&gt;&lt;/svg&gt;</p>\n');
  assert.equal(markup('<svg>\n<a href="https://e.example">y</a>\n</svg>\n'), '&lt;svg&gt;\n&lt;a href=&quot;https://e.example&quot;&gt;y&lt;/a&gt;\n&lt;/svg&gt;\n');
  assert.equal(markup('a <input type="checkbox" checked> b <!-- hidden --> c\n'), '<p>a &lt;input type=&quot;checkbox&quot; checked&gt; b  c</p>\n');
  assert.equal(markup('<!-- secret -->\n\nafter\n'), '<p>after</p>\n');
  assert.equal(markup('a <style>b</style> c\n'), '<p>a &lt;style&gt;b&lt;/style&gt; c</p>\n');
  r.render('<script>window.__pwned=1</script>\n\n<u>under</u> <!-- secret --> <form><button>b</button></form>');
  assert.ok(r.root.textContent.includes('<script>window.__pwned=1</script>')); assert.ok(r.root.textContent.includes('<u>under</u>'));
  assert.ok(!r.root.textContent.includes('secret')); assert.equal(r.root.querySelectorAll('script,u,form,button').length, 0);
  assertInert(r, 'disallowed'); r.close();
});
test('unsafe and unknown attributes are dropped; duplicates keep the first value', () => {
  const r = reader(), markup = text => r.window.mdview.markup(text);
  assert.equal(markup('<p align="center" style="color:red" class="x" onclick="alert(1)" data-x="1" tabindex="1" id="intro" title=\'T "q" >\'>x</p>\n'), '<p align="center" id="user-content-intro" title="T &quot;q&quot; &gt;">x</p>\n');
  assert.equal(markup('<a href="https://ok.example" target="_blank" rel="opener" href="javascript:alert(1)">ok</a>\n'), '<p><a href="https://ok.example">ok</a></p>\n');
  assert.equal(markup('<a href="javascript:alert(1)" href="https://ok.example">bad</a>\n'), '<p>bad</p>\n');
  assert.equal(markup('<img src="a.png" srcdoc="x" onerror="alert(1)" style="x" alt=\'say "hi"\'>\n'), '<img src="a.png" alt="say &quot;hi&quot;">\n');
  assert.equal(markup('<div ALIGN="CENTER" DIR="RTL" lang="sv-SE" aria-hidden="true" aria-label="L" role="note" accesskey="k" xmlns="x">x</div>\n'), '<div align="center" dir="rtl" lang="sv-SE" aria-hidden="true" aria-label="L">x</div>\n');
  assert.equal(markup('<td width="9999999" colspan="12345" align="middle" valign="center">x</td>\n'), '<td>x</td>\n');
  assert.equal(markup('<img src="a.png" width="10px" height="1e3" align="justify" loading="auto">\n'), '<img src="a.png">\n');
  assert.equal(markup('<ol start="x" type="z"><li value="1.5">x</li></ol>\n'), '<ol><li>x</li></ol>\n');
  assert.equal(markup('<source srcset="a.png" type="text/html" media="screen;x{}">\n'), '<source srcset="a.png">\n');
  r.close();
});
const hostileURLs = ['JaVaScRiPt:alert(1)', 'jav&#x09;ascript:alert(1)', '&#106;avascript&colon;alert(1)', '&#x6A;avascript:alert(1)', 'javascript&#58;alert(1)', 'jav&NewLine;ascript:alert(1)',
  '\u0001javascript:alert(1)', ' \u0000 javascript:alert(1)', 'java\nscript:alert(1)', 'vbscript:msgbox(1)', 'data:text/html,<b>x</b>', 'data:image/svg+xml;base64,PHN2Zz4=',
  'file:///etc/passwd', 'mdview-image://local/etc/passwd', '//evil.example/a.md', '\\\\evil.example\\a', '/\\evil.example', 'blob:https://x.example/1', 'about:blank', 'ssh://host', '1x:y'];
test('hostile link and image URLs never become active links or image fetches', () => {
  const r = reader();
  for (const url of hostileURLs) {
    const attr = url.replace(/"/g, '&quot;');
    r.render(`x <a href="${attr}">link text</a> y\n\n<img src="${attr}" alt="Alt text">\n\n<picture><source srcset="${attr} 2x"><img src="ok.png" alt="P"></picture>`, { baseURL: 'file:///tmp/docs/' });
    assert.equal(r.root.querySelectorAll('a').length, 0, JSON.stringify(url));
    assert.ok(r.root.textContent.includes('link text'), JSON.stringify(url));
    assert.equal(r.root.querySelectorAll('[srcset]').length, 0, JSON.stringify(url));
    const images = r.root.querySelectorAll('img');
    assert.equal(images.length, 1, JSON.stringify(url)); assert.equal(images[0].alt, 'P');
    assert.match(r.root.querySelector('.image-error').textContent, /Image unavailable: Alt text/, JSON.stringify(url));
    assertInert(r, url);
  }
  for (const srcset of ['ok.png 1x, data:image/svg+xml;base64,AA 2x', 'ok.png 1q', 'ok.png 1x 2x', ', ,', '']) {
    assert.equal(r.window.mdview.markup(`<picture><source srcset="${srcset}"><img src="ok.png"></picture>\n`), '<p><picture><source><img src="ok.png"></picture></p>\n', srcset);
  }
  r.render('<picture><source srcset="dark.png 1x, data:image/png;base64,iVBORw0KGgo= 2x" media="(prefers-color-scheme: dark)"><img src="https://example.org/l.png" alt="L"></picture>', { baseURL: 'file:///tmp/docs/' });
  assert.equal(r.root.querySelector('source').getAttribute('srcset'), 'mdview-image://local/tmp/docs/dark.png 1x, data:image/png;base64,iVBORw0KGgo= 2x');
  assert.equal(r.root.querySelector('img').src, 'https://example.org/l.png'); r.close();
});
test('links and images in HTML route exactly like their Markdown equivalents', () => {
  const r = reader();
  const pairs = [['https://example.org/a?b=1', 'https://example.org/a?b=1'], ['other file.md#target', '<other file.md#target>'], ['#hello-world', '#hello-world'], ['mailto:a@example.org', 'mailto:a@example.org'], ['../up%20one.markdown', '../up%20one.markdown'], ['caf&eacute;.md', 'café.md']];
  r.render(pairs.map(([html, markdown]) => `<a href="${html}">h</a> [m](${markdown})`).join('\n\n'), { baseURL: 'file:///tmp/docs/' });
  for (const link of r.root.querySelectorAll('a')) link.click();
  const hrefs = r.messages.filter(m => m.type === 'link').map(m => m.href);
  assert.equal(hrefs.length, pairs.length * 2);
  for (let i = 0; i < hrefs.length; i += 2) assert.equal(hrefs[i], hrefs[i + 1], `${hrefs[i]} vs ${hrefs[i + 1]}`);
  r.render('<img src="images/a b.png" alt="h"> ![m](images/a%20b.png) <img src="https://example.org/i.png"> ![m](https://example.org/i.png)', { baseURL: 'file:///tmp/docs/' });
  const sources = Array.from(r.root.querySelectorAll('img'), img => img.src);
  assert.deepEqual(sources, ['mdview-image://local/tmp/docs/images/a%20b.png', 'mdview-image://local/tmp/docs/images/a%20b.png', 'https://example.org/i.png', 'https://example.org/i.png']);
  r.root.querySelector('img').dispatchEvent(new r.window.Event('error'));
  assert.equal(r.root.querySelector('.image-error').textContent, 'Image unavailable: h'); r.close();
});
test('unclosed or stray HTML cannot leak into or close trusted structure', () => {
  const r = reader();
  r.render('<b>bold\n\nnext para');
  assert.equal(r.root.querySelectorAll('p')[1].textContent, 'next para'); assert.equal(r.root.querySelectorAll('p')[1].closest('b'), null);
  r.render('<div><b>bold <i>italic\n\nnext para\n\n</div>');
  assert.equal(r.root.querySelector('p').textContent, 'next para'); assert.equal(r.root.querySelector('p').closest('b,i'), null);
  assert.equal(r.root.querySelector('p').parentElement.tagName, 'DIV');
  r.render('a <a href="https://x.example">link <em>em\n\nnext');
  assert.equal(r.root.querySelectorAll('p')[1].closest('a,em'), null); assert.equal(r.root.querySelectorAll('p')[1].querySelector('a,em'), null);
  r.render('- one </li> two\n- three </ul> four\n\n> quote </blockquote> still\n\n**strong </strong> still**\n\n> [!NOTE]\n> alert </div> body\n\nafter');
  assert.deepEqual(Array.from(r.root.querySelectorAll('li'), li => li.textContent), ['one  two', 'three  four']);
  assert.match(r.root.querySelector('blockquote').textContent, /still/); assert.equal(r.root.querySelector('strong').textContent, 'strong  still');
  assert.match(r.root.querySelector('.markdown-alert').textContent, /body/); assert.equal(r.root.lastElementChild.textContent, 'after');
  assert.equal(r.root.lastElementChild.parentElement, r.root);
  r.render('> [!NOTE]\n> <div align="center">\n>\n> inside\n\nafter\n\n</div>\n\nend');
  const alert = r.root.querySelector('.markdown-alert');
  assert.match(alert.textContent, /inside/); assert.ok(!alert.textContent.includes('after'));
  assert.equal(Array.from(r.root.querySelectorAll('p')).find(p => p.textContent === 'after').parentElement, r.root);
  r.render('<details><summary>S</summary>\n\nbody text\n\n# Next\n\nX[^1]\n\n[^1]: note');
  const details = r.root.querySelector('details');
  assert.match(details.textContent, /body text/); assert.ok(details.querySelector('h1'));
  assert.equal(r.root.querySelector('section.footnotes').parentElement, r.root);
  r.render('<b>a <i>b</b> c</i> d');
  assert.equal(r.root.innerHTML, '<p><b>a <i>b</i></b> c d</p>\n');
  r.close();
});
const mxssCorpus = ['<math><mtext><table><mglyph><style><img src=x onerror=window.__pwned=1>', '<noscript><p title="</noscript><img src=x onerror=window.__pwned=1>">',
  '<form><math><mtext></form><form><mglyph><style></math><img src onerror=window.__pwned=1>', '<details open ontoggle="window.__pwned=1">x</details>',
  '<meta http-equiv="refresh" content="0;url=javascript:window.__pwned=1">', '<base href="javascript:/">', '<object data="javascript:window.__pwned=1"></object>',
  '<link rel="stylesheet" href="https://evil.example/x.css">', '<svg><animate onbegin="window.__pwned=1" attributeName="x" dur="1s">',
  '<svg><a xlink:href="javascript:window.__pwned=1"><text x="20" y="20">X</text></a></svg>', '<img src=x onerror="window.__pwned=1">',
  '<iframe srcdoc="<script>window.__pwned=1</script>"></iframe>', '<a href="javascript:window.__pwned=1">x</a>', '<img src="x" alt="`<img src=x onerror=window.__pwned=1>`">',
  '<a title="&lt;img src=x onerror=window.__pwned=1&gt;" href="#x">t</a>', '<svg></p><style><a id="</style><img src=1 onerror=window.__pwned=1>">',
  '<math><mi><mglyph><svg><mtext><textarea><path id="</textarea><img onerror=window.__pwned=1 src=1>">', '<table><tr><td><style></td><img src=x onerror=window.__pwned=1></style>',
  '<xmp><img src=x onerror=window.__pwned=1></xmp>', '<template><img src=x onerror=window.__pwned=1></template>',
  '<select><template><style><!--</style><a rel="--></select><img src=x onerror=window.__pwned=1>">', '<div id="mdview"></div><img name="getElementById"><form name="body"></form>',
  '<a href="#" style="position:fixed;top:0;left:0;width:100%;height:100%">overlay</a>', '<!--><img src=x onerror=window.__pwned=1>-->', '<!-- --!><img src=x onerror=window.__pwned=1>-->',
  '<?xml-stylesheet href="x"?><img src=x onerror=window.__pwned=1>', '<![CDATA[<img src=x onerror=window.__pwned=1>]]>', '<p><a href="https://ok.example">ok<img src="x" onerror="window.__pwned=1"></a></p>',
  '<div\nonclick="window.__pwned=1">x</div>', '<img/src="x"/onerror="window.__pwned=1">', '<a href="jav&#x0A;ascript:window.__pwned=1">x</a>', '<embed src="javascript:window.__pwned=1">',
  '<input autofocus onfocus="window.__pwned=1">', '<video><source onerror="window.__pwned=1"></video>', '<button formaction="javascript:window.__pwned=1">x</button>',
  '<a href="https://ok.example"><table><tr><td><a href="javascript:window.__pwned=1">x</a></td></tr></table></a>', '<plaintext><img src=x onerror=window.__pwned=1>',
  '<p id="</p><img src=x onerror=window.__pwned=1>">x</p>', '<img src="x\' onerror=\'window.__pwned=1">', '<details><summary onclick="window.__pwned=1">s</summary><style>*{}</style></details>',
  '<span class="katex copy-code markdown-alert" data-math="x" data-footnote-ref>forged</span>', '<input class="task-checkbox" type="checkbox" disabled>'];
test('mXSS and injection corpus renders inert in every block and inline context', () => {
  const r = reader();
  for (const sample of mxssCorpus) {
    for (const text of [sample, `x ${sample} y`, `- ${sample}`, `> ${sample}`, `<div>\n\n${sample}\n\n</div>`, `| a |\n| - |\n| ${sample.replace(/\|/g, '\\|')} |`]) {
      r.render(text, { baseURL: 'file:///tmp/docs/' });
      assertInert(r, JSON.stringify(text));
      assert.equal(r.root.querySelectorAll('[class*="katex"],.copy-code,.markdown-alert,[data-math],[data-footnote-ref],input').length, 0, JSON.stringify(text));
    }
  }
  r.close();
});
test('math, code, checkboxes, front matter, alerts and footnotes survive alongside HTML', () => {
  const r = reader();
  r.render('---\ntitle: T\n---\n\n<sup>$x^2$</sup> <kbd>K</kbd>\n\n<details>\n<summary>Code</summary>\n\n```python\nprint(1)\n```\n\n$$y$$\n\n</details>\n\n- [ ] open <b>bold</b>\n- [x] done\n\n> [!TIP]\n> <kbd>Tip</kbd> body[^a]\n\n[^a]: Note <sub>sub</sub>');
  assert.ok(r.root.firstElementChild.matches('table.front-matter'));
  assert.ok(r.root.querySelector('sup [data-math] .katex'));
  assert.ok(r.root.querySelector('details .hljs-built_in, details .code-block .copy-code'));
  assert.ok(r.root.querySelector('details .math-display'));
  const boxes = r.root.querySelectorAll('input.task-checkbox');
  assert.equal(boxes.length, 2); assert.equal(boxes[1].checked, true); assert.ok(r.root.querySelector('li.task-list-item b'));
  assert.ok(r.root.querySelector('.markdown-alert-tip kbd')); assert.ok(r.root.querySelector('section.footnotes sub'));
  assertInert(r, 'survival'); r.close();
});
test('closed details: copy omits hidden content, find opens it, anchors navigate into it', () => {
  const r = reader();
  r.render('<details><summary>Sum</summary>\n\nHidden secret text\n\n<a name="deep"></a>Deep\n\n</details>\n\n<h3 id="custom">Custom</h3>\n\n<picture><source srcset="dark.png" media="(prefers-color-scheme: dark)"><img src="light.png" alt="Logo"></picture> <kbd>K</kbd> <mark>M</mark>\n\nVisible', { baseURL: 'file:///tmp/docs/' });
  const data = clipboard(r), plain = data['text/plain'], html = data['text/html'];
  assert.ok(plain.includes('Sum') && plain.includes('Visible') && plain.includes('Logo'), plain);
  assert.ok(!plain.includes('Hidden secret'), plain); assert.ok(!html.includes('Hidden secret'), html);
  assert.ok(/^Sum\n/.test(plain), plain);
  assert.ok(!html.includes('user-content-') && !html.includes('mdview-image') && !html.includes('<source'), html);
  const doc = new JSDOM(html).window.document;
  assert.match(doc.querySelector('kbd').style.fontFamily, /Courier New/); assert.ok(doc.querySelector('mark').style.backgroundColor);
  const details = r.root.querySelector('details');
  assert.equal(r.window.mdview.find('secret', 1, true).count, 1); assert.equal(details.open, true);
  details.open = false;
  assert.equal(r.window.mdview.scrollToHeading('#deep'), true); assert.equal(details.open, true);
  assert.equal(r.window.mdview.scrollToHeading('custom'), true);
  assert.equal(r.window.mdview.scrollToHeading('#user-content-custom'), true);
  r.close();
});
test('author ids and names cannot clobber DOM or renderer globals', () => {
  const r = reader();
  r.render('<img name="getElementById" src="a.png"> <a name="mdview"></a> <a id="cookie"></a>\n\n<div id="mdview">x</div>\n\n<div id="document">y</div>\n\n<form name="body"></form>');
  assert.equal(typeof r.window.document.getElementById, 'function'); assert.equal(typeof r.window.mdview.render, 'function');
  assert.equal(r.window.document.body.tagName, 'BODY'); assert.equal(r.window.document.getElementById('document'), r.root);
  assert.ok(r.root.querySelector('#user-content-mdview')); assert.ok(r.root.querySelector('a[name="user-content-mdview"]'));
  assert.equal(r.root.querySelector('img').hasAttribute('name'), false);
  assertInert(r, 'clobbering'); r.close();
});
test('GitHub/CommonMark HTML block rules: unknown components stay literal, generics stay text', () => {
  const r = reader();
  r.render('<Component>\n**bold**\n\nUse Vec<T> and Option<String>, `Vec<T>` too.');
  assert.equal(r.root.querySelectorAll('strong').length, 0); assert.ok(r.root.textContent.includes('<Component>\n**bold**'));
  assert.equal(r.root.querySelector('p').textContent, 'Use Vec<T> and Option<String>, Vec<T> too.');
  r.close();
});
test('inline author block tags cannot break trusted footnote, list, table or heading structure', () => {
  const r = reader();
  r.render('Ref one[^a] and two[^b].\n\n[^a]: First note <li>Injected item\n[^b]: Second note\n\n- item one <li>forged\n\n| x <td>forged</td> | y |\n| - | - |\n| 1 | 2 |\n\n# Title <h2>inner');
  assert.equal(r.root.querySelectorAll('section.footnotes ol > li').length, 2);
  assert.ok(r.root.querySelector('#fn-a .footnote-backref'));
  assert.match(r.root.querySelector('#fn-a').textContent, /<li>Injected item/);
  assert.equal(r.root.querySelectorAll('ul > li').length, 1);
  assert.equal(r.root.querySelectorAll('thead th').length, 2);
  assert.equal(r.root.querySelectorAll('h2:not(#footnote-label)').length, 0);
  assert.match(clipboard(r)['text/plain'], /\[2\] Second note/);
  r.render('Press <kbd>Ctrl</kbd> and <sub>2</sub><br>next');
  assert.ok(r.root.querySelector('p kbd') && r.root.querySelector('p sub') && r.root.querySelector('p br'));
  r.close();
});
test('outline navigation prefers a heading over an author element with the same id', () => {
  const r = reader();
  r.render('<p id="intro">spoof</p>\n\nfiller\n\n# user-content-intro\n');
  let target = null;
  r.window.HTMLElement.prototype.scrollIntoView = function () { target = this; };
  assert.equal(r.window.mdview.scrollToHeading('user-content-intro'), true);
  assert.equal(target.tagName, 'H1');
  r.render('<p id="intro">author</p>\n\nText');
  r.window.mdview.scrollToHeading('intro'); assert.equal(target.tagName, 'P');
  r.close();
});
test('many identical headings get unique ids in linear time', () => {
  const r = reader();
  const start = Date.now(); r.render('\n='.repeat(16000) + 'x');
  assert.ok(Date.now() - start < 1500, `took ${Date.now() - start} ms`);
  r.render('# A\n\n# A\n\n# A-1\n\n# A');
  assert.deepEqual(Array.from(r.root.querySelectorAll('h1'), h => h.id), ['a', 'a-1', 'a-1-1', 'a-2']);
  r.close();
});

// Mermaid diagrams (T-0022). A stub stands in for vendor/mermaid.min.js; the real bundle is smoke-tested last.
function mermaidStub(options = {}) {
  const calls = [];
  return { calls, renders: () => calls.filter(call => call.type === 'render'),
    initialize(config) { calls.push({ type: 'initialize', config: JSON.parse(JSON.stringify(config)) }); },
    async render(id, source) {
      calls.push({ type: 'render', id, source });
      if (options.leaveTemp) { const temp = options.document.createElement('div'); temp.id = 'd' + id; options.document.body.append(temp); }
      if (options.block) await options.block;
      if (/\bbad\b/.test(source)) throw new Error(options.message || 'Parse error on line 2: bad');
      const label = source.split('\n')[1]?.trim() || '';
      return { svg: `<svg id="${id}" width="100%" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160" style="max-width: 320px;" role="graphics-document"><style>#${id} .node{fill:red}</style><g><text>Label ${label.replace(/[<&]/g, '')}</text></g></svg>` };
    } };
}
const mermaidScripts = r => r.window.document.querySelectorAll('script[src="vendor/mermaid.min.js"]');
function loadMermaid(r, stub, event = 'load') {
  const scripts = mermaidScripts(r);
  assert.equal(scripts.length, 1, 'exactly one Mermaid loader');
  if (stub) r.window.mermaid = stub;
  scripts[0].dispatchEvent(new r.window.Event(event));
}
const settled = r => r.window.mdview.diagramsSettled();
const figuresOf = r => Array.from(r.root.querySelectorAll('figure.mermaid'));
test('mermaid fences become nonce-tagged figures with the exact source; other fences unchanged', () => {
  const r = reader(), source = 'graph TD\n  A["a < b & c"] --> B\n\n  B --> C\n';
  r.render('```mermaid\n' + source + '```\n\n~~~ MERMAID\nsequenceDiagram\n  A->>B: hi\n~~~\n\n- item\n\n  ```mermaid\n  graph LR\n    X-->Y\n  ```\n\n> ```mermaid\n> pie\n>   "a" : 1\n> ```\n\n```js\nlet x = 1;\n```\n\n```mermaidx\nnot a diagram\n```');
  const figures = figuresOf(r);
  assert.equal(figures.length, 4);
  const nonce = figures[0].dataset.mermaid;
  assert.match(nonce, /^[0-9a-f]{16,}$/);
  for (const figure of figures) {
    assert.equal(figure.dataset.mermaid, nonce); assert.equal(figure.dataset.state, 'pending');
    assert.deepEqual(Array.from(figure.children, child => `${child.tagName}.${child.className}`), ['BUTTON.copy-code', 'DIV.mermaid-svg', 'FIGCAPTION.mermaid-error', 'PRE.mermaid-source']);
    assert.equal(figure.querySelector('figcaption').hidden, true);
  }
  assert.equal(figures[0].querySelector('pre code').textContent, source);
  assert.equal(figures[1].querySelector('pre code').textContent, 'sequenceDiagram\n  A->>B: hi\n');
  assert.ok(figures[2].closest('li')); assert.equal(figures[2].querySelector('pre code').textContent, 'graph LR\n  X-->Y\n');
  assert.ok(figures[3].closest('blockquote')); assert.equal(figures[3].querySelector('pre code').textContent, 'pie\n  "a" : 1\n');
  assert.deepEqual(Array.from(r.root.querySelectorAll('.code-block code'), code => code.textContent), ['let x = 1;\n', 'not a diagram\n']);
  const other = reader(); other.render('```mermaid\ngraph TD\n```');
  assert.notEqual(figuresOf(other)[0].dataset.mermaid, nonce, 'nonce is random per page');
  other.close(); r.close();
});
test('Mermaid loads lazily: no script without diagrams and one loader across renders', () => {
  const r = reader(); r.render('# Plain\n\n```js\nx\n```\n\nText mentioning mermaid.');
  assert.equal(mermaidScripts(r).length, 0); assert.equal(r.window.mermaid, undefined);
  r.render('```mermaid\ngraph TD\n  A-->B\n```'); r.render('```mermaid\ngraph TD\n  A-->C\n```');
  assert.equal(mermaidScripts(r).length, 1); r.close();
});
test('a failed or empty Mermaid load leaves every diagram as visible source with an error', async () => {
  for (const [event, stub] of [['error', null], ['load', null], ['load', { render: 'not a function' }]]) {
    const r = reader(); r.render('```mermaid\ngraph TD\n  A-->B\n```\n\n```mermaid\npie\n```');
    loadMermaid(r, stub, event); await settled(r);
    for (const figure of figuresOf(r)) {
      assert.equal(figure.dataset.state, 'error', event);
      assert.equal(figure.querySelector('figcaption').hidden, false);
      assert.match(figure.querySelector('figcaption').textContent, /^Diagram could not be rendered: \S/);
      assert.ok(figure.querySelector('pre code').textContent.length > 0);
      assert.equal(figure.querySelector('svg'), null);
    }
    r.close();
  }
});
test('rendered diagrams get a rem-sized SVG, hidden source, strict settings and no leftovers', async () => {
  const r = reader(), stub = mermaidStub({ leaveTemp: true, document: r.window.document });
  r.render('Intro\n\n```mermaid\ngraph TD\n  A-->B\n```');
  loadMermaid(r, stub); await settled(r);
  const figure = figuresOf(r)[0], svg = figure.querySelector('.mermaid-svg > svg');
  assert.equal(figure.dataset.state, 'rendered'); assert.equal(figure.dataset.theme, 'default');
  assert.ok(svg); assert.equal(svg.getAttribute('width'), null); assert.equal(svg.getAttribute('height'), null);
  assert.equal(svg.style.width, '20rem'); assert.equal(svg.style.maxWidth, '100%'); assert.equal(svg.style.height, 'auto');
  assert.equal(figure.querySelector('figcaption').hidden, true);
  const config = stub.calls.find(call => call.type === 'initialize').config;
  assert.equal(config.startOnLoad, false); assert.equal(config.securityLevel, 'strict');
  assert.equal(config.suppressErrorRendering, true); assert.equal(config.theme, 'default'); assert.equal(config.layout, 'dagre');
  for (const key of ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'suppressErrorRendering', 'maxEdges', 'themeCSS']) assert.ok(config.secure.includes(key), key);
  assert.match(config.fontFamily, /-apple-system/);
  const [call] = stub.renders();
  assert.match(call.id, new RegExp(`^mdview-mermaid-${figure.dataset.mermaid}-\\d+-0$`));
  assert.equal(call.source, 'graph TD\n  A-->B\n');
  assert.equal(r.window.document.querySelector('body > [id^="dmdview-mermaid"]'), null, 'temporary Mermaid container removed');
  r.close();
});
test('Mermaid error messages are shown as text next to the visible source', async () => {
  const r = reader(), stub = mermaidStub({ message: 'Parse error <img src=x onerror="window.__pwned=1">' });
  r.render('```mermaid\ngraph TD\n  bad\n```'); loadMermaid(r, stub); await settled(r);
  const figure = figuresOf(r)[0];
  assert.equal(figure.dataset.state, 'error');
  assert.equal(figure.querySelector('figcaption').textContent, 'Diagram could not be rendered: Parse error <img src=x onerror="window.__pwned=1">');
  assert.equal(figure.querySelector('img'), null); assert.equal(r.window.__pwned, undefined);
  assert.equal(figure.querySelector('pre code').textContent, 'graph TD\n  bad\n'); r.close();
});
test('a render that finishes after the document changed is not applied and stops its queue', async () => {
  let release; const block = new Promise(resolve => { release = resolve; });
  const r = reader(), stub = mermaidStub({ block });
  r.render('```mermaid\ngraph TD\n  A-->B\n```\n\n```mermaid\ngraph TD\n  E-->F\n```'); loadMermaid(r, stub);
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(stub.renders().length, 1);
  r.render('Replaced\n\n```mermaid\ngraph TD\n  C-->D\n```');
  release(); await settled(r);
  assert.deepEqual(stub.renders().map(call => call.source.split('\n')[1].trim()), ['A-->B', 'C-->D']);
  assert.equal(r.root.querySelectorAll('svg').length, 1); assert.equal(r.root.querySelector('svg text').textContent, 'Label C-->D'); r.close();
});
test('unchanged diagrams re-render synchronously from the cache; repeated sources render separately', async () => {
  const r = reader(), stub = mermaidStub(), diagram = '```mermaid\ngraph TD\n  A-->B\n```';
  r.render(`One\n\n${diagram}\n\n${diagram}`); loadMermaid(r, stub); await settled(r);
  const ids = stub.renders().map(call => call.id);
  assert.equal(ids.length, 2); assert.notEqual(ids[0], ids[1]);
  r.render(`Two\n\n${diagram}\n\n${diagram}`);
  assert.deepEqual(figuresOf(r).map(figure => figure.dataset.state), ['rendered', 'rendered'], 'cache hit is synchronous');
  assert.deepEqual(Array.from(r.root.querySelectorAll('svg'), svg => svg.id), ids);
  await settled(r); assert.equal(stub.renders().length, 2); r.close();
});
test('switching appearance re-renders with the dark theme and switching back hits the cache', async () => {
  const r = reader(), stub = mermaidStub();
  r.render('```mermaid\ngraph TD\n  A-->B\n```'); loadMermaid(r, stub); await settled(r);
  r.window.setDark(true); await settled(r);
  const figure = figuresOf(r)[0];
  assert.equal(figure.dataset.theme, 'dark'); assert.equal(stub.renders().length, 2);
  assert.equal(stub.calls.filter(call => call.type === 'initialize').at(-1).config.theme, 'dark');
  r.window.setDark(false);
  assert.equal(figure.dataset.theme, 'default'); assert.equal(stub.renders().length, 2);
  const dark = reader({ dark: true }), darkStub = mermaidStub();
  dark.render('```mermaid\ngraph TD\n  A-->B\n```'); loadMermaid(dark, darkStub); await settled(dark);
  assert.equal(figuresOf(dark)[0].dataset.theme, 'dark'); dark.close(); r.close();
});
test('copying a diagram gives fenced Markdown source once and never SVG markup', async () => {
  const r = reader(), stub = mermaidStub(), source = 'graph TD\n  A["x ``` y"]-->B\n';
  r.render('Before\n\n```mermaid\n' + source + '```\n\nAfter'); loadMermaid(r, stub); await settled(r);
  const all = clipboard(r);
  assert.equal(all['text/plain'], 'Before\n\n````mermaid\n' + source + '````\n\nAfter');
  for (const forbidden of ['<svg', '<style', 'foreignObject', 'Label', 'Copy']) assert.ok(!all['text/html'].includes(forbidden), forbidden);
  assert.ok(all['text/html'].includes('````mermaid'));
  const label = r.root.querySelector('svg text').firstChild;
  assert.equal(clipboard(r, label, label)['text/plain'], '````mermaid\n' + source + '````');
  r.window.getSelection().removeAllRanges();
  figuresOf(r)[0].querySelector('button').click();
  assert.equal(r.messages.at(-1).type, 'copy'); assert.equal(r.messages.at(-1).text, source); r.close();
});
test('find ignores diagram labels and source', async () => {
  const r = reader(), stub = mermaidStub();
  r.render('Visible zebra text\n\n```mermaid\ngraph TD\n  zebra-->giraffe\n```');
  assert.equal(r.window.mdview.find('giraffe', 1, true).count, 0, 'pending source is not searchable');
  loadMermaid(r, stub); await settled(r);
  assert.equal(r.window.mdview.find('zebra', 1, true).count, 1);
  assert.equal(r.window.mdview.find('giraffe', 1, true).count, 0); r.close();
});
test('oversized diagrams fail explicitly without loading Mermaid', async () => {
  const r = reader(), source = 'graph TD\n' + 'A-->B\n'.repeat(9000);
  r.render('```mermaid\n' + source + '```'); await settled(r);
  const figure = figuresOf(r)[0];
  assert.equal(figure.dataset.state, 'error'); assert.match(figure.querySelector('figcaption').textContent, /50 000 characters/);
  assert.equal(figure.querySelector('pre code').textContent, source); assert.equal(mermaidScripts(r).length, 0); r.close();
});
test('options.diagrams === false keeps Mermaid fences as plain source code', () => {
  const r = reader(); r.render('```mermaid\ngraph TD\n  A-->B\n```', { diagrams: false });
  assert.equal(figuresOf(r).length, 0); assert.equal(mermaidScripts(r).length, 0);
  assert.equal(r.root.querySelector('code.language-mermaid').textContent, 'graph TD\n  A-->B\n'); r.close();
});
test('diagrams in view render first, and a diagram above the viewport keeps the reading position', async () => {
  const r = reader(), stub = mermaidStub();
  r.render('```mermaid\ngraph TD\n  Below\n```\n\n```mermaid\ngraph TD\n  Visible\n```\n\n```mermaid\ngraph TD\n  Above\n```');
  const [below, visible, above] = figuresOf(r);
  below.getBoundingClientRect = () => ({ top: 2000, bottom: 2100, height: 100 });
  visible.getBoundingClientRect = () => ({ top: 100, bottom: 200, height: 100 });
  above.getBoundingClientRect = () => above.dataset.state === 'rendered' ? { top: -600, bottom: -300, height: 300 } : { top: -600, bottom: -500, height: 100 };
  loadMermaid(r, stub); await settled(r);
  assert.deepEqual(stub.renders().map(call => call.source.split('\n')[1].trim()), ['Visible', 'Below', 'Above']);
  assert.deepEqual(r.window.scrolledBy, [200]); r.close();
});
test('the vendored Mermaid bundle loads as a classic script and parses valid and invalid diagrams', async () => {
  // jsdom has no SVG layout (getBBox), so full rendering is covered by the GUI checks.
  const dom = new JSDOM('<!doctype html><body></body>', { runScripts: 'dangerously', url: 'file:///reader/index.html' });
  const window = dom.window, script = window.document.createElement('script');
  script.textContent = fs.readFileSync(path.join(web, 'vendor/mermaid.min.js'), 'utf8');
  window.document.head.append(script);
  assert.equal(typeof window.mermaid.render, 'function');
  window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true, layout: 'dagre' });
  assert.equal((await window.mermaid.parse('graph TD\n  A-->B')).diagramType, 'flowchart-v2');
  assert.equal((await window.mermaid.parse('sequenceDiagram\n  A->>B: hi')).diagramType, 'sequence');
  await assert.rejects(window.mermaid.parse('graph TD\n  A-->'), /Parse error/);
  window.close();
});

// Emoji shortcodes and appearance-tagged images (T-0025).
const emojiCount = node => (node.textContent.match(/\p{Extended_Pictographic}/gu) || []).length;
test('known GitHub emoji shortcodes render as Unicode emoji; emoticons and unknown names stay text', () => {
  const r = reader();
  r.render(':rocket: :+1: :-1: :white_check_mark: :100: :tada:');
  assert.equal(r.root.querySelector('p').textContent, '🚀 👍 👎 ✅ 💯 🎉');
  const literal = [':unknown_code:', ':octocat:', ':shipit:', '10:30:45', 'a:zz:c', ':) :D :$ ;) <3 :-)'];
  for (const text of literal) { r.render(text); assert.equal(r.root.textContent.trim(), text, text); }
  r.render('\\:rocket: and :rocket\\:'); assert.equal(r.root.textContent.trim(), ':rocket: and :rocket:');
  r.render('Shortcodes need no word boundary, as on GitHub: a:tada:b'); assert.ok(r.root.textContent.includes('a🎉b'));
  r.close();
});
test('emoji leave code, math, link destinations, autolinks, front matter, diagrams and alert titles untouched', () => {
  const r = reader();
  r.render('---\ntitle: ":rocket: launch"\n---\n\n`:rocket:` and $:rocket:$\n\n```\n:rocket:\n```\n\n    :tada: indented\n\nSee https://example.com/:tada:/x and <https://example.com/:tada:> and [x :tada:](https://example.com/:tada:)\n\n> [!NOTE]\n> Body :tada:\n\n```mermaid\ngraph TD\n  A[:tada:] --> B\n```');
  assert.equal(r.root.querySelector('table.front-matter td').textContent, ':rocket: launch');
  assert.equal(r.root.querySelector('p > code').textContent, ':rocket:');
  assert.equal(r.root.querySelector('[data-math]').dataset.math, '$:rocket:$');
  assert.deepEqual(Array.from(r.root.querySelectorAll('pre > code'), n => n.textContent), [':rocket:\n', ':tada: indented\n', 'graph TD\n  A[:tada:] --> B\n']);
  const links = Array.from(r.root.querySelectorAll('a'), a => [a.getAttribute('href'), a.textContent]);
  assert.deepEqual(links, [['https://example.com/:tada:/x', 'https://example.com/:tada:/x'], ['https://example.com/:tada:', 'https://example.com/:tada:'], ['https://example.com/:tada:', 'x 🎉']]);
  assert.equal(r.root.querySelector('.markdown-alert-title').textContent, 'Note');
  assert.equal(r.root.querySelector('.markdown-alert p:not(.markdown-alert-title)').textContent, 'Body 🎉');
  r.render('![:rocket: alt](a.png)'); assert.equal(r.root.querySelector('img').alt, ':rocket: alt');
  r.close();
});
test('emoji in author HTML text follow GitHub: converted in text, not inside code, pre or tt', () => {
  const r = reader();
  r.render('Press <kbd>:rocket:</kbd> or <code>:tada:</code> <tt>:tada:</tt> then :tada:\n\n<p align="center">:rocket: Project</p>\n\n<pre>\n:rocket:\n</pre>\n\n<div>\n<code>:tada:</code> :100:\n</div>');
  assert.equal(r.root.querySelector('kbd').textContent, '🚀');
  assert.equal(r.root.querySelector('p > code').textContent, ':tada:');
  assert.equal(r.root.querySelector('tt').textContent, ':tada:');
  assert.ok(r.root.querySelector('p').textContent.endsWith('then 🎉'));
  assert.equal(r.root.querySelector('p[align="center"]').textContent, '🚀 Project');
  assert.equal(r.root.querySelector('pre').textContent, ':rocket:\n');
  assert.equal(r.root.querySelector('div').textContent.trim(), ':tada: 💯');
  assertInert(r, 'emoji html'); r.close();
});
test('emoji headings keep the shortcode in the id and show the emoji in the outline; task lists still work', () => {
  const r = reader();
  r.render('# :rocket: Launch\n\n## Done :white_check_mark:\n\n- [x] :rocket: shipped\n- [ ] :tada: party');
  const headings = r.messages.find(m => m.type === 'headings').headings;
  assert.deepEqual(Array.from(headings, h => [h.id, h.title]), [['rocket-launch', '🚀 Launch'], ['done-white_check_mark', 'Done ✅']]);
  assert.equal(r.root.querySelector('h1').id, 'rocket-launch'); assert.equal(r.root.querySelector('h1').textContent, '🚀 Launch');
  const boxes = r.root.querySelectorAll('li.task-list-item input.task-checkbox');
  assert.equal(boxes.length, 2); assert.equal(boxes[0].checked, true);
  assert.deepEqual(Array.from(r.root.querySelectorAll('li'), li => li.textContent.trim()), ['🚀 shipped', '🎉 party']);
  r.close();
});
test('copy and find see the rendered emoji, not the shortcode', () => {
  const r = reader();
  r.render('Launch :rocket: now.\n\n`:rocket:` stays code.');
  const copied = clipboard(r);
  assert.equal(copied['text/plain'], 'Launch 🚀 now.\n\n:rocket: stays code.');
  assert.ok(copied['text/html'].includes('Launch 🚀 now.'));
  const found = r.window.mdview.find('🚀', 1, true);
  assert.equal(found.count, 1); assert.equal(r.window.mdview.find(':rocket:', 1, true).count, 1);
  r.close();
});
test('#gh-dark-mode-only and #gh-light-mode-only tag Markdown and HTML images and their fallbacks', () => {
  const r = reader();
  r.render('![Light](logo-light.png#gh-light-mode-only) ![Dark](logo-dark.png#gh-dark-mode-only) ![Other](x.png#gh-dark-mode-only-x) ![Remote](https://example.org/d.png#gh-dark-mode-only)\n\n<img src="html-dark.png#gh-dark-mode-only" alt="HTML dark"> <img src="html-light.png#gh-light-mode-only" alt="HTML light">', { baseURL: 'file:///tmp/docs/' });
  const images = Array.from(r.root.querySelectorAll('img'));
  assert.deepEqual(images.map(img => img.className), ['gh-light-mode-only', 'gh-dark-mode-only', '', 'gh-dark-mode-only', 'gh-dark-mode-only', 'gh-light-mode-only']);
  assert.equal(images[0].src, 'mdview-image://local/tmp/docs/logo-light.png');
  assert.equal(images[4].src, 'mdview-image://local/tmp/docs/html-dark.png');
  assert.equal(images[3].src, 'https://example.org/d.png#gh-dark-mode-only');
  images[1].dispatchEvent(new r.window.Event('error'));
  const fallback = r.root.querySelector('.image-error');
  assert.ok(fallback.classList.contains('gh-dark-mode-only')); assert.match(fallback.textContent, /Dark/);
  r.render('![Broken](ftp://example.org/x.png#gh-light-mode-only)');
  assert.equal(r.root.querySelector('.image-error').className, 'image-error gh-light-mode-only');
  assertInert(r, 'variants'); r.close();
});
test('reader CSS hides the inactive variant by appearance', () => {
  const css = fs.readFileSync(path.join(web, 'reader.css'), 'utf8').replace(/\s+/g, ' ');
  assert.ok(css.includes('@media not all and (prefers-color-scheme: dark) { .gh-dark-mode-only { display:none !important; } }'), 'light hides dark variant');
  assert.ok(css.includes('@media (prefers-color-scheme: dark) { .gh-light-mode-only { display:none !important; } }'), 'dark hides light variant');
});
test('copy and find include only the variant visible in the current appearance', () => {
  for (const dark of [false, true]) {
    const r = reader({ dark });
    r.render('Logo: ![Light logo](l.png#gh-light-mode-only)![Dark logo](d.png#gh-dark-mode-only) end.\n\n![Broken light](ftp://example.org/x.png#gh-light-mode-only) ![Broken dark](ftp://example.org/x.png#gh-dark-mode-only)');
    const copied = clipboard(r), want = dark ? 'Dark' : 'Light', not = dark ? 'Light' : 'Dark';
    assert.ok(copied['text/plain'].startsWith(`Logo: ${want} logo end.`), copied['text/plain']);
    assert.ok(copied['text/plain'].includes(`Broken ${want.toLowerCase()}`));
    for (const format of ['text/plain', 'text/html']) assert.ok(!copied[format].includes(`${not} logo`) && !copied[format].includes(`Broken ${not.toLowerCase()}`), `${format}: ${copied[format]}`);
    assert.equal(r.window.mdview.find(`Broken ${not.toLowerCase()}`, 1, true).count, 0);
    assert.equal(r.window.mdview.find(`Broken ${want.toLowerCase()}`, 1, true).count, 1);
    // The same nodes answer to an appearance switch without a re-render.
    r.window.setDark(!dark);
    assert.ok(clipboard(r)['text/plain'].includes(`${not} logo`));
    r.close();
  }
});
