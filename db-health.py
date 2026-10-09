from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
import socket

PORT = int(os.environ.get("PORT", "10000"))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with socket.create_connection(("127.0.0.1", 3306), timeout=1):
                ready = True
        except OSError:
            ready = False

        self.send_response(200 if ready else 503)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b"MariaDB ready" if ready else b"MariaDB starting")

    def log_message(self, format, *args):
        return

ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
