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
  for (const file of ['vendor/markdown-it.min.js', 'vendor/katex.min.js', 'vendor/highlight.min.js', 'renderer.js']) window.eval(fs.readFileSync(path.join(web, file), 'utf8'));
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
