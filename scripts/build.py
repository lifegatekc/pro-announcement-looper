#!/usr/bin/env python3
"""Create sideloadable ZIPs and debugger folders using only Python's standard library."""
from pathlib import Path
import shutil
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'out'

def build(kind):
    target = OUT / kind
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    shutil.copy(ROOT / 'manifests' / kind, target / 'manifest')
    for folder in ('components', 'images'):
        shutil.copytree(ROOT / folder, target / folder)
    (target / 'source').mkdir()
    for name in ('common.brs', 'model.brs', kind + '.brs'):
        shutil.copy(ROOT / 'source' / name, target / 'source' / name)
    for xml in (target / 'components').glob('*.xml'):
        ET.parse(xml)
    entry = (target / 'source' / (kind + '.brs')).read_text()
    assert ('sub Main()' in entry) == (kind == 'player')
    package = OUT / ('pro-announcement-looper-' + kind + '.zip')
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(target.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(target))
    print(f'Built {package.name} ({package.stat().st_size:,} bytes)')

if __name__ == '__main__':
    for kind in ('player', 'screensaver'):
        build(kind)
