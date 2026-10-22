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

