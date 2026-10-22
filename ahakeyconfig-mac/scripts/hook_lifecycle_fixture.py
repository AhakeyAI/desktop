"""Loopback model-call detector for isolated hook lifecycle scripts."""
import http.server
import threading


class ForbiddenModelEndpoint:
    def __enter__(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.server.calls += 1
                self.send_error(503, "A lifecycle fixture must not call a model")

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.calls = 0
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


def terminate_process_group(process, grace_seconds=2):
    """Reap our fixture parent and confirm its whole process group is gone."""
    import os
    import signal
    import subprocess
    import time

    def group_exists():
        try:
            os.killpg(process.pid, 0)
            return True
        except ProcessLookupError:
            return False

    for stop_signal in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, stop_signal)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + grace_seconds
        while time.monotonic() < deadline:
            # poll also reaps an exited parent; its status alone does not prove
            # its subprocesses have exited.
            process.poll()
            if not group_exists():
                break
            time.sleep(.02)
        if not group_exists():
            break
    if process.poll() is None:
        try:
            process.wait(timeout=grace_seconds)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError("Fixture parent survived cleanup") from error
    if group_exists():
        raise RuntimeError("Fixture process group survived cleanup")
