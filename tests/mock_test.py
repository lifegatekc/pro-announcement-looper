"""Verify mock endpoint shapes and explicit fault injection without church hardware."""
import json
import subprocess
import sys
import time
import socket
from urllib.request import urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def run_case(flags, check):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port = sock.getsockname()[1]
    proc = subprocess.Popen([sys.executable,str(ROOT/'scripts/mock_server.py'),'--host','127.0.0.1','--port',str(port),*flags],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    base = f'http://127.0.0.1:{port}'
    try:
        for _ in range(100):
            try:
                with urlopen(base+'/version',timeout=1): break
            except (URLError, ConnectionError): time.sleep(.05)
        else: raise AssertionError('Mock did not start')
        check(base)
    finally:
        proc.terminate(); proc.wait(timeout=5)

UUID = '11111111-1111-4111-8111-111111111111'
def normal(base):
    with urlopen(base+'/v1/libraries') as r: assert json.load(r)[0]['id']['name'] == 'Church'
    with urlopen(base+'/v1/library/Church') as r: assert len(json.load(r)['items']) == 2
    with urlopen(base+'/v1/presentation/'+UUID) as r:
        groups = json.load(r)['groups']; assert [s['enabled'] for g in groups for s in g['slides']] == [True,False,True,True]
    for i in [0,2,3]:
        with urlopen(base+f'/v1/presentation/{UUID}/thumbnail/{i}?quality=1920&thumbnail_type=jpeg') as r:
            data = r.read(); assert data.startswith(b'\x89PNG'); assert len(data)>100
    try: urlopen(base+'/v1/presentation/'+UUID+'/trigger')
    except HTTPError as e: assert e.code == 404
    else: raise AssertionError('Mock must never implement trigger')
def failed(base):
    try: urlopen(base+f'/v1/presentation/{UUID}/thumbnail/2')
    except HTTPError as e: assert e.code == 503
    else: raise AssertionError('Missing simulated failure')
def corrupt(base):
    with urlopen(base+f'/v1/presentation/{UUID}/thumbnail/2') as r: assert r.read() == b'\x89PNGbroken image'
run_case([],normal)
run_case(['--fail-slide','2'],failed)
run_case(['--corrupt-slide','2'],corrupt)
print('PASS mock API endpoints, disabled-slide indices, read-only behavior, HTTP failure, corrupt image')
