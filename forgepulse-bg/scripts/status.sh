#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
for c in blue green; do
  h=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(port_of $c)/health" 2>/dev/null)
  m=""; [ "$c" = "$(active)" ] && m="  <-- LIVE"
  printf '%-6s port %s  version %-6s health %s%s\n' "$c" "$(port_of $c)" "$(version_of $c)" "${h:-down}" "$m"
done
echo "router :$ROUTER_PORT -> $(router_env)"
