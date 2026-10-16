#!/usr/bin/env python3
"""Local release checks only. This is not Roku certification or hardware validation."""
from pathlib import Path
import json, re, struct, zipfile
ROOT = Path(__file__).resolve().parents[1]

def png_size(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Expected PNG asset'
    return struct.unpack('>II', data[16:24])

def check():
    version = json.loads((ROOT/'package.json').read_text())['version']
    listing = json.loads((ROOT/'store/listing-en-US.json').read_text())
    assert listing['version'] == version
    results = []
    for kind in ('player','screensaver'):
        with zipfile.ZipFile(ROOT/'out'/f'pro-announcement-looper-{kind}.zip') as archive:
            names = archive.namelist()
            assert names == sorted(names)
            assert len(names) == len(set(names))
            assert all(not name.startswith('/') and '..' not in Path(name).parts for name in names)
            manifest = dict(line.split('=',1) for line in archive.read('manifest').decode().splitlines() if '=' in line)
            assert '.'.join(manifest[k] for k in ('major_version','minor_version','build_version')) == version
            assert manifest.get('rsg_version') == '1.3'
            assert ('screensaver_title' in manifest) == (kind == 'screensaver')
            assert len(listing[kind]['name']) <= 30
            assert len(listing[kind]['short_description']) <= 300
            assert len(listing[kind]['long_description']) <= 1500
            assert png_size(archive.read('images/icon-fhd.png')) == (540,405)
            assert png_size(archive.read('images/icon-hd.png')) == (290,218)
            for i in range(3):
                assert png_size(archive.read(f'images/demo/{i}.png')) == (1920,1080)
            sources = '\n'.join(archive.read(n).decode() for n in names if n.endswith('.brs'))
            assert bool(re.search(r'(?im)^sub Main\(',sources)) == (kind == 'player')
            assert ('CreateObject("roInput")' in sources) == (kind == 'player')
            if kind == 'screensaver':
                assert not re.search(r'(?im)^function onKeyEvent\(', sources), 'Screensaver must have no custom key handler'
                assert 'components/ControlsScene.brs' not in names
                assert 'RunScreenSaverSettings' not in sources
            assert not any(n.startswith(('node_modules/','tests/','branding/','store/')) for n in names)
            assert not any(Path(n).suffix in ('.env','.pkg','.key','.pem') for n in names)
            assert png_size((ROOT/'store'/listing[kind]['poster']).read_bytes()) == (540,405)
            results.append({'package':kind,'files':len(names),'checks':'pass'})
    report = {'version':version,'local_preflight':'pass','packages':results,'scope':'Artifact checks only; signing, device validation, screenshots and Roku certification remain separate.'}
    (ROOT/'out/local-preflight.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return report

if __name__ == '__main__':
    check()
