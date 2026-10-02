#!/usr/bin/env bash
# ForgePulse blue-green deployment lab (local Ubuntu, no cloud services, no root needed at runtime)
#
#   ./bluegreen.sh setup            create everything, start BLUE on v1 and the nginx router
#   ./bluegreen.sh deploy <ver>     deploy a release to the idle env, validate, switch, verify
#   ./bluegreen.sh rollback         instantly switch back to the previous environment
#   ./bluegreen.sh status           show which env is live and what each one runs
#   ./bluegreen.sh load             live traffic probe (run in a 2nd terminal during deploys)
#   ./bluegreen.sh stop | clean
#
# Public URL (via router):   http://localhost:8080
# Blue  (direct/preview):    http://localhost:8081
# Green (direct/preview):    http://localhost:8082

set -euo pipefail

BASE="${FP_BASE:-$HOME/forgepulse}"
PUBLIC_PORT=8080
declare -A PORT=( [blue]=8081 [green]=8082 )
NGINX_CONF="$BASE/nginx/nginx.conf"
ACTIVE_CONF="$BASE/nginx/active.conf"

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_blu=$'\e[34m'; c_off=$'\e[0m'
log()  { echo "${c_blu}==>${c_off} $*"; }
ok()   { echo "${c_grn} ✔${c_off} $*"; }
warn() { echo "${c_ylw} !${c_off} $*"; }
die()  { echo "${c_red} ✘ $*${c_off}" >&2; exit 1; }

other() { [[ "$1" == "blue" ]] && echo green || echo blue; }
active_env()  { cat "$BASE/state/active" 2>/dev/null || echo none; }
env_version() { cat "$BASE/state/$1.version" 2>/dev/null || echo "-"; }

