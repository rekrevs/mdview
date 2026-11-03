#!/usr/bin/env python3
"""Reproduce offline assets from pinned npm archives; verify hashes before extracting.
Usage: python scripts/vendor-renderer.py [directory-containing-npm-pack-archives]
With no directory, download archives from registry.npmjs.org. A local directory must hold
every pinned archive (npm pack names, e.g. highlightjs-cdn-assets-11.12.0.tgz); archives of
the components bundled inside mermaid.min.js are read from its bundled/ subdirectory, or
downloaded when that is missing. Each is checked against the lockfile integrity recorded in
scripts/mermaid-bundled.json.
"""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'Sources/Resources/Web/vendor'
BUNDLED = json.loads((Path(__file__).resolve().parent / 'mermaid-bundled.json').read_text())
PACKAGES = [
    ('markdown-it', '15.0.2', 'markdown-it-15.0.2.tgz', 'MIT', {'dist/browser/markdown-it.umd.min.js': 'markdown-it.min.js'}),
    ('katex', '0.18.9', 'katex-0.18.9.tgz', 'MIT', {'dist/katex.min.js': 'katex.min.js', 'dist/katex.min.css': 'katex.min.css'}),
    ('@highlightjs/cdn-assets', '11.12.0', 'highlightjs-cdn-assets-11.12.0.tgz', 'BSD-3-Clause', {'highlight.min.js': 'highlight.min.js'}),
    ('markdown-it-footnote', '4.0.0', 'markdown-it-footnote-4.0.0.tgz', 'MIT', {'dist/markdown-it-footnote.min.js': 'markdown-it-footnote.min.js'}),
    # Source of the GitHub alert icon paths embedded in renderer.js (kept for provenance tests).
    ('@primer/octicons', '19.42.0', 'primer-octicons-19.42.0.tgz', 'MIT', {f'build/svg/{icon}-16.svg': f'octicons/{icon}-16.svg' for icon in ('info', 'light-bulb', 'report', 'alert', 'stop')}),
    # Self-contained IIFE build (no lazy chunks); loaded only for documents with mermaid fences.
    ('mermaid', '12.2.0', 'mermaid-12.2.0.tgz', 'MIT', {'dist/mermaid.min.js': 'mermaid.min.js'}),
    # GitHub emoji shortcodes (data derived from GitHub's gemoji, MIT); global markdownitEmoji is the full plugin.
    ('markdown-it-emoji', '3.1.0', 'markdown-it-emoji-3.1.0.tgz', 'MIT', {'dist/markdown-it-emoji.min.js': 'markdown-it-emoji.min.js'}),
]


def registry_url(name, version):
    return f'https://registry.npmjs.org/{name}/-/{name.split("/")[-1]}-{version}.tgz'


def download(url):
    for attempt in range(5):  # The registry CDN occasionally truncates large responses.
        try:
            return urllib.request.urlopen(url).read()
        except Exception:
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)


def bundled_notices(local):
    """License texts of every component bundled inside mermaid.min.js, deterministic output."""
    lines = [
        'Third-party components bundled inside mermaid.min.js (mermaid 12.2.0)',
        '=' * 70, '',
        'mermaid.min.js is a single esbuild bundle. ' + BUNDLED['comment'],
        f'Lockfile: {BUNDLED["lockfile"]}', '',
        'Source code: every component below is available in source form from its npm archive,',
        'https://registry.npmjs.org/<name>/-/<name without scope>-<version>.tgz, and from the',
        'repository named in that archive. In particular, elkjs 0.9.3 is distributed here in',
        'object-code form under the Eclipse Public License 2.0; its source code is available at',
        'https://github.com/kieler/elkjs (tag 0.9.3) and https://registry.npmjs.org/elkjs/-/elkjs-0.9.3.tgz.',
        'DOMPurify 3.4.12 is used under the Apache License 2.0 (alternatively MPL-2.0); its source',
        'code is available at https://github.com/cure53/DOMPurify (tag 3.4.12).', '',
    ]
    seen = {}
    for package in BUNDLED['packages']:
        name, version = package['name'], package['version']
        archive = name.lstrip('@').replace('/', '-') + f'-{version}.tgz'
        path = Path(local) / 'bundled' / archive if local else None
        data = path.read_bytes() if path and path.exists() else download(registry_url(name, version))
        integrity = 'sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode()
        if integrity != package['integrity']:
            raise SystemExit(f'Archive integrity mismatch for bundled {name}@{version}')
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            texts = {}
            for member in tar.getmembers():
                file = member.name.split('/', 1)[-1]
                if member.isfile() and '/' not in file and re.match(r'(?i)^(licen[cs]e|copying|notice)', file) and not file.endswith(('.js', '.mjs')):
                    texts[file] = tar.extractfile(member).read().decode('utf-8', 'replace').replace('\r\n', '\n').strip()
        lines += ['-' * 70, f'{name} {version} ({package["license"]})', '-' * 70]
        if not texts:
            lines += [f'The npm archive contains no license file; its package.json declares {package["license"]}.']
        for file, text in sorted(texts.items()):
            if text in seen:
                lines += [f'{file}: identical to the {seen[text]} text above.']
            else:
                seen[text] = f'{name} {version} {file}'
                lines += [f'[{file}]', '', text]
        lines.append('')
    return '\n'.join(lines) + '\n'


manifest_path = ROOT / 'manifest.json'
previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
expected = {(p['name'], p['version']): p['sha256'] for p in previous}
local = sys.argv[1] if len(sys.argv) > 1 else None
manifest = []
for name, version, archive, license_name, files in PACKAGES:
    url = registry_url(name, version)
    data = (Path(local) / archive).read_bytes() if local else download(url)
    digest = hashlib.sha256(data).hexdigest()
    if expected.get((name, version)) and expected[(name, version)] != digest:
        raise SystemExit(f'Archive checksum mismatch for {name}')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        files['LICENSE'] = f'licenses/{name.split("/")[-1]}.txt'
        if name == 'katex':
            files.update({m.name.removeprefix('package/'): m.name.removeprefix('package/dist/') for m in tar.getmembers() if m.name.startswith('package/dist/fonts/') and m.isfile()})
        for source, target in files.items():
            path = ROOT / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(tar.extractfile('package/' + source).read())
    entry = dict(name=name, version=version, license=license_name, archive=url, sha256=digest, files=sorted(files.values()))
    if name == 'mermaid':
        (ROOT / 'licenses/mermaid-bundled.txt').write_text(bundled_notices(local))
        entry['files'] = sorted(entry['files'] + ['licenses/mermaid-bundled.txt'])
        entry['bundled'] = [dict(name=p['name'], version=p['version'], license=p['license']) for p in BUNDLED['packages']]
    manifest.append(entry)
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Vendored {len(manifest)} pinned packages into {ROOT}')
