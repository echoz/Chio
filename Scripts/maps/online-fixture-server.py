#!/usr/bin/env python3
"""Verify twelve native-coordinate tiles and replay world and street maps; never fetch."""

import argparse
import hashlib
import json
from pathlib import Path
import signal
import socketserver
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


FIXTURES = Path(__file__).resolve().parents[2] / "Examples/Maps/Fixtures/OnlineTiles"
ADDRESSES = ({(1, x, y) for x in (0, 1) for y in (0, 1)}
             | {(12, x, 2033) for x in (3228, 3229, 3230)}
             | {(14, x, 8133) for x in range(12917, 12922)})
MAX_TILE_BYTES = 16 * 1024 * 1024


def verified_tiles():
    """Return bounded, hash-checked replay bytes indexed by exact request path."""
    manifest_path = FIXTURES / "manifest.json"
    if manifest_path.stat().st_size > 256 * 1024:
        raise ValueError("fixture manifest exceeds 256 KiB")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["schemaVersion"] != 1 or len(manifest["tiles"]) != len(ADDRESSES):
        raise ValueError("unexpected fixture manifest version or tile count")
    addresses = set()
    routes = {}
    for tile in manifest["tiles"]:
        address = (tile["z"], tile["x"], tile["y"])
        if address not in ADDRESSES or address in addresses:
            raise ValueError("unexpected or duplicate fixture coordinate")
        addresses.add(address)
        z, x, y = address
        filename = f"{z}-{x}-{y}.pbf"
        if tile["file"] != filename:
            raise ValueError("fixture filename does not match its coordinate")
        path = FIXTURES / filename
        if path.is_symlink() or not 0 < path.stat().st_size <= MAX_TILE_BYTES:
            raise ValueError("fixture must be a bounded, nonempty regular local file")
        data = path.read_bytes()
        if len(data) != tile["bytes"] or hashlib.sha256(data).hexdigest() != tile["sha256"]:
            raise ValueError(f"fixture bytes/hash mismatch: {filename}")
        expected_url = manifest["observedTemplate"].format(z=z, x=x, y=y)
        if tile["url"] != expected_url:
            raise ValueError("fixture URL does not match its native coordinate")
        routes[f"/{z}/{x}/{y}.pbf"] = data
    return manifest, routes


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def serve(manifest, routes, args):
    cache_control = "no-store" if args.cache_seconds == 0 else f"public, max-age={args.cache_seconds}"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass  # No request logs or addresses in demo recordings.

        def respond(self, include_body):
            # Exact allowlist: queries, traversal, manifests and unknown XYZ paths all fail.
            data = routes.get(self.path)
            if data is None:
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            if include_body and args.delay_ms:
                time.sleep(args.delay_ms / 1000)
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.mapbox-vector-tile")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", cache_control)
            self.end_headers()
            if include_body:
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass  # A cancelled map load is expected during navigation.

        def do_GET(self):
            self.respond(True)

        def do_HEAD(self):
            self.respond(False)

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        def server_bind(self):
            # HTTPServer otherwise reverse-resolves even numeric loopback. Replay
            # needs the bound address and port, with no DNS dependency.
            socketserver.TCPServer.server_bind(self)
            self.server_name, self.server_port = self.server_address[:2]

        def handle_error(self, request, client_address):
            pass  # Disconnected clients must not emit request information.

    # Loopback only, with an OS-selected ephemeral port.
    with Server(("127.0.0.1", 0), Handler) as server:
        endpoint = f"http://127.0.0.1:{server.server_port}"
        source = {"template": endpoint + "/{z}/{x}/{y}.pbf", "zoomRange": [1, 12],
                  "metadata": manifest["metadata"]}
        write_json(args.config_file, source)
        readiness = {"ready": True, "endpoint": endpoint, "configFile": str(args.config_file.resolve()),
                     "tileCount": len(routes), "delayMilliseconds": args.delay_ms,
                     "cacheControl": cache_control}
        if args.ready_file:
            write_json(args.ready_file, readiness)
        print(json.dumps(readiness), flush=True)
        try:
            server.serve_forever(poll_interval=0.1)
        except KeyboardInterrupt:
            pass


def interrupt(signum, frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="check retained bytes/hashes without starting HTTP")
    parser.add_argument("--config-file", type=Path, help="write checked OpenMapTilesSource JSON for --tile-source")
    parser.add_argument("--ready-file", type=Path, help="also write readiness JSON for capture orchestration")
    parser.add_argument("--delay-ms", type=int, default=250, help="GET response delay, 0…5000 ms (default 250)")
    parser.add_argument("--cache-seconds", type=int, default=0, help="max-age 0…1800 seconds; 0 sends no-store")
    args = parser.parse_args()
    if not 0 <= args.delay_ms <= 5000 or not 0 <= args.cache_seconds <= 1800:
        parser.error("delay or cache duration exceeds the supported bounds")
    if not args.verify and args.config_file is None:
        parser.error("--config-file is required when serving")
    if args.ready_file and args.config_file and args.ready_file.resolve() == args.config_file.resolve():
        parser.error("readiness and source config must use different files")
    try:
        manifest, routes = verified_tiles()
        if args.verify:
            print(json.dumps({"verified": True, "tileCount": len(routes),
                              "bytes": sum(map(len, routes.values()))}), flush=True)
            return 0
        signal.signal(signal.SIGTERM, interrupt)
        serve(manifest, routes, args)
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"online fixture replay: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
