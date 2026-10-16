#!/usr/bin/env python3
"""Assemble an unsigned release handoff. Never installs on or signs using a Roku."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys, zipfile
ROOT = Path(__file__).resolve().parents[1]

def main():
    for command in (['npm','run','check'],['npm','test'],['npm','run','build'],[sys.executable,'scripts/preflight.py']):
        subprocess.run(command,cwd=ROOT,check=True)
    version = json.loads((ROOT/'package.json').read_text())['version']
    destination = ROOT.parent / f'pro-announcement-looper-release-{version}'
    if destination.exists(): shutil.rmtree(destination)
    destination.mkdir()
    for kind in ('player','screensaver'):
        shutil.copy2(ROOT/'out'/f'pro-announcement-looper-{kind}.zip',destination/f'pro-announcement-looper-{kind}-{version}-unsigned.zip')
    signed = ROOT/'out/signed'
    if signed.exists():
        for kind in ('player','screensaver'):
            package = signed/f'pro-announcement-looper-{kind}-{version}.pkg'
            if package.exists(): shutil.copy2(package,destination/package.name)
    shutil.copytree(ROOT/'store',destination/'store')
    shutil.copytree(ROOT/'branding',destination/'branding')
    for name in ('README.md','LICENSE'):
        shutil.copy2(ROOT/name,destination/name)
    shutil.copy2(ROOT/'out/local-preflight.json',destination/'local-preflight.json')
    (destination/'START-HERE.md').write_text(f'''# Pro Announcement Looper {version} release candidate

Approved icon exports, unsigned player/screensaver ZIPs, listing copy, reviewer instructions and publisher-policy drafts are included.

Open store/SIGNING-AND-SUBMISSION.md for remaining signing and Store steps. If signed .pkg files are present, they are copies of packages previously created by the signing device. The ZIPs are unsigned. See store/release-status.json for actual device and certification status; the local build itself never changes a Roku.

Run npm run release from the source repository to regenerate this bundle. SHA256SUMS verifies each included file. The manifest uses rsg_version=1.3. Completed hardware checks and remaining tests are recorded in store/REVIEWER-NOTES.md.
''')
    sums = []
    for file in sorted(destination.rglob('*')):
        if file.is_file():
            sums.append(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.relative_to(destination).as_posix())
    (destination/'SHA256SUMS').write_text('\n'.join(sums)+'\n')
    bundle = Path(str(destination) + '.zip')
    with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(destination.rglob('*')):
            if file.is_file(): archive.write(file,file.relative_to(destination))
    print(f'Release directory: {destination}')
    print(f'Release bundle: {bundle}')

if __name__ == '__main__':
    main()
