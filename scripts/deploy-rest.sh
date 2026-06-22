#!/usr/bin/env bash
#
# Deploy / refresh the winbit32 REST + x402 surface (incl. the hosted-AI proxy)
# alongside the existing MCP unit. The REST service shares the proven
# /opt/winbit32mcp install (and its node-23-built better-sqlite3), so we never
# rebuild native modules or duplicate node_modules — we just overlay the
# payments-gateway source, install a second systemd unit, and (re)start it.
#
# Usage:
#   PG_SRC=/path/to/payments-gateway sudo -E bash scripts/deploy-rest.sh
#   # PG_SRC optional — omit to (re)start with whatever is already installed.
#
# Env overrides: TARGET (/opt/winbit32mcp), REST_PORT (8820).
set -euo pipefail

TARGET="${TARGET:-/opt/winbit32mcp}"
REST_PORT="${REST_PORT:-8820}"
PG_SRC="${PG_SRC:-}"
SERVICE="winbit32-rest"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVC_USER="winbit32mcp"

echo "== Deploy winbit32 REST (target: $TARGET, port: $REST_PORT) =="

# 1. Optionally overlay an updated payments-gateway source tree (pure JS only —
#    no deps change, so the existing node_modules stays valid).
if [[ -n "$PG_SRC" ]]; then
	[[ -d "$PG_SRC/src" ]] || { echo "PG_SRC=$PG_SRC has no src/ — aborting"; exit 1; }
	echo "-- overlaying payments-gateway source from $PG_SRC"
	rsync -a --delete --exclude='__pycache__' "$PG_SRC/src/" "$TARGET/node_modules/payments-gateway/src/"
	rsync -a "$PG_SRC/bin/" "$TARGET/node_modules/payments-gateway/bin/"
	cp "$PG_SRC/package.json" "$TARGET/node_modules/payments-gateway/package.json"
	chown -R "$SVC_USER:$SVC_USER" "$TARGET/node_modules/payments-gateway"
fi

# 2. Install / refresh the systemd unit.
echo "-- installing $SERVICE.service"
install -m 0644 "$HERE/deploy/$SERVICE.service" "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1 || true
systemctl restart "$SERVICE"

# 3. Smoke: the REST health endpoint should answer locally.
echo "-- smoke test"
sleep 1
if curl -fsS "http://127.0.0.1:$REST_PORT/v1/health" >/tmp/winbit32-rest-health.json 2>/dev/null; then
	echo "REST health: $(cat /tmp/winbit32-rest-health.json)"
else
	echo "WARNING: REST health check failed — inspect: journalctl -u $SERVICE -n 50 --no-pager"
	exit 1
fi

cat <<EONOTE

Done. Remaining manual steps the first time only:
  * Add the /v1/ai nginx locations from deploy/nginx-mcp-ai.location.conf to
    /etc/nginx/sites-available/mcp.winbit32.com.conf, then: nginx -t && reload.
  * Set AI_UPSTREAM_API_KEY (+ X402_RECIPIENT_ADDRESS) in /etc/winbit32/mcp.env
    and restart $SERVICE — until then /v1/ai answers 503 by design.
EONOTE
