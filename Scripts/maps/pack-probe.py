#!/usr/bin/env python3
"""Exercise explicit bundled pack preparation and offline viewing in real PTYs.

Uses an already-built executable and the retained PTY harness. Checks fresh
process reopening, unchanged pack bytes, interaction and terminal restoration.
No public provider is contacted; this does not establish physical durability.
"""

import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True


def load_harness():
    import importlib.util
    path = Path(__file__).with_name("cache-probe.py")
    specification = importlib.util.spec_from_file_location("pack_process_harness", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("Cannot load retained PTY harness")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def pack_hashes(path):
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()}


def wait_screen(session, required):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        session.receive(min(0.1, deadline - time.monotonic()))
        screen = session.screen()
        if all(text in screen for text in required) and "Preparing map" not in screen:
            session.loaded_screen = screen
            return screen
        assert session.process.poll() is None, f"{session.name} exited before rendering"
    raise AssertionError(f"{session.name} did not render {required} within 15 seconds")


def geography(screen):
    rows = screen.splitlines()[3:23]
    samples = tuple("".join(character if "\u2800" <= character <= "\u28ff" else " "
                            for character in row) for row in rows)
    assert any(any(character != " " for character in row) for row in samples), "World geography is empty"
    return samples


def probe(binary, output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    harness = load_harness()
    terminal = harness.load_script("pack_terminal_parser", Path(__file__).with_name("terminal-probe.py"))
    parser = terminal.shared_parser()
    root = Path(tempfile.mkdtemp(prefix="process-pack-", dir=output_dir))
    pack_file = root / "world.chiomap"
    report = {"status": "failed", "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "scope": "Real preparation and fresh-process offline pack viewing; PTY restoration and unchanged bytes. No live provider.",
              "validations": {}}
    validations = report["validations"]
    sessions = []
    try:
        prepared = subprocess.run([str(binary), "--write-tile-pack", str(pack_file)],
                                  capture_output=True, timeout=15, check=False)
        (output_dir / "prepare.log").write_bytes(prepared.stdout + prepared.stderr)
        assert prepared.returncode == 0, "Pack preparation failed"
        assert b"Prepared offline world tile pack" in prepared.stdout, "Preparation diagnostic missing"
        assert b"\x1b[?1049h" not in prepared.stdout + prepared.stderr, "Preparation entered interactive UI"
        original = pack_hashes(pack_file)
        assert original, "Preparation produced no pack files"
        validations["preparation_exits_before_ui"] = True
        fifo = root / "not-a-pack.fifo"
        os.mkfifo(fifo)
        alias = root / "pack-link"
        alias.symlink_to(pack_file)
        for invalid in [fifo, alias, root]:
            rejected = subprocess.run([str(binary), "--tile-pack", str(invalid)],
                                      capture_output=True, timeout=5, check=False)
            assert rejected.returncode != 0, f"Invalid pack path accepted: {invalid.name}"
            assert b"\x1b[?1049h" not in rejected.stdout + rejected.stderr, "Invalid path entered UI"
        fifo.unlink()
        alias.unlink()
        validations["fifo_symlink_and_directory_rejected_before_ui"] = True
        original_names = sorted(item.name for item in root.iterdir())
        pack_file.chmod(0o444)
        root.chmod(0o555)
        command = [str(binary), "--tile-pack", str(pack_file), "--map", "world"]
        samples = None
        for name in ["first-open", "fresh-reopen"]:
            session = harness.Session(name, command, parser, output_dir)
            sessions.append(session)
            loaded = wait_screen(session, ["Offline pack · z1", "span 360.0000", "2/4 minimal"])
            current = geography(loaded)
            assert "Online ·" not in loaded and "Natural Earth" not in loaded, "Pack mislabeled its source"
            if samples is None:
                samples = current
            else:
                assert current == samples, "Fresh-process pack geography changed"
            os.write(session.master, b"dt")
            wait_screen(session, ["Offline pack · z1", "3/4 abstract", "light", "span 360.0000"])
            os.write(session.master, b"\x1b[C")
            moved = wait_screen(session, ["Offline pack · z1", "Center 0.000, 43.200"])
            assert "3/4 abstract" in moved and "light" in moved, "Pan reset detail or theme"
            harness.fcntl.ioctl(session.slave, harness.termios.TIOCSWINSZ, harness.struct.pack("HHHH", 18, 36, 0, 0))
            session.process.send_signal(signal.SIGWINCH)
            wait_screen(session, ["More room for the map", "Offline pack paused"])
            harness.fcntl.ioctl(session.slave, harness.termios.TIOCSWINSZ, harness.struct.pack("HHHH", 30, 100, 0, 0))
            session.process.send_signal(signal.SIGWINCH)
            wait_screen(session, ["Offline pack · z1", "Center 0.000, 43.200", "3/4 abstract", "light"])
            os.write(session.master, b"\x1b[C")
            wait_screen(session, ["Offline pack · z1", "Center 0.000, 86.400"])
            session.graceful_exit()
            assert pack_hashes(pack_file) == original, "Viewing changed immutable pack files"
            assert sorted(item.name for item in root.iterdir()) == original_names, "Viewing created sidecar files"
        validations["fresh_process_reopen_preserves_geography"] = True
        validations["detail_theme_and_camera_interaction"] = True
        validations["readonly_pack_and_parent_open"] = True
        validations["resize_preserves_camera_detail_theme_and_native_input"] = True
        validations["graceful_terminal_restoration"] = True
        validations["pack_files_unchanged_after_viewing"] = True
        for option in ["--tile-pack", "--write-tile-pack"]:
            for conflicting in [["--online"], ["--snapshot"], ["--snapshot-json"], ["--benchmark"],
                                ["--source", "openfreemap"], ["--tile-source", "unused.json"],
                                ["--tile-cache", str(root / "unused-cache")]]:
                rejected = subprocess.run([str(binary), option, str(pack_file)] + conflicting,
                                          capture_output=True, timeout=5, check=False)
                assert rejected.returncode != 0, f"Ambiguous flags accepted: {option} {conflicting}"
                assert b"\x1b[?1049h" not in rejected.stdout + rejected.stderr, "Invalid flags entered UI"
        validations["ambiguous_flags_rejected_before_ui"] = True
        report["status"] = "passed"
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
    finally:
        root.chmod(0o755)
        if pack_file.exists():
            pack_file.chmod(0o644)
        cleanup_errors = []
        for session in sessions:
            try:
                session.close()
            except Exception as error:
                cleanup_errors.append(f"{session.name}: {type(error).__name__}: {error}")
        if cleanup_errors:
            report.update(status="failed", cleanup_errors=cleanup_errors)
        report["children"] = [{"name": session.name, "exit_code": session.process.returncode}
                              for session in sessions]
        report["pack_file"] = str(pack_file)
        (output_dir / "pack-probe.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{report['status'].upper()}: offline pack process probe; report {output_dir / 'pack-probe.json'}")
    if report["status"] != "passed":
        print(report.get("failure", report.get("cleanup_errors")), file=sys.stderr)
        return 1
    return 0


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("binary", type=Path, help="Already-built release chio-maps")
    arguments.add_argument("--output-dir", type=Path, default=Path(".build/pack-slice/process"))
    options = arguments.parse_args()
    if not options.binary.is_file() or not os.access(options.binary, os.X_OK):
        arguments.error("binary must be an existing executable")
    return probe(options.binary.resolve(), options.output_dir.resolve())


if __name__ == "__main__":
    sys.exit(main())
