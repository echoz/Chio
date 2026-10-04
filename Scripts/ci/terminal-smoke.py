#!/usr/bin/env python3
"""Exercise the release dashboard in a real POSIX pseudo-terminal.

The small text-screen reader only handles the cursor/erase sequences emitted by
these fixed-size, single-cell fixtures. It does not validate colors or emulate a
general terminal; SwiftTUI's public raster tests own detailed rendering checks.
"""

import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time


WIDTH, HEIGHT = 100, 30
ESCAPE = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])|\x1b\].*?(?:\x07|\x1b\\)", re.S)


def screen(output):
    cells = [[" "] * WIDTH for _ in range(HEIGHT)]
    row = column = index = 0
    value = output.decode("utf-8", errors="replace")
    while index < len(value):
        char = value[index]
        if char == "\x1b":
            match = ESCAPE.match(value, index)
            if not match:
                break  # A later read completes a split escape sequence.
            raw, _, final = match.groups()
            args = [int(x or 0) for x in (raw or "").lstrip("?").split(";")
                    if x.isdigit() or not x]
            first = args[0] if args else 0
            if final in ("H", "f"):
                row = max(0, (first or 1) - 1)
                column = max(0, (args[1] or 1) - 1) if len(args) > 1 else 0
            elif final == "A":
                row = max(0, row - (first or 1))
            elif final == "B":
                row += first or 1
            elif final == "C":
                column += first or 1
            elif final == "D":
                column = max(0, column - (first or 1))
            elif final == "G":
                column = (first or 1) - 1
            elif final == "d":
                row = (first or 1) - 1
            elif final == "J" and first in (2, 3):
                cells = [[" "] * WIDTH for _ in range(HEIGHT)]
            elif final == "K" and 0 <= row < HEIGHT:
                start, end = ((0, WIDTH) if first == 2 else
                              ((0, column + 1) if first == 1 else (column, WIDTH)))
                for x in range(max(0, start), min(WIDTH, end)):
                    cells[row][x] = " "
            index = match.end()
            continue
        if char == "\r":
            column = 0
        elif char == "\n":
            row += 1
        elif char == "\b":
            column = max(0, column - 1)
        elif char >= " ":
            if 0 <= row < HEIGHT and 0 <= column < WIDTH:
                cells[row][column] = char
            column += 1
        index += 1
    return "\n".join("".join(line) for line in cells)


def run(binary, choices=False):
    master, slave = pty.openpty()
    process = None
    output = bytearray()
    original_modes = termios.tcgetattr(slave)

    def receive(timeout=0.1):
        if not select.select([master], [], [], timeout)[0]:
            return False
        try:
            chunk = os.read(master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:  # Linux reports a closed PTY this way.
                return False
            raise
        output.extend(chunk)
        if len(output) > 8 * 1024 * 1024:
            raise AssertionError("Terminal output exceeded the smoke check's 8 MiB limit")
        return bool(chunk)

    def until(expected, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            receive()
            if expected in screen(output):
                # Finish queued frame/focus updates before the next user action.
                while time.monotonic() < deadline and receive(0.25):
                    pass
                if expected in screen(output):
                    print("Observed:", expected, flush=True)
                    return
            if process.poll() is not None:
                break
        raise AssertionError("Not observed: " + expected)

    def send(value, expected):
        os.write(master, value)
        until(expected)

    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
        env = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
        for key in ("NO_COLOR", "CLICOLOR", "CLICOLOR_FORCE", "FORCE_COLOR"):
            env.pop(key, None)
        process = subprocess.Popen([str(binary), "--choices" if choices else "--paused"], stdin=slave,
                                   stdout=slave, stderr=slave, env=env)
        until("1 / 2" if choices else "4 of 4 items")
        modes = termios.tcgetattr(slave)
        assert not modes[3] & (termios.ECHO | termios.ICANON), "Terminal is not in raw input mode"
        assert modes[6][termios.VMIN] == 1 and modes[6][termios.VTIME] == 0, "Unexpected raw read timing"
        assert b"\x1b[?1049h" in output, "Alternate screen was not entered"

        if choices:
            send(b"/rust", "1 of 4 items")
            send(b"\r\r", "2 / 2")
            send(b"\x13", "Error: Choose at least 1")  # Ctrl-S validates.
            send(b"build", "1 of 6 items")
            send(b"\r", "1 of 6 items")
            send(b" ", "1 selected")
            send(b"\x1b", "6 of 6 items")
            send(b"/test", "1 hidden")
            send(b"\r", "1 hidden")
            send(b" ", "2 selected")
            send(b"\x13", "Saved: Rust")
            until("Build, Test")
            send(b"\x02", "1 / 2")  # Ctrl-B retains draft and query.
            until("1 of 4 items")
            send(b"\x18", "Cancelled")  # Ctrl-X restores original choices.
            until("4 of 4 items")
            send(b"\x13", "2 / 2")
            until("0 selected")
        else:
            send(b"/docs", "1 of 4 items")
            send(b"\x0b", "esc close")  # Ctrl-K opens the native palette from search.
            send(b"zzzz", "No matches.")
            send(b"\x1b", "1 of 4 items")
            send(b"q", "docsq")  # Cancellation must restore the editor, not quit.
            send(b"\x1b", "4 of 4 items")
            send(b"\x0b", "esc close")
            send(b"report", "Open agent report")
            send(b"\r", "/ agent report")
            until("Table example")
            send(b"\x1b", "/ agent workspace")
            send(b"n", "/ create agent")
            send(b"Smoke Agent", "Smoke Agent")
            send(b"\x1b", "/ agent workspace")

        os.write(master, b"\x11" if choices else b"q")
        deadline = time.monotonic() + 15
        while process.poll() is None and time.monotonic() < deadline:
            receive()
        process.wait(timeout=1)
        while receive(0):
            pass
        assert process.returncode == 0, f"Dashboard exited with {process.returncode}"
        assert b"\x1b[?1049l" in output, "Alternate screen was not restored"
        assert termios.tcgetattr(slave) == original_modes, "Terminal modes were not restored"
        print("PASS: searchable choices, hidden checks, validation, save/cancel, clean exit" if choices else
              "PASS: raw input, search, palette, report/table, form, focus restoration, clean exit")
    except Exception:
        print("Last terminal screen:\n" + screen(output), file=sys.stderr)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        os.close(master)
        os.close(slave)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="Path to a built chio-dashboard executable")
    parser.add_argument("--choices", action="store_true", help="Exercise the focused choice example")
    arguments = parser.parse_args()
    run(arguments.binary.resolve(), choices=arguments.choices)
