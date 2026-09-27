"""Check review evidence and positive controls; this characterizes known defects."""
from pathlib import Path
import re
r = Path(__file__).resolve().parent
log = (r/'evidence/runtime.log').read_text()
watch = (r/'evidence/watcher.log').read_text()
for expected in [
    'key=true appActive=true',
    'COPY single handled=true value=Optional("Alpha first paragraph.")',
    'COPY cross handled=true value=Optional("Alpha first paragraph.")',
    'COPY select-all handled=true/true value=Optional("Alpha first paragraph.")',
    'LINK markdown click callbacks=[]',
    'LINK after positive control callbacks=[https://example.com/control]',
    'after=[62.0, 62.0]',
    'SCROLL key=125 modifiers=0 y=40.0',
    'SCROLL key=115 modifiers=0 y=0.0',
    'HARNESS COMPLETE',
]:
    assert expected in log, expected
for expected in [
    'WATCH in-place: ["in-place-1"]', 'WATCH atomic-1: ["atomic-1"]',
    'WATCH atomic-2: []', 'WATCH in-place-after-atomic: []',
    'descriptor growth after 25 lifecycles: 25', 'WATCH COMPLETE',
]:
    assert expected in watch, expected
assert not (r/'evidence/runtime-errors.log').read_text()
for project in ['Markd', 'Glim']:
    html = (r/'evidence'/f'{project}-02-math.html').read_text()
    assert '<pre class="hljs"><code>x^2 + y^2 = z^2' in html
    assert 'Escaped dollars: $5 and $10.' in html
    html = (r/'evidence'/f'{project}-04-math-integrity.html').read_text()
    assert html.count('<mtr>') == 2
    html = (r/'evidence'/f'{project}-03-structure.html').read_text()
    assert 'QUOTE CODE SHOULD APPEAR' in html and 'LIST CODE SHOULD APPEAR' in html
    html = (r/'evidence'/f'{project}-01-reading.html').read_text()
    assert html.count('type="checkbox"') == 2 and '<img ' in html
for doc in ['REVIEW.md','COMPARISON.md']:
    for link in re.findall(r'\]\(([^)]+)\)', (r/doc).read_text()):
        if '://' not in link and not link.startswith('#'):
            assert (r/link.split('#')[0]).exists(), (doc, link)
assert 'Build complete!' in (r/'evidence/build-release.log').read_text()
assert 'no tests found' in (r/'evidence/swift-test.log').read_text()
print('Evidence consistency verified: active GUI and positive controls, reproduced defects, watcher controls, competitor parser output, build/test outcomes and local report links.')
print('This is a review evidence check, not a passing product regression suite.')
