#!/usr/bin/env python
"""Compile the unchanged production views into a separate AppKit review host."""
from pathlib import Path
import subprocess
import plistlib
import shutil
import tempfile
root = Path(__file__).resolve().parents[2]
review = Path(__file__).resolve().parent
build = root / '.build/arm64-apple-macosx/debug'
objects = [p for p in (build / 'mdview.product/Objects.LinkFileList').read_text().splitlines() if '/mdview.build/' not in p]
cmd = ['swiftc', '-sdk', '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk', '-target', 'arm64-apple-macosx13.0', '-I', str(build/'Modules')]
for module in ['swift-cmark/src/include', 'swift-cmark/extensions/include', 'swift-markdown/Sources/CAtomic/include']:
    cmd += ['-Xcc', '-I'+str(root/'.build/checkouts'/module)]
    cmd += ['-Xcc', '-fmodule-map-file='+str(root/'.build/checkouts'/module/'module.modulemap')]
cmd += [str(root/'Sources'/p) for p in ['ContentView.swift','MarkdownDocument.swift','MathView.swift']]
cmd += [str(review/'ReviewHarness.swift'), *objects, '-o', str(review/'evidence/review-harness')]
subprocess.run(cmd, check=True, cwd=root)
# LaunchServices is essential: direct CLI launch left the window inactive,
# making even the positive single-paragraph selection control fail.
with tempfile.TemporaryDirectory(prefix='mdview-review-app-') as tmp:
    contents = Path(tmp)/'Review.app/Contents'
    (contents/'MacOS').mkdir(parents=True)
    shutil.copy2(review/'evidence/review-harness', contents/'MacOS/review-harness')
    (contents/'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable':'review-harness', 'CFBundleIdentifier':'com.mdview.review-harness',
        'CFBundleName':'mdview Review Harness', 'CFBundlePackageType':'APPL',
        'NSHighResolutionCapable':True,
    }))
    log = review/'evidence/runtime.log'
    errors = review/'evidence/runtime-errors.log'
    log.write_text(''); errors.write_text('')
    subprocess.run(['open','-n','-W',str(contents.parent),'--stdout',str(log),'--stderr',str(errors),'--args',str(review/'evidence')],check=True,timeout=120)
    if 'HARNESS COMPLETE' not in log.read_text():
        raise RuntimeError(errors.read_text())
print((review/'evidence/runtime.log').read_text())
with (review/'evidence/watcher.log').open('w') as log:
    subprocess.run([str(review/'evidence/review-harness'),str(review/'evidence'),'--watch-only'],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
print((review/'evidence/watcher.log').read_text())
