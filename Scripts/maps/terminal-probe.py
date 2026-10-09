#!/usr/bin/env python3
"""Probe the offline or fixed-local-HTTP online map example in a real POSIX PTY; optionally capture asciinema v2.

The shared dashboard smoke parser checks text transitions. Public native raster tests
own colors, braille samples and Unicode layout; this is not a terminal emulator or
live-emulator/SSH appearance measurement. A recording ends at a complete 100x30 map
before resize and teardown; the PTY check continues through resize and clean exit.
"""

import argparse
import codecs
import errno
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


PHASE_TIMEOUT = 15
OUTPUT_LIMIT = 8 * 1024 * 1024


def shared_parser():
    path = Path(__file__).resolve().parents[1] / "ci" / "terminal-smoke.py"
    specification = importlib.util.spec_from_file_location("chio_terminal_smoke", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("Could not load the shared terminal smoke parser")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    module.WIDTH, module.HEIGHT = 100, 30
    return module


def probe(binary, output_dir, record=None, online_source=None):
    parser = shared_parser()
    master, slave = pty.openpty()
    original_modes = termios.tcgetattr(slave)
    process = None
    output = bytearray()
    phases = []
    events = []
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    recording = record is not None
    started = time.monotonic()
    last_recorded_time = 0.0
    failure = None
    validations = {}
    recording_completed = False
    command = [str(binary), "--map", "world", "--theme", "default"]
    if online_source is not None:
        command.extend(["--online", "--tile-source", str(online_source)])

    def receive(timeout=0.1):
        nonlocal last_recorded_time
        if not select.select([master], [], [], timeout)[0]:
            return False
        try:
            chunk = os.read(master, 65_536)
        except OSError as error:
            if error.errno == errno.EIO:
                return False
            raise
        if len(output) + len(chunk) > OUTPUT_LIMIT:
            raise AssertionError("Map terminal output exceeded the 8 MiB limit")
        output.extend(chunk)
        if recording and chunk:
            text = decoder.decode(chunk)
            if text:
                last_recorded_time = time.monotonic() - started
                events.append([round(last_recorded_time, 6), "o", text])
        return bool(chunk)

    def current_screen():
        return parser.screen(output)

    def map_samples():
        # Compare the actual drawing, excluding headers, camera text and credits.
        # Keeping only braille also excludes labels from this movement assertion.
        return tuple(''.join(char if '\u2800' <= char <= '\u28ff' else ' ' for char in row)
                     for row in current_screen().splitlines()[3:23])

    def recording_pause():
        if not recording:
            return
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            receive(min(0.1, deadline - time.monotonic()))

    def observe(name, expected, action=None, transitions=()):
        before = len(output)
        phase_started = time.monotonic()
        deadline = phase_started + PHASE_TIMEOUT
        seen_transitions = set()
        if action is not None:
            action()
        while time.monotonic() < deadline:
            receive(min(0.1, deadline - time.monotonic()))
            seen_transitions.update(value for value in transitions if value in current_screen())
            if len(output) > before and all(value in current_screen() for value in expected) and "Preparing map" not in current_screen():
                # Complete queued updates before sending the next user action.
                while time.monotonic() < deadline and receive(min(0.25, deadline - time.monotonic())):
                    seen_transitions.update(value for value in transitions if value in current_screen())
                if all(value in current_screen() for value in expected) and "Preparing map" not in current_screen():
                    assert seen_transitions == set(transitions), f"Missing transitions in {name}: {set(transitions) - seen_transitions}"
                    phases.append({"name": name, "seconds": round(time.monotonic() - phase_started, 6),
                                   "output_bytes": len(output) - before,
                                   "columns": parser.WIDTH, "rows": parser.HEIGHT, "expected": list(expected)})
                    print("Observed:", name, flush=True)
                    recording_pause()
                    phases[-1].update(screen=current_screen(),
                                      recording_seconds=round(time.monotonic() - started, 6) if recording else None,
                                      observed_transitions=sorted(seen_transitions))
                    return
            if process.poll() is not None:
                break
        raise AssertionError(f"Not observed within {PHASE_TIMEOUT}s: {name} ({expected})")

    def key(name, value, expected):
        observe(name, expected, lambda: os.write(master, value))

    def resize(columns, rows):
        parser.WIDTH, parser.HEIGHT = columns, rows
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        process.send_signal(signal.SIGWINCH)

    def stop_recording():
        nonlocal recording, recording_completed
        if not recording:
            return
        trailing = decoder.decode(b"", final=True)
        if trailing:
            events.append([round(time.monotonic() - started, 6), "o", trailing])
        # Preserve the final complete UI frame's one-second hold in the cast.
        events.append([round(max(last_recorded_time, time.monotonic() - started), 6), "o", ""])
        recording = False
        recording_completed = True

    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        environment = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
        for key_name in ("NO_COLOR", "CLICOLOR", "CLICOLOR_FORCE", "FORCE_COLOR"):
            environment.pop(key_name, None)
        process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=environment)
        initial_expected = ("/ maps", "World", "2/4 minimal", "span 360.0000")
        if online_source is not None:
            initial_expected += ("Online · z1", "OpenFreeMap")
        observe("world minimal default", initial_expected)
        modes = termios.tcgetattr(slave)
        assert not modes[3] & (termios.ECHO | termios.ICANON | termios.ISIG | termios.IEXTEN), "Terminal is not in raw input mode"
        assert modes[6][termios.VMIN] == 1 and modes[6][termios.VTIME] == 0, "Unexpected raw read timing"
        assert b"\x1b[?1049h" in output, "Alternate screen was not entered"
        assert b"\x1b[?25l" in output, "Cursor was not hidden"
        validations["raw_input"] = True
        validations["alternate_screen_entered"] = True
        validations["cursor_hidden"] = True

        if online_source is not None:
            assert "Natural Earth" not in current_screen(), "Online world substituted bundled geography"
            initial_world_samples = map_samples()
            assert sum(char not in (" ", "\u2800") for row in initial_world_samples for char in row) > 100, "Online world lacks braille geography"
            key("online world pan", b"\x1b[C", ("Online · z1", "span 360.0000"))
            assert map_samples() != initial_world_samples, "World pan changed camera without moving geography"
            key("online world reset", b"r", ("Online · z1", "span 360.0000"))
            assert map_samples() == initial_world_samples, "World reset did not restore geography"
            validations["online_world_coverage_and_pan"] = True
            observe("online street default ready", ("Singapore", "2/4 minimal · default", "Online · z12",
                    "Center 1.289, 103.866", "span 0.0300"), lambda: os.write(master, b" "),
                    transitions=("Loading tiles",))
            initial_street_samples = map_samples()
            assert sum(char not in (" ", "\u2800") for row in initial_street_samples for char in row) > 100, "Online ready frame lacks actual braille geography"
            validations["online_loading_and_braille"] = True
            key("online pan crosses adjacent tile boundary", b"\x1b[C" * 8,
                ("Online · z12", "Center 1.289, 103.895", "span 0.0300"))
            assert map_samples() != initial_street_samples, "Online pan changed camera text without moving geography"
            assert sum(char not in (" ", "\u2800") for row in map_samples() for char in row) > 100, "Adjacent online tile lacks braille geography"
            validations["adjacent_tile_pan_and_focus"] = True
            key("online outside fixed fixture", b"\x1b[C" * 24,
                ("Could not load this area", "showing previous coverage", "Center 1.289, 103.981", "span 0.0300"))
            observe("online retry retains failed camera and previous coverage",
                    ("Could not load this area", "showing previous coverage", "Center 1.289, 103.981"),
                    lambda: os.write(master, b"e"), transitions=("Loading tiles",))
            key("online reset recovers", b"r", ("Online · z12", "Center 1.289, 103.866", "span 0.0300"))
            assert "Could not load" not in current_screen(), "Online failure status did not reset"
            assert map_samples() == initial_street_samples, "Reset did not restore accepted online geography"
            validations["failed_coverage_retry_and_recovery"] = True
            key("online select first place", b"n", ("Online · z12", "Selected: Merlion", "Center 1.287, 103.855"))
            key("online next place", b"n", ("Online · z12", "Selected: Gardens by the Bay", "Center 1.282, 103.864"))
            key("online activate place", b"\r", ("Online · z12", "Opened Gardens by the Bay"))
            selected_minimal_samples = map_samples()
            key("online silhouette detail", b"[", ("1/4 silhouette", "Online · z12", "Center 1.282, 103.864"))
            assert map_samples() != selected_minimal_samples, "Online silhouette did not change the drawing"
            key("online batched raise detail", b"]]", ("3/4 abstract", "Online · z12", "Center 1.282, 103.864"))
            key("online upper detail limit", b"]]]]", ("4/4 source", "Online · z12", "Center 1.282, 103.864"))
            key("online lower detail limit", b"[[[[", ("1/4 silhouette", "Online · z12", "Center 1.282, 103.864"))
            key("online minimal detail", b"]", ("2/4 minimal", "Online · z12", "Center 1.282, 103.864"))
            assert map_samples() == selected_minimal_samples, "Online minimal detail did not restore the drawing"
            validations["online_detail_and_marker_focus"] = True
            key("online reset retains selected place", b"r", ("Online · z12", "Selected: Gardens by the Bay", "Center 1.289, 103.866"))
            key("online street light ready", b"t", ("2/4 minimal · light", "Online · z12", "Center 1.289, 103.866", "span 0.0300"))
            key("online street btop ready", b"t", ("2/4 minimal · btop", "Online · z12", "Center 1.289, 103.866", "span 0.0300"))
            key("online final street default ready", b"t", ("2/4 minimal · default", "Online · z12", "Center 1.289, 103.866", "span 0.0300"))
            assert "Could not load" not in current_screen(), "Final online street frame retained failure status"
            stop_recording()
            observe("online compact paused", ("More room for the map", "Online paused"), lambda: resize(36, 18))
            observe("online restored size retains camera detail selection and focus",
                    ("Online · z12", "2/4 minimal · default", "Selected: Gardens by the Bay", "Center 1.289, 103.866", "span 0.0300"),
                    lambda: resize(100, 30))
            assert "More room for the map" not in current_screen(), "Online fallback remained after expansion"
            key("online restored map still receives pan input", b"\x1b[C",
                ("Online · z12", "Center 1.289, 103.870", "Selected: Gardens by the Bay"))
            validations["online_compact_pause_and_recovery"] = True
        else:
            minimal_world_samples = map_samples()
            key("world silhouette shapes", b"[", ("World", "1/4 silhouette", "span 360.0000"))
            assert map_samples() != minimal_world_samples, "World shape strengths did not change the coastline"
            key("restore world minimal", b"]", ("World", "2/4 minimal", "span 360.0000"))
            assert map_samples() == minimal_world_samples, "World detail did not restore the minimal coastline"
            key("world abstract shapes", b"]", ("World", "3/4 abstract", "span 360.0000"))
            key("street", b" ", ("Singapore", "span 0.0300"))
            abstract_samples = map_samples()
            key("minimal detail", b"[", ("2/4 minimal", "Center 1.289, 103.866", "span 0.0300"))
            minimal_samples = map_samples()
            key("silhouette detail", b"[", ("1/4 silhouette", "Center 1.289, 103.866", "span 0.0300"))
            assert map_samples() != minimal_samples, "Silhouette did not remove road geometry"
            key("raise detail", b"]]", ("3/4 abstract", "span 0.0300"))
            assert map_samples() == abstract_samples, "Raising detail did not restore the drawing"
            key("source detail", b"]", ("4/4 source", "span 0.0300"))
            assert map_samples() != abstract_samples, "Detail comparison did not change the drawing"
            key("cycle detail", b"d", ("1/4 silhouette", "span 0.0300"))
            key("abstract detail", b"]]", ("3/4 abstract", "span 0.0300"))
            assert map_samples() == abstract_samples, "Abstract comparison did not restore the drawing"
            key("zoom", b"+", ("Singapore", "span 0.0210"))
            zoom_samples = map_samples()
            key("pan", b"\x1b[C", ("Center 1.289, 103.869", "span 0.0210"))
            assert map_samples() != zoom_samples, "Pan changed camera text without moving the drawing"
            key("light theme", b"t", ("abstract · light", "span 0.0210"))
            # Exercise visible label changes on the named Overpass extract.
            key("fills off redraw", b"f", ("Singapore", "abstract · light", "span 0.0210"))
            key("labels off redraw", b"l", ("Singapore", "span 0.0210"))
            key("fills on redraw", b"f", ("Singapore", "span 0.0210"))
            key("labels on redraw", b"l", ("Singapore", "span 0.0210"))
            key("select first place", b"n", ("Selected: Merlion", "Center 1.287, 103.855", "span 0.0210"))
            key("next place", b"n", ("Selected: Gardens by the Bay", "Center 1.282, 103.864"))
            key("activate place", b"\r", ("Opened Gardens by the Bay",))
            key("previous place", b"p", ("Selected: Merlion", "Center 1.287, 103.855"))
            key("reset camera retains selection", b"r", ("Selected: Merlion", "Center 1.289, 103.866", "span 0.0300"))
            key("minimal final view", b"[", ("2/4 minimal", "Selected: Merlion", "span 0.0300"))
            stop_recording()

            key("lower detail limit", b"[[[", ("1/4 silhouette", "Center 1.289, 103.866", "span 0.0300"))
            key("upper detail limit", b"]]]]", ("4/4 source", "Center 1.289, 103.866", "span 0.0300"))
            key("restore abstract detail", b"[", ("3/4 abstract", "span 0.0300"))
            observe("compact fallback", ("More room for the map",), lambda: resize(36, 18))
            observe("restored size retains camera and detail", ("Singapore", "3/4 abstract", "Center 1.289, 103.866", "span 0.0300"),
                    lambda: resize(100, 30))
            assert "More room for the map" not in current_screen(), "Fallback remained after expansion"
            key("leave offline coverage", b"\x1b[C" * 8, ("Outside offline coverage",))
            key("reset", b"r", ("Center 1.289, 103.866", "span 0.0300"))
            assert "Outside offline coverage" not in current_screen(), "Coverage status did not reset"

        before = len(output)
        exit_started = time.monotonic()
        os.write(master, b"q")
        deadline = exit_started + PHASE_TIMEOUT
        while process.poll() is None and time.monotonic() < deadline:
            receive(min(0.1, deadline - time.monotonic()))
        assert process.poll() is not None, "Map did not exit within 15 seconds"
        process.wait(timeout=1)
        while receive(0):
            pass
        phases.append({"name": "exit", "seconds": round(time.monotonic() - exit_started, 6),
                       "output_bytes": len(output) - before, "columns": 100, "rows": 30})
        assert process.returncode == 0, f"Map exited with {process.returncode}"
        assert b"\x1b[?1049l" in output, "Alternate screen was not restored"
        assert b"\x1b[?25h" in output, "Cursor was not restored"
        assert termios.tcgetattr(slave) == original_modes, "Exact original terminal attributes were not restored"
        assert b"runtime warning" not in output.lower(), "Map emitted runtime warnings"
        assert b"runtime error" not in output.lower(), "Map emitted runtime errors"
        assert b"swifttui runtime" not in output.lower(), "Map emitted runtime diagnostics or deferred logs"
        validations.update(exit_zero=True, alternate_screen_restored=True, cursor_restored=True,
                           exact_terminal_attributes_restored=True, no_runtime_warnings=True, no_runtime_errors_or_logs=True)
    except Exception as error:
        failure = f"{type(error).__name__}: {error}"
        print("Last terminal screen:\n" + current_screen(), file=sys.stderr)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "terminal-probe.log").write_bytes(output)
        report = {"status": "passed" if failure is None else "failed", "failure": failure,
                  "command": command, "total_seconds": round(time.monotonic() - started, 6),
                  "output_bytes": len(output), "output_limit_bytes": OUTPUT_LIMIT,
                  "phase_timeout_seconds": PHASE_TIMEOUT, "phases": phases, "validations": validations,
                  "recording": str(record) if record is not None else None,
                  "recording_completed_before_resize_and_teardown": recording_completed,
                  "measurement_scope": "Local POSIX PTY transitions and restoration; no live-emulator or SSH claims."}
        (output_dir / "terminal-probe.json").write_text(json.dumps(report, indent=2) + "\n")
        if record is not None:
            record.parent.mkdir(parents=True, exist_ok=True)
            header = {"version": 2, "width": 100, "height": 30,
                      "title": ("Chio maps · fixed local HTTP replay of real provider geometry"
                                if online_source is not None else "Chio maps · offline world and Singapore"),
                      "env": {"TERM": "xterm-256color", "COLORTERM": "truecolor"}}
            if online_source is not None:
                header["description"] = ("Fixed local HTTP fixture replay of real OpenFreeMap provider geometry; "
                                         "actual HTTP loading, adjacent tile pan, failure/retry, native focus, "
                                         "marker activation, detail and themes. No live-provider availability claim.")
            with record.open("w", encoding="utf-8") as cast:
                for item in [header, *events]:
                    cast.write(json.dumps(item, ensure_ascii=False) + "\n")
        os.close(master)
        os.close(slave)
    workflow = ("online HTTP loading, adjacent tiles, failure/retry, native focus, detail, themes, compact recovery"
                if online_source is not None else
                "map pan/zoom, detail limits, marker selection/activation, theme, fills/labels, coverage, resize")
    print(f"PASS: {workflow} and clean exit ({len(output)} bytes)")


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("binary", type=Path, help="Path to an already-built chio-maps executable")
    arguments.add_argument("--output-dir", type=Path, default=Path(".build/maps"), help="Raw PTY log and timing report directory")
    arguments.add_argument("--record", type=Path, help="Optional asciinema v2 output; meaningful 100x30 frames only")
    arguments.add_argument("--online-source", type=Path,
                           help="Configured source JSON for the fixed z12 local HTTP fixture workflow")
    options = arguments.parse_args()
    probe(options.binary.resolve(), options.output_dir, options.record,
          options.online_source.resolve() if options.online_source is not None else None)


if __name__ == "__main__":
    main()
