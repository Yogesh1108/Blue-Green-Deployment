#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
PREV=$(previous); CUR=$(active)
[ "$PREV" = none ] && { bad "nothing to roll back to"; exit 1; }
wait_healthy "$PREV" 3 || { bad "$PREV is not healthy, cannot roll back"; exit 1; }
say "Rolling back $CUR ($(version_of "$CUR")) -> $PREV ($(version_of "$PREV"))"
point_router_to "$PREV" && sleep 0.5 && ok "Users now on $PREV ($(version_of "$PREV")), router confirms: $(router_env)"