# ---------------------------------------------------------------- releases
write_app() {
cat > "$BASE/app.py" <<'PYEOF'
import json, os, random, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REL = json.load(open(os.path.join(HERE, "release.json")))
COLOR = os.environ.get("ENV_COLOR", "blue")
PORT = int(os.environ.get("PORT", "8081"))

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<title>ForgePulse Support Analytics</title>
<style>
 body{font-family:system-ui,sans-serif;margin:0;background:#0f172a;color:#e2e8f0}
 #banner{padding:18px 28px;font-size:22px;font-weight:700;transition:background .4s}
 #banner small{display:block;font-size:13px;font-weight:400;opacity:.85;margin-top:4px}
 .blue{background:#1d4ed8}.green{background:#15803d}.err{background:#b91c1c}
 main{padding:24px 28px;display:grid;gap:24px;max-width:1000px}
 .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px}
 .card{background:#1e293b;border-radius:10px;padding:16px}
 .card b{display:block;font-size:30px;margin-top:6px}
 .meta{display:flex;gap:28px;font-size:15px}
 #log{background:#020617;border-radius:8px;padding:12px;font:13px monospace;height:150px;overflow:auto}
 h3{margin:0 0 8px;font-size:14px;opacity:.7;text-transform:uppercase;letter-spacing:.05em}
</style></head><body>
<div id="banner" class="blue">Connecting…<small>polling /api/info every second</small></div>
<main>
 <div class="meta"><div>Requests OK: <b id="ok">0</b></div><div>Failed: <b id="bad">0</b></div>
  <div>Release notes: <b id="notes">-</b></div></div>
 <div><h3>Support analytics (live)</h3><div class="cards" id="cards"></div></div>
 <div><h3>Deployment events seen by this browser</h3><div id="log"></div></div>
</main>
<script>
var ok=0,bad=0,last=null;
function ev(m){var l=document.getElementById('log');l.innerHTML='['+new Date().toLocaleTimeString()+'] '+m+'<br>'+l.innerHTML;}
function poll(){
 fetch('/api/info',{cache:'no-store'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(function(d){
  ok++;var b=document.getElementById('banner');b.className=d.env;
  b.innerHTML='Served by '+d.env.toUpperCase()+' &middot; release '+d.version+'<small>pid '+d.pid+' &middot; '+d.time+'</small>';
  document.getElementById('notes').textContent=d.notes;
  var key=d.env+'/'+d.version;
  if(last!==null&&key!==last)ev('TRAFFIC SWITCHED: '+last+' &rarr; '+key);
  if(last===null)ev('First response from '+key);
  last=key;
 }).catch(function(){bad++;document.getElementById('banner').className='err';ev('request FAILED');})
 .then(function(){document.getElementById('ok').textContent=ok;document.getElementById('bad').textContent=bad;});
}
function stats(){
 fetch('/api/stats',{cache:'no-store'}).then(function(r){if(!r.ok)throw 0;return r.json();}).then(function(s){
  var h='';for(var k in s){h+='<div class="card">'+k.replace(/_/g,' ')+'<b>'+s[k]+'</b></div>';}
  document.getElementById('cards').innerHTML=h;
 }).catch(function(){document.getElementById('cards').innerHTML='<div class="card">stats unavailable</div>';});
}
setInterval(poll,1000);setInterval(stats,2000);poll();stats();
</script></body></html>"""

class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif p == "/health":
            self._send(200, json.dumps({"status": "ok"}))
        elif p == "/api/info":
            self._send(200, json.dumps({"env": COLOR, "version": REL["version"], "notes": REL["notes"],
                                        "pid": os.getpid(), "time": time.strftime("%H:%M:%S")}))
        elif p == "/api/stats":
            if REL.get("broken_stats"):
                self._send(500, json.dumps({"error": "stats aggregation crashed"}))
                return
            s = {"open_tickets": random.randint(120, 140),
                 "avg_first_response_min": round(random.uniform(8, 12), 1),
                 "csat_percent": round(random.uniform(91, 95), 1)}
            if "sla" in REL["features"]:
                s["sla_breaches_today"] = random.randint(2, 6)
            if "csat_trend" in REL["features"]:
                s["csat_7d_trend"] = "+%.1f pts" % random.uniform(0.2, 1.4)
            self._send(200, json.dumps(s))
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def log_message(self, *a):
        pass

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
PYEOF
}

make_release() {  # version notes features_json broken_stats
  local d="$BASE/releases/$1"; mkdir -p "$d"
  cp "$BASE/app.py" "$d/app.py"
  printf '{"version":"%s","notes":"%s","features":%s,"broken_stats":%s}\n' "$1" "$2" "$3" "$4" > "$d/release.json"
}

# ---------------------------------------------------------------- env control
start_env() {  # color version
  local color="$1" ver="$2" pidf="$BASE/run/$1.pid"
  stop_env "$color"
  ENV_COLOR="$color" PORT="${PORT[$color]}" nohup python3 "$BASE/releases/$ver/app.py" \
      >"$BASE/logs/$color.log" 2>&1 &
  echo $! > "$pidf"
  echo "$ver" > "$BASE/state/$color.version"
}

stop_env() {
  local pidf="$BASE/run/$1.pid"
  if [[ -f "$pidf" ]]; then kill "$(cat "$pidf")" 2>/dev/null || true; rm -f "$pidf"; fi
  sleep 0.3
}

wait_healthy() {  # port
  for _ in $(seq 1 30); do
    curl -fsS --max-time 1 "http://127.0.0.1:$1/health" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

smoke_test() {  # port version   -> validates the idle env BEFORE it gets any user traffic
  local port="$1" ver="$2" info stats
  curl -fsS --max-time 2 "http://127.0.0.1:$port/health" >/dev/null       || { warn "health check failed"; return 1; }
  info=$(curl -fsS --max-time 2 "http://127.0.0.1:$port/api/info")         || { warn "/api/info failed"; return 1; }
  [[ "$info" == *"\"version\": \"$ver\""* ]]                                || { warn "wrong version reported: $info"; return 1; }
  stats=$(curl -fsS --max-time 2 "http://127.0.0.1:$port/api/stats")       || { warn "/api/stats returned an error"; return 1; }
  [[ "$stats" == *open_tickets* ]]                                          || { warn "stats payload invalid"; return 1; }
  curl -fsS --max-time 2 "http://127.0.0.1:$port/" | grep -q ForgePulse     || { warn "home page invalid"; return 1; }
  return 0
}

# ---------------------------------------------------------------- traffic switch
write_active_conf() {  # color
  cat > "$ACTIVE_CONF.tmp" <<EOF
upstream forgepulse_active { server 127.0.0.1:${PORT[$1]}; }
map \$host \$active_env { default $1; }
EOF
  mv "$ACTIVE_CONF.tmp" "$ACTIVE_CONF"     # atomic replace
}

switch_to() {  # color   -> graceful nginx reload: in-flight requests finish, new ones go to the new env
  local color="$1" prev; prev=$(active_env)
  write_active_conf "$color"
  if ! nginx -t -c "$NGINX_CONF" >/dev/null 2>&1; then
    write_active_conf "$prev"; die "nginx config test failed - switch aborted, traffic unchanged"
  fi
  nginx -c "$NGINX_CONF" -s reload
  echo "$prev"  > "$BASE/state/previous"
  echo "$color" > "$BASE/state/active"
}

live_version() { curl -fsS --max-time 2 "http://127.0.0.1:$PUBLIC_PORT/api/info" 2>/dev/null | sed -n 's/.*"version": "\([^"]*\)".*/\1/p'; }
live_env()     { curl -fsS --max-time 2 "http://127.0.0.1:$PUBLIC_PORT/api/info" 2>/dev/null | sed -n 's/.*"env": "\([a-z]*\)".*/\1/p'; }

# ---------------------------------------------------------------- commands
cmd_setup() {
  command -v nginx   >/dev/null || die "nginx missing:   sudo apt update && sudo apt install -y nginx"
  command -v python3 >/dev/null || die "python3 missing: sudo apt install -y python3"
  command -v curl    >/dev/null || die "curl missing:    sudo apt install -y curl"
  log "Creating layout in $BASE"
  mkdir -p "$BASE"/{releases,run/tmp,logs,state,nginx}
  write_app
  make_release v1 "Baseline dashboard"                          '[]'                     false
  make_release v2 "Adds SLA breach tracking"                    '["sla"]'                false
  make_release v3 "Adds CSAT trend (contains a bug)"            '["sla","csat_trend"]'   true
  make_release v4 "CSAT trend fixed"                            '["sla","csat_trend"]'   false
  ok "Releases built: v1, v2, v3 (buggy on purpose), v4"

  cat > "$NGINX_CONF" <<EOF
worker_processes 1;
pid $BASE/run/nginx.pid;
error_log $BASE/logs/nginx-error.log warn;
events { worker_connections 512; }
http {
  access_log $BASE/logs/nginx-access.log;
  client_body_temp_path $BASE/run/tmp/body;
  proxy_temp_path       $BASE/run/tmp/proxy;
  fastcgi_temp_path     $BASE/run/tmp/fcgi;
  uwsgi_temp_path       $BASE/run/tmp/uwsgi;
  scgi_temp_path        $BASE/run/tmp/scgi;
  include $ACTIVE_CONF;                 # <-- the ONLY file that changes on a switch
  server {
    listen $PUBLIC_PORT;
    location / {
      proxy_pass http://forgepulse_active;
      proxy_set_header Host \$host;
      proxy_connect_timeout 2s;
      add_header X-Active-Env \$active_env always;
    }
  }
}
EOF
  log "Starting BLUE with v1 and the router"
  start_env blue v1
  wait_healthy "${PORT[blue]}" || die "blue did not become healthy (see $BASE/logs/blue.log)"
  write_active_conf blue
  echo blue > "$BASE/state/active"; echo none > "$BASE/state/previous"
  if [[ -f "$BASE/run/nginx.pid" ]] && kill -0 "$(cat "$BASE/run/nginx.pid")" 2>/dev/null; then
    nginx -c "$NGINX_CONF" -s reload
  else
    nginx -c "$NGINX_CONF" 2>/dev/null || die "nginx failed to start - is port $PUBLIC_PORT in use?"
  fi
  sleep 0.5
  ok "Live at http://localhost:$PUBLIC_PORT  (BLUE, v1)"
  echo "   Open it in a browser now, then run './bluegreen.sh deploy v2'"
}

cmd_deploy() {
  local ver="${1:-}"; [[ -n "$ver" ]] || die "usage: deploy <version>  (v1..v4)"
  [[ -d "$BASE/releases/$ver" ]] || die "unknown release '$ver'"
  local live idle; live=$(active_env); idle=$(other "$live")
  log "LIVE = $live ($(env_version "$live"))   IDLE = $idle ($(env_version "$idle"))"
  [[ "$(env_version "$live")" != "$ver" ]] || die "$ver is already live on $live"

  local old_idle_ver; old_idle_ver=$(env_version "$idle")
  restore_idle() { stop_env "$idle"; echo "-" > "$BASE/state/$idle.version"
                   if [[ "$old_idle_ver" != "-" ]]; then start_env "$idle" "$old_idle_ver"; wait_healthy "${PORT[$idle]}" || true; fi; }

  log "1/5 Deploying $ver to idle env '$idle' (users are untouched)"
  start_env "$idle" "$ver"
  wait_healthy "${PORT[$idle]}" || { restore_idle; die "$idle never became healthy - deploy aborted, $live still serving"; }
  ok "$idle is up on :${PORT[$idle]}"

  log "2/5 Smoke-testing $idle directly (health, version, stats API, home page)"
  if ! smoke_test "${PORT[$idle]}" "$ver"; then
    restore_idle
    die "Validation FAILED for $ver - release blocked. Users never saw it; $live keeps serving."
  fi
  ok "all smoke tests passed"

  log "3/5 Switching traffic $live -> $idle (graceful nginx reload)"
  switch_to "$idle"

  log "4/5 Verifying through the public URL"
  sleep 1
  local bad=0
  for _ in 1 2 3 4 5; do [[ "$(live_version)" == "$ver" ]] || bad=1; sleep 0.3; done
  if (( bad )); then
    warn "post-switch verification failed - AUTO ROLLBACK"
    switch_to "$live"; die "rolled back to $live ($(env_version "$live"))"
  fi
  ok "public URL now serves $ver from $idle"

  log "5/5 Keeping $live ($(env_version "$live")) running as hot standby for instant rollback"
  ok "Deployment complete.  Rollback any time with: ./bluegreen.sh rollback"
}

cmd_rollback() {
  local live prev; live=$(active_env); prev=$(cat "$BASE/state/previous" 2>/dev/null || echo none)
  [[ "$prev" == "blue" || "$prev" == "green" ]] || die "nothing to roll back to"
  wait_healthy "${PORT[$prev]}" || die "standby '$prev' is not healthy - cannot roll back"
  log "Rolling back $live ($(env_version "$live")) -> $prev ($(env_version "$prev"))"
  switch_to "$prev"
  sleep 1
  ok "Live is now $(live_env) / $(live_version)"
}

cmd_status() {
  local a; a=$(active_env)
  echo "Public URL : http://localhost:$PUBLIC_PORT  -> $(live_env || true) / $(live_version || true)"
  for c in blue green; do
    local st="stopped"
    [[ -f "$BASE/run/$c.pid" ]] && kill -0 "$(cat "$BASE/run/$c.pid")" 2>/dev/null && st="running"
    printf "  %-6s %-8s version=%-4s port=%s  %s\n" "$c" "$st" "$(env_version "$c")" "${PORT[$c]}" \
      "$([[ $c == "$a" ]] && echo '<== LIVE' || echo '(idle / standby)')"
  done
}

cmd_load() {
  local ok_n=0 bad_n=0 last="" r e v
  trap 'echo; echo "Summary: $ok_n OK, $bad_n failed"; exit 0' INT
  echo "Probing http://localhost:$PUBLIC_PORT every 0.1s  (Ctrl-C for summary)"
  while true; do
    r=$(curl -s --max-time 2 -w ' %{http_code}' "http://127.0.0.1:$PUBLIC_PORT/api/info" || true)
    if [[ "$r" == *" 200" ]]; then
      ok_n=$((ok_n+1))
      e=$(sed -n 's/.*"env": "\([a-z]*\)".*/\1/p' <<<"$r"); v=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' <<<"$r")
      if [[ "$e/$v" != "$last" ]]; then echo "$(date +%T)  now served by ${e^^} / $v   (ok=$ok_n failed=$bad_n)"; last="$e/$v"; fi
    else
      bad_n=$((bad_n+1)); echo "${c_red}$(date +%T)  REQUEST FAILED${c_off}"
    fi
    sleep 0.1
  done
}

cmd_stop()  { stop_env blue; stop_env green; [[ -f "$BASE/run/nginx.pid" ]] && nginx -c "$NGINX_CONF" -s stop 2>/dev/null || true; ok "stopped"; }
cmd_clean() { cmd_stop; rm -rf "$BASE"; ok "removed $BASE"; }

case "${1:-}" in
  setup)    cmd_setup ;;
  deploy)   shift; cmd_deploy "${1:-}" ;;
  rollback) cmd_rollback ;;
  status)   cmd_status ;;
  load)     cmd_load ;;
  stop)     cmd_stop ;;
  clean)    cmd_clean ;;
  *)        sed -n '2,13p' "$0" ;;
esac
