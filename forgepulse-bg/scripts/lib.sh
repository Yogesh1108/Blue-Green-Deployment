#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER_PORT=8080
port_of()  { [ "$1" = blue ] && echo 8081 || echo 8082; }
active()   { cat "$ROOT/state/active" 2>/dev/null || echo none; }
previous() { cat "$ROOT/state/previous" 2>/dev/null || echo none; }
idle()     { [ "$(active)" = blue ] && echo green || echo blue; }
version_of(){ cat "$ROOT/state/version_$1" 2>/dev/null || echo none; }
say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31mERR\033[0m %s\n' "$*"; }

stop_env() {
  local pidf="$ROOT/run/$1.pid"
  [ -f "$pidf" ] && kill "$(cat "$pidf")" 2>/dev/null || true
  rm -f "$pidf"
}
start_env() {  # color version [fail_health]
  stop_env "$1"; sleep 0.3
  PORT=$(port_of "$1") COLOR="$1" VERSION="$2" FAIL_HEALTH="${3:-0}" \
    nohup python3 "$ROOT/app/app.py" >>"$ROOT/logs/$1.log" 2>&1 &
  echo $! > "$ROOT/run/$1.pid"
  echo "$2" > "$ROOT/state/version_$1"
}
wait_healthy() {  # color, seconds
  local i; for i in $(seq 1 $(( $2 * 4 ))); do
    curl -fs "http://127.0.0.1:$(port_of "$1")/health" >/dev/null 2>&1 && return 0; sleep 0.25
  done; return 1
}
smoke_test() {  # color version -> validates the idle env BEFORE it gets traffic
  local base="http://127.0.0.1:$(port_of "$1")" v
  curl -fs "$base/health" | grep -q '"status": "ok"'        || { bad "health check failed"; return 1; }
  v=$(curl -fs "$base/api/info" | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])')
  [ "$v" = "$2" ]                                            || { bad "version mismatch ($v != $2)"; return 1; }
  curl -fs -o /dev/null "$base/"                            || { bad "home page failed"; return 1; }
  local i; for i in $(seq 1 20); do curl -fs -o /dev/null "$base/api/info" || { bad "request $i failed"; return 1; }; done
  ok "smoke test passed (health, version=$v, homepage, 20 requests)"
}
point_router_to() {  # color : atomic swap of upstream + graceful nginx reload
  local tmp="$ROOT/conf/upstream.conf.new"
  echo "upstream forgepulse_active { server 127.0.0.1:$(port_of "$1"); }" > "$tmp"
  cp "$ROOT/conf/upstream.conf" "$ROOT/conf/upstream.conf.bak"
  mv "$tmp" "$ROOT/conf/upstream.conf"
  if ! nginx -t -c "$ROOT/conf/nginx.conf" -p "$ROOT" >/dev/null 2>&1; then
    mv "$ROOT/conf/upstream.conf.bak" "$ROOT/conf/upstream.conf"; bad "nginx config test failed, reverted"; return 1
  fi
  nginx -s reload -c "$ROOT/conf/nginx.conf" -p "$ROOT"
  [ "$(active)" != none ] && active > "$ROOT/state/previous"
  echo "$1" > "$ROOT/state/active"
}
router_env() { curl -fs -o /dev/null -D - "http://127.0.0.1:$ROUTER_PORT/api/info" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-env"{print $2}'; }
