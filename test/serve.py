#!/usr/bin/env python3
"""Serve the self-test on 127.0.0.1:8765 with caching disabled (so edits show on a normal reload)."""
import functools, http.server, os
class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
d = os.path.dirname(os.path.abspath(__file__))
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), functools.partial(NoCache, directory=d)).serve_forever()
