// Execute the checked-out applications' actual parser initialization, without their GUI.
const fs = require('fs'), vm = require('vm'), path = require('path');
const out = path.join(__dirname, 'evidence');
for (const [name, root, scripts, marker] of [
 ['Markd','/private/tmp/mdview-review-Markd/Markd/Resources/Web/js', ['markdown-it.min.js','katex.min.js','texmath.min.js','markdownItAnchor.umd.js','markdown-it-task-lists.min.js','highlight.min.js'],'// Initialize Mermaid'],
 ['Glim','/private/tmp/mdview-review-yeduk3/App/Resources/web',['markdown-it.min.js','katex/katex.min.js','texmath.js','anchors.js','tasklists.js','hljs/highlight.min.js'],'// ---- source-line mapping']
]) {
 const c = vm.createContext({console}); c.window=c; c.self=c;
 for(const f of scripts) vm.runInContext(fs.readFileSync(path.join(root,f),'utf8'),c);
 vm.runInContext(fs.readFileSync(path.join(root,'render.js'),'utf8').split(marker)[0],c);
 for(const fixture of ['01-reading','02-math','03-structure','04-math-integrity']) {
  c.fixture = fs.readFileSync(path.join(out,fixture+'.md'),'utf8');
  const html=vm.runInContext('md.render(fixture)',c);
  fs.writeFileSync(path.join(out,`${name}-${fixture}.html`),html);
  console.log(name,fixture,JSON.stringify({anchors:(html.match(/<a\b/g)||[]).length,images:(html.match(/<img\b/g)||[]).length,checkboxes:(html.match(/type="checkbox"/g)||[]).length,mathML:(html.match(/<math\b/g)||[]).length,matrixRows:(html.match(/<mtr>/g)||[]).length,quoteCode:html.includes('QUOTE CODE SHOULD APPEAR'),listCode:html.includes('LIST CODE SHOULD APPEAR')}));
 }
}
