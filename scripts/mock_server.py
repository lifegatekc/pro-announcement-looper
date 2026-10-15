#!/usr/bin/env python3
"""Read-only mock of the four ProPresenter endpoints used by this app.
Use --fail-slide, --corrupt-slide, --delay, and --revision to exercise refresh behavior.
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, unquote
from assets import slide

MAIN = '11111111-1111-4111-8111-111111111111'
YOUTH = '22222222-2222-4222-8222-222222222222'

def serve(args):
    images = {p: [slide(p, (i + args.revision) % 3) for i in range(3)] for p in ['main','youth']}
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parts = [unquote(p) for p in urlsplit(self.path).path.strip('/').split('/')]
            if args.delay: time.sleep(args.delay)
            status, kind, body = 200, 'application/json', None
            if parts == ['version']:
                body = {'name': 'ProPresenter Mock', 'version': '21-mock'}
            elif parts == ['v1','libraries']:
                body = [{'id': {'uuid':'mock-library','name':'Church','index':0}}]
            elif parts == ['v1','library','Church']:
                body = {'updateType':'all','items':[
                    {'uuid':MAIN,'name':'Main Announcements','index':0},
                    {'uuid':YOUTH,'name':'Youth Announcements','index':1}]}
            elif len(parts) in (3,5) and parts[:2] == ['v1','presentation'] and parts[2] in (MAIN,YOUTH):
                profile = 'main' if parts[2] == MAIN else 'youth'
                if len(parts) == 3:
                    # Disabled index 1 verifies flattening across groups without renumbering.
                    body = {'id':{'uuid':parts[2],'name':profile.title()+' Announcements','index':0},
                        'groups':[{'name':'Intro','slides':[{'enabled':True},{'enabled':False}]},
                                  {'name':'Events','slides':[{'enabled':True},{'enabled':True}]}],
                        'destination':'presentation','has_timeline':False}
                elif parts[3] == 'thumbnail' and parts[4] in ('0','2','3'):
                    index = int(parts[4])
                    if args.fail_slide == index:
                        status, body = 503, {'error':'Simulated unavailable slide'}
                    elif args.corrupt_slide == index:
                        kind, body = 'image/png', b'\x89PNGbroken image'
                    else:
                        kind, body = 'image/png', images[profile][[0,2,3].index(index)]
                else:
                    status, body = 404, {'error':'Not found'}
            else:
                status, body = 404, {'error':'Not found'}
            if not isinstance(body, bytes): body = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            try: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError): pass
    print(f'Mock listening on {args.host}:{args.port}; use your computer LAN address in Roku settings.', flush=True)
    ThreadingHTTPServer((args.host,args.port), Handler).serve_forever()

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host',default='0.0.0.0')
    p.add_argument('--port',type=int,default=50001)
    p.add_argument('--fail-slide',type=int,default=-1)
    p.add_argument('--corrupt-slide',type=int,default=-1)
    p.add_argument('--delay',type=float,default=0)
    p.add_argument('--revision',type=int,default=0)
    serve(p.parse_args())
