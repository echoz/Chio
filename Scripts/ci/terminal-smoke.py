#!/usr/bin/env python3
"""Exercise the release dashboard in a real POSIX pseudo-terminal.

The small text-screen reader only handles the cursor, erase and scroll sequences emitted by
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
import signal
import struct
import subprocess
import sys
import termios
import tempfile
import time


WIDTH, HEIGHT = 100, 30
ESCAPE = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])|\x1b\].*?(?:\x07|\x1b\\)", re.S)


def screen(output):
    cells = [[" "] * WIDTH for _ in range(HEIGHT)]
    row = column = index = 0
    region_top, region_bottom = 0, HEIGHT - 1
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
            elif final == "r":
                region_top = min(HEIGHT - 1, max(0, (first or 1) - 1))
                region_bottom = min(HEIGHT - 1, max(region_top, (args[1] or HEIGHT) - 1)) if len(args) > 1 else HEIGHT - 1
                row = column = 0
            elif final in ("S", "T"):
                count = min(first or 1, region_bottom - region_top + 1)
                blank = [[" "] * WIDTH for _ in range(count)]
                region = cells[region_top:region_bottom + 1]
                cells[region_top:region_bottom + 1] = (region[count:] + blank if final == "S"
                                                      else blank + region[:-count])
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


def run(binary, choices=False, text_entry=False, feedback=False, files=False, keyboard_help=False, tabs=False, pagination=False, viewport=False, tree=False, forms=False, timers=False):
    global WIDTH, HEIGHT
    master, slave = pty.openpty()
    process = None
    output = bytearray()
    original_modes = termios.tcgetattr(slave)
    file_fixture = tempfile.TemporaryDirectory(prefix="chio-files-") if files else None

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
        example = "--timers" if timers else "--forms" if forms else "--tree" if tree else "--viewport" if viewport else "--pagination" if pagination else "--tabs" if tabs else "--keyboard-help" if keyboard_help else "--files" if files else "--feedback" if feedback else "--text-entry" if text_entry else "--choices" if choices else "--paused"
        command = [str(binary), example]
        if file_fixture is not None:
            folder = Path(file_fixture.name)
            (folder / "alpha.txt").write_text("alpha\n")
            (folder / "nested").mkdir()
            (folder / "nested" / "inside.txt").write_text("inside\n")
            command.extend(["--directory", str(folder)])
        process = subprocess.Popen(command, stdin=slave,
                                   stdout=slave, stderr=slave, env=env)
        until("/ time studio" if timers else "Saved: Chio · manual" if forms else "Expanded folders: 3 / 6" if tree else "Row 2 · Col 2" if viewport else "1–3 of 23" if pagination else "Demo runs: 0" if tabs else "Runs: 0" if keyboard_help else "alpha.txt" if files else "Ready to publish" if feedback else "/ text entry" if text_entry else "1 / 2" if choices else "4 of 4 items")
        modes = termios.tcgetattr(slave)
        assert not modes[3] & (termios.ECHO | termios.ICANON), "Terminal is not in raw input mode"
        assert modes[6][termios.VMIN] == 1 and modes[6][termios.VTIME] == 0, "Unexpected raw read timing"
        assert b"\x1b[?1049h" in output, "Alternate screen was not entered"

        if timers:
            until("0:20")
            send(b"\r", "Running")
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                elapsed = re.search(r"0:(\d{2})", screen(output))
                if elapsed and int(elapsed.group(1)) > 0:
                    break
                receive()
            else:
                raise AssertionError("Stopwatch did not advance while running")
            send(b"\r", "Resume")
            send(b"\x14", "Resume")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("^Q quit")
            until("Resume")
            send(b"c", "Running")
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                remaining = re.search(r"0:(\d{2})", screen(output).split("Countdown", 1)[-1])
                if remaining and 0 < int(remaining.group(1)) < 20:
                    break
                receive()
            else:
                raise AssertionError("Countdown did not advance while running")
            send(b"c", "Resume")
            deadline = time.monotonic() + 15
            while "Running" in screen(output) and time.monotonic() < deadline:
                receive()
            assert "Running" not in screen(output), "Countdown did not pause independently"
            send(b"r", "0:20")
            until("0:00")
            assert "Running" not in screen(output), "Reset left a clock running"
        elif forms:
            send(b"\x1b[FAB\x13", "Saved: ChioAB · manual")
            send(b"\t ", "Interval (minutes)")
            send(b"\t\x1b[F\x7f\x7f3\x13", "Timeout must be shorter")
            until("Saved: ChioAB · manual")
            send(b"\x1b[F\x7f1\x13", "Saved: ChioAB · every 3m, timeout 1m")
            send(b"\x1b[F\x7fbad\x13", "Use whole minutes")
            until("Saved: ChioAB · every 3m, timeout 1m")
            send(b"\x18", "Cancelled")
            send(b"X", "Unsaved changes")
            send(b"\x18", "Cancelled")
            send(b"\x14", "Cancelled")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("^Q quit")
            until("Save")
            until("Cancel")
            send(b"\x13", "Saved locally")
        elif tree:
            send(b"\r", "Expanded folders: 2 / 6")
            assert "SearchableList.swift" not in screen(output), "Collapsed parent still shows children"
            send(b" ", "Expanded folders: 3 / 6")
            until("SearchableList.swift")
            send(b"\t\t ", "Expanded folders: 2 / 6")
            assert "SearchableList.swift" not in screen(output), "Collapsed child still shows content"
            send(b"\x14", "Expanded folders: 2 / 6")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("Expanded folders: 2 / 6")
            until("^Q quit")
            send(b" ", "Expanded folders: 3 / 6")
            until("SearchableList.swift")
        elif viewport:
            send(b"\x1b[H\x1b[D", "Row 1 · Col 1")
            send(b"\x1b[B\x1b[B\x1b[C", "Row 3 · Col 2")
            send(b"\x14", "Row 3 · Col 2")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("Row 3 · Col 2")
            until("^Q quit")
            send(b"\x1b[H", "Row 1 · Col 2")
            send(b"\x1b[D\x1b[F", "40  ✓  Docs agent")
            send(b"\x1b[H", "Row 1 · Col 1")
            send(b"\x1b[C", "Row 1 · Col 2")
            send(b"\t\t\t\r", "Row 1 · Col 1")
            send(b"\x1b[17~", "Row 2 · Col 2")
            send(b"\x1b[B", "Row 3 · Col 2")
        elif pagination:
            send(b"build", "1–3 of 6")
            send(b"\t\t\t\r", "4–6 of 6")
            until("Build 13")
            send(b"\x14", "4–6 of 6")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("^Q quit")
            until("4–6 of 6")
            send(b"\x12", "1–3 of 23")  # Ctrl-R explicitly resets the result set.
        elif tabs:
            send(b"\x1b[C", "Workspace overview")  # Right changes focus, not selection.
            assert "Agent directory" not in screen(output), "Tab focus activated a page"
            send(b"\x1b[H\r", "Workspace overview")
            send(b"\t\r", "Demo runs: 1")
            send(b"\x1b[17~", "←→ choose")  # F6 returns to the native tab strip.
            send(b"\x1b[H\x1b[C\x1b[C\r", "Scratch notes")
            send(b"\tDraft", "Characters: 5")
            send(b"\x1b[D!", "Characters: 6")
            send(b"\x1b[17~", "←→ choose")
            send(b"\x1b[H\r", "Demo runs: 1")
            send(b"\x1b[C\x1b[C\r", "Characters: 6")
            send(b"\x14", "Characters: 6")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("More")
            send(b"\x1b[F", "Characters: 6")
            send(b"\r", "More ▴")
            send(b"\r", "Quiet mode: off")
            send(b"\x1b[H\r", "Demo runs: 1")
        elif keyboard_help:
            send(b"/?", "No matches.")
            assert "Keyboard shortcuts" not in screen(output), "Question mark escaped the search editor"
            send(b"\x1bOP", "Keyboard shortcuts")  # F1 can open help while editing.
            until("All shortcuts")
            send(b"\x1b", "No matches.")
            assert "Keyboard shortcuts" not in screen(output), "Escape did not dismiss help"
            send(b"\x1b", "4 of 4 items")
            send(b"/Review", "1 of 4 items")
            send(b"\r", "Review Agent")
            send(b"?\x12", "Keyboard shortcuts")  # Opening batch must not run an agent.
            until("Browse")
            send(b"\x1b", "1 of 4 items")
            until("Runs: 0")
            send(b"\x12", "Runs: 1")
            send(b"?", "Keyboard shortcuts")
            send(b"\x14", "Keyboard shortcuts")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("Keyboard shortcuts")
            send(b"\x1b", "Runs: 1")
            until("? help")
        elif files:
            send(b"/alpha", "1 of 2 items")
            send(b"\r", "alpha.txt")  # Search hands focus to the filtered row.
            send(b"\x14", "alpha.txt")
            WIDTH, HEIGHT = 36, 18
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
            process.send_signal(signal.SIGWINCH)
            until("^Q quit")
            until("Choose")
            send(b"\r", "Selected file")
            until("alpha.txt")
            send(b"\x0f", "Filter files")  # Ctrl-O reopens the picker.
            until("nested")
            send(b"\x07", "Cancelled")
            until("alpha.txt")  # Cancel preserves the earlier committed file.
            send(b"\r", "Filter files")  # The native action also reopens.
        elif feedback:
            send(b"\r", "Publish report?")
            send(b"\x1b", "Ready to publish")
            assert "Publish report?" not in screen(output), "Escape did not dismiss confirmation"
            send(b"\r", "Publish report?")
            send(b"\t\t\r", "Ready to publish")  # Close, message viewport, then Cancel.
            assert "Publish report?" not in screen(output), "Cancel did not dismiss confirmation"
            send(b"\r", "Publish report?")
            send(b"\t\t\t\r", "Report published")
            until("Published · ready to share")
            send(b"\x04", "Discard report?")
            send(b"\t\t\t\r", "Ready to publish")
            send(b"\x14", "Ready to publish")
        elif text_entry:
            password = b"ChioDemo482!"  # Synthetic fixture; never use a real credential.
            send(b"\x13", "Error: Use at least 8")
            send(password, "•" * len(password))
            send(b"\t", "Notes")
            send(b"\x1b[200~FIRST\nSECOND\nLAST\x1b[201~", "LAST")
            send(b"\x04", "Inputs locked")
            os.write(master, b"MUSTNOTEDIT")
            send(b"\x14", "Inputs locked")  # Theme redraw also observes disabled input.
            assert "MUSTNOTEDIT" not in screen(output), "Disabled input accepted text"
            send(b"\x04", "^D lock")
            send(b"\x13", "Accepted")
            until("password cleared")
            assert password not in output, "Synthetic password leaked into terminal output"
            assert "•" not in screen(output), "Password was not cleared on acceptance"
            send(b"\x18", "Cancelled")
            assert "FIRST" not in screen(output), "Cancel did not clear notes"
        elif choices:
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

        os.write(master, b"\x11" if choices or text_entry or feedback or files or keyboard_help or tabs or pagination or viewport or tree or forms or timers else b"q")
        deadline = time.monotonic() + 15
        while process.poll() is None and time.monotonic() < deadline:
            receive()
        process.wait(timeout=1)
        while receive(0):
            pass
        assert process.returncode == 0, f"Dashboard exited with {process.returncode}"
        assert b"\x1b[?1049l" in output, "Alternate screen was not restored"
        assert termios.tcgetattr(slave) == original_modes, "Terminal modes were not restored"
        print("PASS: native timer actions, live ticks, pause, reset, theme, compact resize, clean exit" if timers else
              "PASS: grouped editing, cross-field validation, save/cancel, theme, compact resize, clean exit" if forms else
              "PASS: nested disclosure, retained expansion, native focus, theme, compact resize, clean exit" if tree else
              "PASS: two-axis scrolling, native focus and reset, theme, compact resize, clean exit" if viewport else
              "PASS: history filtering, native page activation, theme, compact resize, reset, clean exit" if pagination else
              "PASS: tab focus/selection, retained counter and draft, native editing, theme, overflow, resize, clean exit" if tabs else
              "PASS: contextual help, literal search input, focus restoration, guarded actions, theme, resize, clean exit" if keyboard_help else
              "PASS: file filtering, confirmation, reopen/cancel, theme, compact resize, clean exit" if files else
              "PASS: confirmation, cancellation, spinner, toast, destructive reset, clean exit" if feedback else
              "PASS: secure masking, multiline paste, disabled input, validation, clean exit" if text_entry else
              "PASS: searchable choices, hidden checks, validation, save/cancel, clean exit" if choices else
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
        if file_fixture is not None:
            file_fixture.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="Path to a built chio-dashboard executable")
    examples = parser.add_mutually_exclusive_group()
    examples.add_argument("--choices", action="store_true", help="Exercise the focused choice example")
    examples.add_argument("--text-entry", action="store_true", help="Exercise the focused text-entry example")
    examples.add_argument("--feedback", action="store_true", help="Exercise native prompts, spinner and toast")
    examples.add_argument("--files", action="store_true", help="Exercise filesystem selection in a temporary tree")
    examples.add_argument("--keyboard-help", action="store_true", help="Exercise contextual help and editor-safe opening")
    examples.add_argument("--tabs", action="store_true", help="Exercise tab focus, selection, retained drafts and narrow overflow")
    examples.add_argument("--pagination", action="store_true", help="Exercise history filtering, page navigation and resizing")
    examples.add_argument("--viewport", action="store_true", help="Exercise two-axis scrolling, focus and resizing")
    examples.add_argument("--tree", action="store_true", help="Exercise nested disclosure, expansion retention and resizing")
    examples.add_argument("--forms", action="store_true", help="Exercise grouped settings, cross-field validation and save/cancel")
    examples.add_argument("--timers", action="store_true", help="Exercise stopwatch, countdown, pause, reset and resizing")
    arguments = parser.parse_args()
    run(arguments.binary.resolve(), choices=arguments.choices, text_entry=arguments.text_entry,
        feedback=arguments.feedback, files=arguments.files, keyboard_help=arguments.keyboard_help, tabs=arguments.tabs,
        pagination=arguments.pagination, viewport=arguments.viewport, tree=arguments.tree, forms=arguments.forms, timers=arguments.timers)
