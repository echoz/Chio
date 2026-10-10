#!/usr/bin/env python3
"""Verify persistent tiles and ownership across real chio-maps processes on loopback.

Requires an already-built binary. SIGKILL after a completed frame checks ownership
release; a separately planted partial temp checks startup recovery, not kill-mid-write.
No public map service is contacted. Retains bounded logs, screens and a JSON report.
"""

import argparse
import errno
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import socketserver
import struct
import subprocess
import sys

# Keep imported verification helpers from writing user-wide bytecode caches.
sys.dont_write_bytecode = True
import tempfile
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


PHASE_TIMEOUT = 15
FAILURE_TIMEOUT = 5
OUTPUT_LIMIT = 8 * 1024 * 1024
REQUEST_LIMIT = 32


def load_script(name, path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Cannot load {path.name}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


class ReplayServer(HTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def start_replay(routes):
    requests = []
    request_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            self.request.settimeout(2)
            super().setup()

        def log_message(self, *unused):
            pass

        def do_GET(self):
            with request_lock:
                admitted = len(requests) < REQUEST_LIMIT
                if admitted:
                    requests.append(self.path)
                else:
                    self.server.excess_requests += 1
            body = routes.get(self.path) if admitted else None
            self.send_response(200 if body is not None else 404 if admitted else 429)
            self.send_header("Content-Length", str(len(body) if body else 0))
            self.send_header("Content-Type", "application/vnd.mapbox-vector-tile")
            self.send_header("Cache-Control", "public, max-age=1800")
            self.end_headers()
            if body:
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError, TimeoutError):
                    pass

    server = ReplayServer(("127.0.0.1", 0), Handler)
    server.excess_requests = 0
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
    try:
        thread.start()
    except BaseException:
        server.server_close()
        raise
    return server, thread, requests


class Session:
    def __init__(self, name, command, parser, output_dir):
        self.name, self.parser, self.output_dir = name, parser, output_dir
        self.output = bytearray()
        self.loaded_screen = None
        self.command = command
        self.started = time.monotonic()
        self.master, self.slave = pty.openpty()
        self.original_modes = termios.tcgetattr(self.slave)
        self.process = None
        try:
            fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            environment = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
            for name in ("NO_COLOR", "CLICOLOR", "CLICOLOR_FORCE", "FORCE_COLOR"):
                environment.pop(name, None)
            self.process = subprocess.Popen(command, stdin=self.slave, stdout=self.slave,
                                            stderr=self.slave, env=environment)
        except BaseException:
            os.close(self.master)
            os.close(self.slave)
            raise

    def receive(self, timeout=0.1):
        if not select.select([self.master], [], [], timeout)[0]:
            return False
        try:
            chunk = os.read(self.master, 65_536)
        except OSError as error:
            if error.errno == errno.EIO:
                return False
            raise
        if len(self.output) + len(chunk) > OUTPUT_LIMIT:
            raise AssertionError("PTY output exceeds 8 MiB per child")
        self.output.extend(chunk)
        return bool(chunk)

    def screen(self):
        return self.parser.screen(self.output)

    def loaded(self):
        deadline = time.monotonic() + PHASE_TIMEOUT
        expected = ("/ maps", "World", "2/4 minimal", "span 360.0000", "Online · z1")
        while time.monotonic() < deadline:
            self.receive(min(0.1, deadline - time.monotonic()))
            screen = self.screen()
            if all(value in screen for value in expected) and "Preparing map" not in screen:
                # Drain queued frame updates; retained samples must be a complete frame.
                while time.monotonic() < deadline and self.receive(min(0.25, deadline - time.monotonic())):
                    pass
                screen = self.screen()
                if all(value in screen for value in expected) and "Preparing map" not in screen:
                    self.loaded_screen = screen
                    samples = tuple(''.join(char if '\u2800' <= char <= '\u28ff' else ' ' for char in row)
                                    for row in screen.splitlines()[3:23])
                    assert any(any(char != ' ' for char in row) for row in samples), "World geography is empty"
                    return samples
            assert self.process.poll() is None, f"{self.name} exited before loading: {self.process.returncode}"
        raise AssertionError(f"{self.name} did not load within {PHASE_TIMEOUT}s")

    def exited(self, timeout=PHASE_TIMEOUT):
        deadline = time.monotonic() + timeout
        while self.process.poll() is None and time.monotonic() < deadline:
            self.receive(min(0.1, deadline - time.monotonic()))
        assert self.process.poll() is not None, f"{self.name} did not exit within {timeout}s"
        self.process.wait(timeout=1)
        while self.receive(0):
            pass
        return self.process.returncode

    def graceful_exit(self):
        os.write(self.master, b"q")
        assert self.exited() == 0, f"{self.name} did not exit successfully"
        assert b"\x1b[?1049l" in self.output, "Alternate screen not restored"
        assert b"\x1b[?25h" in self.output, "Cursor not restored"
        assert termios.tcgetattr(self.slave) == self.original_modes, "Original terminal attributes not restored"
        for diagnostic in (b"runtime warning", b"runtime error", b"swifttui runtime"):
            assert diagnostic not in self.output.lower(), "Runtime diagnostic in PTY output"

    def close(self):
        try:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=5)
            (self.output_dir / f"{self.name}.log").write_bytes(self.output)
            (self.output_dir / f"{self.name}.txt").write_text(self.loaded_screen or self.screen(), encoding="utf-8")
        finally:
            os.close(self.master)
            os.close(self.slave)


