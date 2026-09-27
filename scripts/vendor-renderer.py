#!/usr/bin/env python3
"""Reproduce offline assets from pinned npm archives; verify hashes before extracting.
Usage: python scripts/vendor-renderer.py [directory-containing-npm-pack-archives]
With no directory, download archives from registry.npmjs.org.
"""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'Sources/Resources/Web/vendor'
PACKAGES = [
    ('markdown-it', '15.0.2', 'markdown-it-15.0.2.tgz', 'MIT', {'dist/browser/markdown-it.umd.min.js': 'markdown-it.min.js'}),
    ('katex', '0.18.9', 'katex-0.18.9.tgz', 'MIT', {'dist/katex.min.js': 'katex.min.js', 'dist/katex.min.css': 'katex.min.css'}),
    ('@highlightjs/cdn-assets', '11.12.0', 'highlightjs-cdn-assets-11.12.0.tgz', 'BSD-3-Clause', {'highlight.min.js': 'highlight.min.js'}),
]
manifest_path = ROOT / 'manifest.json'
previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
expected = {(p['name'], p['version']): p['sha256'] for p in previous}
manifest = []
for name, version, archive, license_name, files in PACKAGES:
    url = f'https://registry.npmjs.org/{name}/-/{name.split("/")[-1]}-{version}.tgz'
    data = (Path(sys.argv[1]) / archive).read_bytes() if len(sys.argv) > 1 else urllib.request.urlopen(url).read()
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
    manifest.append(dict(name=name, version=version, license=license_name, archive=url, sha256=digest, files=sorted(files.values())))
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Vendored {len(manifest)} pinned packages into {ROOT}')
