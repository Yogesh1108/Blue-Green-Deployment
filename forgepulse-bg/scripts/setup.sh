#!/usr/bin/env bash
# One-time setup: writes nginx config, starts BLUE (v1) and the router.
source "$(dirname "$0")/lib.sh"
command -v nginx >/dev/null || { bad "nginx missing: sudo apt install -y nginx"; exit 1; }
command -v python3 >/dev/null || { bad "python3 missing"; exit 1; }
mkdir -p "$ROOT/run/tmp" "$ROOT/logs" "$ROOT/state" "$ROOT/conf"
cat > "$ROOT/conf/nginx.conf" <<CONF
worker_processes 1;
pid $ROOT/run/nginx.pid;
error_log $ROOT/logs/nginx_error.log;
events { worker_connections 256; }
http {
  access_log $ROOT/logs/nginx_access.log;
  client_body_temp_path $ROOT/run/tmp/body;
  proxy_temp_path $ROOT/run/tmp/proxy;
  fastcgi_temp_path $ROOT/run/tmp/fcgi;
  uwsgi_temp_path $ROOT/run/tmp/uwsgi;
  scgi_temp_path $ROOT/run/tmp/scgi;
  include $ROOT/conf/upstream.conf;
  server {
    listen $ROUTER_PORT;
    location / {
      proxy_pass http://forgepulse_active;
      proxy_next_upstream error timeout http_502 http_503;
      proxy_connect_timeout 2s;
    }
  }
}
CONF
"$ROOT/scripts/stop.sh" >/dev/null 2>&1
say "Starting BLUE (v1) on :8081"
start_env blue v1
wait_healthy blue 10 || { bad "blue did not start, see logs/blue.log"; exit 1; }
echo "upstream forgepulse_active { server 127.0.0.1:8081; }" > "$ROOT/conf/upstream.conf"
echo blue > "$ROOT/state/active"; rm -f "$ROOT/state/previous" "$ROOT/state/version_green"
say "Starting router on :$ROUTER_PORT"
nginx -c "$ROOT/conf/nginx.conf" -p "$ROOT" 2>/dev/null
sleep 0.5
ok "Live: http://localhost:$ROUTER_PORT  (served by $(router_env))"