def probe(binary, output_dir, interrupted_temp_name, contention_text):
    started = time.monotonic()
    with binary.open("rb") as executable:
        digest = hashlib.sha256()
        for chunk in iter(lambda: executable.read(1024 * 1024), b""):
            digest.update(chunk)
    output_dir.mkdir(parents=True, exist_ok=True)
    cache_root = Path(tempfile.mkdtemp(prefix="process-cache-", dir=output_dir)).resolve()
    fixtures = load_script("cache_replay_fixtures", Path(__file__).with_name("online-fixture-server.py"))
    manifest, routes = fixtures.verified_tiles()
    terminal = load_script("cache_terminal_probe", Path(__file__).with_name("terminal-probe.py"))
    parser = terminal.shared_parser()
    server, thread, requests = None, None, []
    command = []
    sessions = []
    validations = {}
    report = {"status": "failed", "command": command, "cache_root": str(cache_root),
              "binary_sha256": digest.hexdigest(),
              "phase_timeout_seconds": PHASE_TIMEOUT, "failure_timeout_seconds": FAILURE_TIMEOUT,
              "per_child_output_limit_bytes": OUTPUT_LIMIT, "request_limit": REQUEST_LIMIT,
              "scope": "Real POSIX PTY children and retained loopback fixtures; no live provider or SSH. "
                       "SIGKILL occurs after loading; planted partial temp proves startup cleanup only.",
              "validations": validations}

    def launch(name):
        session = Session(name, command, parser, output_dir)
        sessions.append(session)
        return session

    try:
        server, thread, requests = start_replay(routes)
        source_path = cache_root.parent / (cache_root.name + "-source.json")
        source = {"template": f"http://127.0.0.1:{server.server_port}" + "/{z}/{x}/{y}.pbf",
                  "zoomRange": [1, 12], "metadata": manifest["metadata"]}
        source_path.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
        command = [str(binary), "--map", "world", "--theme", "default", "--online",
                   "--tile-source", str(source_path), "--tile-cache", str(cache_root)]
        report["command"] = command
        first = launch("first-owner")
        geography = first.loaded()
        assert set(requests) == {f"/1/{x}/{y}.pbf" for x in (0, 1) for y in (0, 1)}, "First world fetched unexpected coverage"
        assert len(requests) == 4, "First launch did not fetch exactly four tiles"
        validations["first_launch_fetches_four_world_tiles"] = True
        count = len(requests)
        conflict = launch("contending-owner")
        assert conflict.exited(FAILURE_TIMEOUT) != 0, "Contending process succeeded"
        assert contention_text.lower() in conflict.output.decode("utf-8", errors="replace").lower(), "Missing explicit ownership diagnostic"
        assert b"\x1b[?1049h" not in conflict.output, "Ownership failure entered TUI"
        assert len(requests) == count, "Contending process requested tiles"
        validations["second_owner_fails_fast_before_tui"] = True
        first.graceful_exit()
        validations["first_owner_graceful_terminal_restoration"] = True

        warm = launch("warm-reopen")
        assert warm.loaded() == geography, "Reopened cached world geography changed"
        assert len(requests) == count, "Warm reopen used HTTP"
        warm.graceful_exit()
        validations["fresh_cross_process_reuse_without_http_and_same_geography"] = True
        validations["warm_owner_graceful_terminal_restoration"] = True

        killed = launch("killed-owner")
        assert killed.loaded() == geography, "Pre-kill cached geography changed"
        assert len(requests) == count, "Pre-kill launch used HTTP"
        killed.process.kill()
        assert killed.exited(FAILURE_TIMEOUT) == -signal.SIGKILL, "Owner did not exit via SIGKILL"
        validations["loaded_owner_sigkill_observed"] = True
        partial = cache_root / interrupted_temp_name
        assert not partial.exists(), "Interrupted temp fixture would overwrite a file"
        partial.write_bytes(b"partial interrupted write fixture")
        reopened = launch("after-kill-and-partial-temp")
        assert reopened.loaded() == geography, "After-kill cached geography changed"
        assert len(requests) == count, "After-kill reopen used HTTP"
        assert not partial.exists(), "Recognized interrupted temp was not removed on reopen"
        reopened.graceful_exit()
        validations["sigkill_releases_process_ownership"] = True
        validations["planted_partial_temp_removed_on_startup"] = True
        validations["after_kill_fresh_reuse_and_graceful_restoration"] = True
        report["status"] = "passed"
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
    finally:
        cleanup_errors = []
        for session in sessions:
            try:
                session.close()
            except Exception as error:
                cleanup_errors.append(f"{session.name}: {type(error).__name__}: {error}")
        if server is not None:
            try:
                server.shutdown()
            except Exception as error:
                cleanup_errors.append(f"Replay shutdown: {type(error).__name__}: {error}")
            try:
                server.server_close()
            except Exception as error:
                cleanup_errors.append(f"Replay close: {type(error).__name__}: {error}")
        if thread is not None:
            thread.join(timeout=5)
            if thread.is_alive():
                cleanup_errors.append("Replay server thread did not stop")
        report["children"] = [{"name": session.name, "pid": session.process.pid,
                               "exit_code": session.process.returncode, "output_bytes": len(session.output)}
                              for session in sessions]
        report["requests"] = requests
        excess_requests = server.excess_requests if server is not None else 0
        report["excess_requests"] = excess_requests
        report["total_seconds"] = round(time.monotonic() - started, 6)
        if excess_requests:
            cleanup_errors.append("HTTP request limit exceeded")
        if cleanup_errors:
            report.update(status="failed", cleanup_errors=cleanup_errors)
        (output_dir / "cache-probe.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{report['status'].upper()}: persistent cache process probe; report {output_dir / 'cache-probe.json'}")
    if report["status"] != "passed":
        print(report.get("failure", report.get("cleanup_errors")), file=sys.stderr)
        return 1
    return 0


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("binary", type=Path, help="Already-built release chio-maps executable")
    arguments.add_argument("--output-dir", type=Path, default=Path(".build/cache-slice/process"))
    arguments.add_argument("--interrupted-temp-name", default="tile-1-0-0.bin.tmp",
                           help="Recognized root-level partial write basename from the cache contract")
    arguments.add_argument("--contention-text", default="already in use", help="Expected ownership failure diagnostic")
    options = arguments.parse_args()
    if not options.binary.is_file() or not os.access(options.binary, os.X_OK):
        arguments.error("binary must be an existing executable")
    filename = options.interrupted_temp_name
    if not filename or Path(filename).name != filename or filename in (".", "..", "owner.lock", ".lock", "manifest.json"):
        arguments.error("interrupted temp must be a safe recognized basename")
    return probe(options.binary.resolve(), options.output_dir.resolve(), filename, options.contention_text)


if __name__ == "__main__":
    sys.exit(main())
