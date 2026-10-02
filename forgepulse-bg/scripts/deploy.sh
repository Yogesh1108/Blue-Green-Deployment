#!/usr/bin/env bash
# Usage: deploy.sh <version> [--bad]     (--bad simulates a broken release)
source "$(dirname "$0")/lib.sh"
NEW="${1:?usage: deploy.sh <version> [--bad]}"; BAD=0; [ "${2:-}" = "--bad" ] && BAD=1
ACT=$(active); TARGET=$(idle)
[ "$ACT" = none ] && { bad "run setup.sh first"; exit 1; }
say "Active: $ACT ($(version_of "$ACT"))   Idle target: $TARGET"
say "1/4 Deploying $NEW to idle env $TARGET (no user traffic touches it)"
start_env "$TARGET" "$NEW" "$BAD"
wait_healthy "$TARGET" 10 || { bad "$TARGET never became healthy. Release blocked; users still on $ACT ($(version_of "$ACT"))."; stop_env "$TARGET"; exit 1; }
say "2/4 Validating $TARGET before go-live"
if ! smoke_test "$TARGET" "$NEW"; then
  bad "Validation FAILED. Release blocked; users are still on $ACT ($(version_of "$ACT"))."
  stop_env "$TARGET"; exit 1
fi
say "3/4 Switching router $ACT -> $TARGET"
point_router_to "$TARGET" || exit 1
sleep 0.5
say "4/4 Post-switch verification through the router"
if [ "$(router_env)" = "$TARGET" ]; then
  ok "Traffic now on $TARGET ($NEW). $ACT ($(version_of "$ACT")) kept warm for instant rollback: ./scripts/rollback.sh"
else
  bad "Router not serving $TARGET, rolling back automatically"; point_router_to "$ACT"; exit 1
fi
