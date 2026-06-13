#!/usr/bin/env python3
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def log(level, msg, **fields):
    print(json.dumps({"level": level, "msg": msg, **fields}), flush=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path in ("/health", "/smoke"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return
        if self.path != "/work":
            self.send_response(404)
            self.end_headers()
            return

        log("INFO", "request complete", route="/work", duration_ms=50)
        body = json.dumps({"status": "ok"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    log("INFO", "server start", port=8082)
    HTTPServer(("0.0.0.0", 8082), Handler).serve_forever()
