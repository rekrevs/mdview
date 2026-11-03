const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const web = path.resolve(__dirname, '../../Sources/Resources/Web');
function reader() {
  const dom = new JSDOM('<!doctype html><main id="document"></main>', { runScripts: 'outside-only', url: 'file:///reader/index.html' });
  const window = dom.window, messages = [];
  window.webkit = { messageHandlers: { reader: { postMessage: message => messages.push(message) } } };
  window.scrollTo = () => {};
  window.HTMLElement.prototype.scrollIntoView = () => {};
  for (const file of ['vendor/markdown-it.min.js', 'vendor/markdown-it-footnote.min.js', 'vendor/katex.min.js', 'vendor/highlight.min.js', 'renderer.js']) window.eval(fs.readFileSync(path.join(web, file), 'utf8'));
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
  assert.equal(r.root.querySelectorAll('script,img,[onerror],a[href^="javascript:"]').length, 0); r.close();
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
