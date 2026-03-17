import json
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import threading


def set_winsize(fd: int, cols: int, rows: int) -> None:
    if cols <= 0 or rows <= 0:
        return
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl_ioctl = getattr(__import__("fcntl"), "ioctl")
    fcntl_ioctl(fd, termios.TIOCSWINSZ, winsize)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: pty_bridge.py <command> [args...]", file=sys.stderr)
        return 2

    command = sys.argv[1]
    args = sys.argv[2:]
    cwd = os.environ.get("TAIRI_PTY_CWD") or os.getcwd()

    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, 120, 32)

    child = subprocess.Popen(
        [command, *args],
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        cwd=cwd,
        env=os.environ.copy(),
        close_fds=True,
    )
    os.close(slave_fd)

    stdin_closed = threading.Event()
    control_reader = None

    try:
        control_reader = os.fdopen(3, "r", encoding="utf-8", buffering=1)
    except OSError:
        control_reader = None

    def pump_stdin() -> None:
        try:
            while True:
                data = os.read(0, 4096)
                if not data:
                    break
                os.write(master_fd, data)
        except OSError:
            pass
        finally:
            stdin_closed.set()

    def pump_control() -> None:
        if control_reader is None:
            return
        try:
            for line in control_reader:
                line = line.strip()
                if not line:
                    continue
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if message.get("type") == "resize":
                    cols = int(message.get("cols") or 0)
                    rows = int(message.get("rows") or 0)
                    set_winsize(master_fd, cols, rows)
                    if child.poll() is None:
                        child.send_signal(signal.SIGWINCH)
        except OSError:
            pass
        finally:
            try:
                control_reader.close()
            except OSError:
                pass

    threading.Thread(target=pump_stdin, daemon=True).start()
    threading.Thread(target=pump_control, daemon=True).start()

    try:
        while True:
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if master_fd in ready:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                os.write(1, chunk)
            if child.poll() is not None and stdin_closed.is_set():
                break
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()

    return child.returncode or 0


if __name__ == "__main__":
    raise SystemExit(main())
