#!/usr/bin/env python3
"""Read hidden local diagnostics over a keyed Roku's developer console. No playback commands."""
import argparse
import html
import json
import re
import socket
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True, help='Roku hostname or IP address')
    parser.add_argument('--out', type=Path, help='Optional private local output file; do not commit it')
    args = parser.parse_args()
    with socket.create_connection((args.host, 8080), timeout=5) as connection:
        connection.settimeout(2)
        connection.sendall(b'sgnodes palExitDiagnostics\r\n')
        chunks = []
        size = 0
        while size < 65536:
            try:
                chunk = connection.recv(8192)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
    response = b''.join(chunks).decode(errors='replace')
    match = re.search(r'\btext="([^"]*)"', response)
    if not match:
        raise SystemExit('Diagnostics unavailable. Open the updated app first; published-app inspection requires a matching developer key. No changes were made.')
    try:
        report = json.loads(html.unescape(match.group(1)))
    except json.JSONDecodeError:
        raise SystemExit('The developer console did not return a complete diagnostics record. Inspect the PALExitDiagnosticsV1 registry section with Roku Resource Monitor instead.')
    output = json.dumps(report, indent=2) + '\n'
    if args.out:
        args.out.write_text(output)
        print('Saved private diagnostics:', args.out)
    else:
        print(output, end='')


if __name__ == '__main__':
    main()
