#!/usr/bin/env bash
# Hits the router ~5x/sec and prints which env answered. Run during a deploy: no FAIL lines = zero downtime.
source "$(dirname "$0")/lib.sh"; ok_n=0; fail_n=0
trap 'echo; echo "ok=$ok_n failed=$fail_n"; exit' INT
while true; do
  out=$(curl -s -m 2 -o /dev/null -D - "http://127.0.0.1:$ROUTER_PORT/api/info" | tr -d '\r')
  code=$(echo "$out" | head -1 | awk '{print $2}'); env=$(echo "$out" | awk -F': ' 'tolower($1)=="x-env"{print $2}'); ver=$(echo "$out" | awk -F': ' 'tolower($1)=="x-version"{print $2}')
  if [ "$code" = 200 ]; then ok_n=$((ok_n+1)); printf '%s  200  %-5s %s\n' "$(date +%T)" "$env" "$ver"
  else fail_n=$((fail_n+1)); printf '%s  \033[1;31mFAIL (%s)\033[0m\n' "$(date +%T)" "${code:-none}"; fi
  sleep 0.2
done
