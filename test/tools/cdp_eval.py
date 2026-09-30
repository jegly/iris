#!/usr/bin/env python3
"""Tiny DevTools-protocol client (stdlib only): navigate the first page target of a browser started with
--remote-debugging-port=PORT to URL, wait, evaluate a JS expression, print the result.
Usage: cdp_eval.py PORT URL 'js expression' [wait_seconds]"""
import base64, json, os, socket, struct, sys, time, urllib.request
port, url, expr = int(sys.argv[1]), sys.argv[2], sys.argv[3]
wait = float(sys.argv[4]) if len(sys.argv) > 4 else 3
tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
ws_url = next(t["webSocketDebuggerUrl"] for t in tabs if t["type"] == "page")
path = ws_url.split(str(port), 1)[1]
s = socket.create_connection(("127.0.0.1", port))
key = base64.b64encode(os.urandom(16)).decode()
s.send((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf: buf += s.recv(4096)
def send(obj):
    data = json.dumps(obj).encode(); mask = os.urandom(4); n = len(data)
    hdr = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n))
    s.send(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
def recv():
    def rd(n):
        out = b""
        while len(out) < n: out += s.recv(n - len(out))
        return out
    b1, b2 = rd(2); n = b2 & 0x7F
    if n == 126: n = struct.unpack(">H", rd(2))[0]
    elif n == 127: n = struct.unpack(">Q", rd(8))[0]
    return json.loads(rd(n))
def call(i, method, params):
    send({"id": i, "method": method, "params": params})
    while True:
        m = recv()
        if m.get("id") == i: return m
call(1, "Page.navigate", {"url": url}); time.sleep(wait)
r = call(2, "Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": True})
res = r.get("result", {})
print(res["result"].get("value") if "value" in res.get("result", {}) else json.dumps(r)[:1500])
