#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
[ -f "$ROOT/run/nginx.pid" ] && nginx -s stop -c "$ROOT/conf/nginx.conf" -p "$ROOT" 2>/dev/null
stop_env blue; stop_env green; echo stopped
