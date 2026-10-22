#!/usr/bin/env python3
"""Run Flutter and request hot reload after Dart source changes settle."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def snapshot(root):
    files = {}
    for path in root.rglob('*.dart'):
        try:
            stat = path.stat()
            files[path] = (stat.st_mtime_ns, stat.st_size)
        except FileNotFoundError:
            pass
    return files


def main():
    source = Path.cwd() / 'lib'
    with tempfile.TemporaryDirectory(prefix='.flutter-watch-', dir='.') as temp:
        pid_file = Path(temp).resolve() / 'flutter.pid'
        command = ['flutter', 'run', '--hot', '--pid-file', str(pid_file), *sys.argv[1:]]
        process = subprocess.Popen(command)
        previous = snapshot(source)
        changed_at = None
        print('Auto hot reload: watching frontend/lib/**/*.dart', flush=True)
        try:
            while process.poll() is None:
                current = snapshot(source)
                if current != previous:
                    previous = current
                    changed_at = time.monotonic()
                if changed_at is not None and time.monotonic() - changed_at >= 0.5:
                    try:
                        flutter_pid = int(pid_file.read_text().strip())
                        os.kill(flutter_pid, signal.SIGUSR1)
                        print('Source changed: requesting hot reload.', flush=True)
                        changed_at = None
                    except (FileNotFoundError, ProcessLookupError, ValueError):
                        # Flutter installs signal handlers when startup is ready.
                        pass
                time.sleep(0.25)
        except KeyboardInterrupt:
            pass
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        return process.returncode


if __name__ == '__main__':
    sys.exit(main())
