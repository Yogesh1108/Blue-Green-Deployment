#!/usr/bin/env python3
"""ForgePulse demo app: one process = one environment (blue or green)."""
import json, os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8081"))
COLOR = os.environ.get("COLOR", "blue")
VERSION = os.environ.get("VERSION", "v1")
FAIL_HEALTH = os.environ.get("FAIL_HEALTH", "0") == "1"   # simulate a broken release
START = time.time()

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>ForgePulse Analytics</title>
<style>
body{font-family:system-ui,sans-serif;margin:0;background:#f4f6f8;color:#1d2733}
header{padding:24px 32px;color:#fff;background:#444;transition:background .3s}
h1{margin:0;font-size:22px} .sub{opacity:.85;margin-top:4px}
main{padding:24px 32px;max-width:820px}
.card{background:#fff;border-radius:10px;padding:16px 20px;margin-bottom:16px;box-shadow:0 1px 3px #0002}
.big{font-size:28px;font-weight:700} .k{display:flex;gap:16px;flex-wrap:wrap}
.k div{flex:1;min-width:160px}
.pill{display:inline-block;padding:2px 10px;border-radius:99px;color:#fff;font-size:13px}
.blue{background:#2563eb}.green{background:#16a34a}.down{background:#dc2626}
#log{font:13px ui-monospace,monospace;max-height:220px;overflow:auto;margin:0;padding:0;list-style:none}
#log li{padding:2px 0;border-bottom:1px solid #eee}
</style></head><body>
<header id="hd"><h1>ForgePulse - Support Analytics</h1>
<div class="sub">Live view. This page polls the router every second.</div></header>
<main>
<div class="card k">
 <div><div class="sub">Serving environment</div><div class="big" id="env">...</div></div>
 <div><div class="sub">App version</div><div class="big" id="ver">...</div></div>
 <div><div class="sub">Open tickets (demo data)</div><div class="big" id="tix">...</div></div>
</div>
<div class="card"><b>Request log</b> (newest first)<ul id="log"></ul></div>
</main>
<script>
const colors={blue:'#2563eb',green:'#16a34a'};let n=0;
async function tick(){
  const li=document.createElement('li');n++;
  try{
    const r=await fetch('/api/info',{cache:'no-store'});const d=await r.json();
    document.getElementById('env').innerHTML='<span class="pill '+d.env+'">'+d.env.toUpperCase()+'</span>';
    document.getElementById('ver').textContent=d.version;
    document.getElementById('tix').textContent=d.open_tickets;
    document.getElementById('hd').style.background=colors[d.env];
    li.textContent='#'+n+'  '+new Date().toLocaleTimeString()+'  200  '+d.env+' '+d.version;
  }catch(e){li.innerHTML='#'+n+'  <span class="pill down">FAILED</span> '+e;}
  const log=document.getElementById('log');log.prepend(li);while(log.children.length>40)log.lastChild.remove();
}
setInterval(tick,1000);tick();
</script></body></html>"""

class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("X-Env", COLOR)
        self.send_header("X-Version", VERSION)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/health":
            if FAIL_HEALTH:
                return self._send(500, json.dumps({"status": "unhealthy", "env": COLOR, "version": VERSION}))
            return self._send(200, json.dumps({"status": "ok", "env": COLOR, "version": VERSION,
                                               "uptime_s": round(time.time() - START, 1)}))
        if self.path == "/api/info":
            return self._send(200, json.dumps({"env": COLOR, "version": VERSION,
                                               "open_tickets": 128 + (len(VERSION) * 7), "ts": time.time()}))
        if self.path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        self._send(404, json.dumps({"error": "not found"}))

    def log_message(self, fmt, *a):
        print("[%s %s] %s" % (COLOR, VERSION, fmt % a), flush=True)

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
