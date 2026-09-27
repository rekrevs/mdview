#!/usr/bin/env python
"""Run production reader code in a LaunchServices app with packaged resources."""
from pathlib import Path
import os, platform, plistlib, shutil, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
output=root/'.build/reader-checks'; output.mkdir(parents=True,exist_ok=True)
sdk=os.environ.get('MDVIEW_SDK')
if not sdk:
    fallback=Path('/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk')
    sdk=str(fallback) if fallback.exists() else subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
build=Path(subprocess.check_output([str(root/'scripts/swift-tool.sh'),'build','--show-bin-path'],cwd=root,text=True).strip())
accessors=list((root/'.build').glob('**/mdview.build/DerivedSources/resource_bundle_accessor.swift'))
accessor=build/'mdview.build/DerivedSources/resource_bundle_accessor.swift'
if not accessor.exists(): accessor=accessors[0]
with tempfile.TemporaryDirectory(prefix='mdview-reader-check-') as tmp:
    contents=Path(tmp)/'ReaderChecks.app/Contents'; (contents/'MacOS').mkdir(parents=True)
    (contents/'Resources').mkdir()
    bundle=root/'mdview.app/Contents/Resources/mdview_mdview.bundle'
    if not bundle.exists(): raise RuntimeError('Run make bundle before the GUI checks')
    shutil.copytree(bundle, contents/'Resources'/bundle.name)
    sources=[p for p in (root/'Sources').glob('*.swift') if p.name!='mdviewApp.swift']
    cmd=['swiftc','-sdk',sdk,'-target',f'{platform.machine()}-apple-macosx13.0',*map(str,sources),str(accessor),str(root/'Tests/Integration/ReaderChecks.swift'),'-o',str(contents/'MacOS/ReaderChecks')]
    subprocess.run(cmd,cwd=root,check=True)
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ReaderChecks','CFBundleIdentifier':'com.mdview.reader-checks','CFBundleName':'mdview Reader Checks','CFBundlePackageType':'APPL','NSHighResolutionCapable':True}))
    log=output/'checks.log'; errors=output/'errors.log'; log.write_text('');errors.write_text('')
    subprocess.run(['open','-n','-W',str(contents.parent),'--stdout',str(log),'--stderr',str(errors),'--args',str(root),str(output)],check=True,timeout=180)
    print(log.read_text()); print(errors.read_text())
    result=log.read_text()
    if 'RESULT ' not in result or 'FAIL ' in result: raise SystemExit(1)
