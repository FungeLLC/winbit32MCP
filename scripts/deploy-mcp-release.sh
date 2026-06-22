#!/usr/bin/env bash
set -euo pipefail

# Parameterised winbit32MCP deploy helper used by the Jenkins pipeline
# (winbit32MCP-master). It converges a TARGET_ROOT git checkout to the pushed
# branch tip and reinstalls from the lock, so the live box always runs exactly
# what is on origin/master — "a pull to master puts it on the live site".
#
# Two shapes, selected by DEPLOY_ENV:
#   staging  ->  a deploy-user-owned tree (default ~/tools/staging/winbit32mcp).
#               Fresh `npm ci` + smoke, NO service restart. Proves the release
#               builds cleanly from a pristine checkout before we touch live.
#   live     ->  /opt/winbit32mcp, owned by the service user (winbit32mcp). The
#               git + npm steps run AS that user (so node_modules ownership
#               stays correct), then winbit32-rest + winbit32-mcp are restarted.
#
# Node is pinned to the system node (v23, /usr/local/bin) to match the running
# services — a better-sqlite3 .node built for the wrong ABI will not dlopen.
#
# Privileged steps (run-as-service-user, systemctl restart) use passwordless
# sudo; the Jenkins controller runs as a user with NOPASSWD sudo on this host.

TARGET_ROOT="${TARGET_ROOT:-/opt/winbit32mcp}"
DEPLOY_ENV="${DEPLOY_ENV:-live}"
RESTART_SERVICES="${RESTART_SERVICES:-auto}"
# Empty SERVICE_USER => run git/npm as the invoking user (staging). For live the
# pipeline passes winbit32mcp so the install is owned by the service account.
SERVICE_USER="${SERVICE_USER:-}"
# Public HTTPS clone — no SSH key/credential needed (matches the origin already
# configured on the live /opt checkout). Override REPO_URL for a private fork.
REPO_URL="${REPO_URL:-https://github.com/FungeLLC/winbit32MCP.git}"
GIT_BRANCH="${GIT_BRANCH_DEPLOY:-master}"
# The exact commit to deploy. Jenkins passes the SHA it built + tested
# (GIT_COMMIT); both staging and live then run precisely that revision. Default
# is the pushed branch tip ("a pull to master puts it on the live site").
DEPLOY_REF="${DEPLOY_REF:-origin/$GIT_BRANCH}"
NODE_BIN_DIR="${NODE_BIN_DIR:-/usr/local/bin}"
REST_PORT="${REST_PORT:-8820}"
MCP_PORT="${MCP_PORT:-8821}"
SERVICES=("winbit32-rest.service" "winbit32-mcp.service")

section() { echo ""; echo "== $1 =="; }

# Resolve restart default from the target (only the live /opt tree restarts).
if [ "$RESTART_SERVICES" = "auto" ]; then
	case "$TARGET_ROOT" in
		/opt/winbit32mcp) RESTART_SERVICES="true" ;;
		*) RESTART_SERVICES="false" ;;
	esac
fi

# HOME for the service user keeps npm's cache beside the install (how /opt was
# originally provisioned: /opt/winbit32mcp/.npm).
SVC_HOME="${SVC_HOME:-$TARGET_ROOT}"

# Run a shell snippet either directly or as $SERVICE_USER (via sudo), always
# with the pinned node on PATH.
run_svc() {
	local snippet="$1"
	if [ -n "$SERVICE_USER" ] && [ "$SERVICE_USER" != "$(id -un)" ]; then
		sudo -u "$SERVICE_USER" env HOME="$SVC_HOME" PATH="$NODE_BIN_DIR:/usr/bin:/bin" bash -c "$snippet"
	else
		env PATH="$NODE_BIN_DIR:$PATH" bash -c "$snippet"
	fi
}

section "Deploy winbit32MCP ($DEPLOY_ENV)"
echo "Target:  $TARGET_ROOT"
echo "Branch:  origin/$GIT_BRANCH"
echo "Ref:     $DEPLOY_REF"
echo "RunAs:   ${SERVICE_USER:-$(id -un)}"
echo "Restart: $RESTART_SERVICES"
echo "Node:    $("$NODE_BIN_DIR/node" --version 2>/dev/null || echo '?')"

section "Ensure checkout"
if [ ! -d "$TARGET_ROOT/.git" ]; then
	echo "No git checkout at $TARGET_ROOT — cloning $REPO_URL"
	parent="$(dirname "$TARGET_ROOT")"
	run_svc "mkdir -p '$parent' && git clone --branch '$GIT_BRANCH' '$REPO_URL' '$TARGET_ROOT'"
fi

section "Sync to $DEPLOY_REF + install"
# Fetch the branch, then HARD-FAIL if the requested commit is not present on
# origin: Jenkins polls the LOCAL working repo, so a master commit that has not
# been pushed would otherwise let us deploy stale code. Refusing here enforces
# the "everything via commits and pushes" rule — push to origin/$GIT_BRANCH and
# re-run. reset --hard then makes the tree identical to that exact revision
# (discarding any drift on the box). npm ci installs strictly from the lock (the
# typescript override keeps it ci-consistent); node_modules ownership follows
# SERVICE_USER so the service account can read its own native addons.
run_svc "cd '$TARGET_ROOT' && git fetch origin '$GIT_BRANCH'"
if ! run_svc "cd '$TARGET_ROOT' && git cat-file -e '${DEPLOY_REF}^{commit}' 2>/dev/null"; then
	echo "ERROR: commit '$DEPLOY_REF' is not on origin after fetch." >&2
	echo "       The built commit has not been pushed to origin/$GIT_BRANCH." >&2
	echo "       Push it and re-run — live must equal what is on origin." >&2
	exit 1
fi
run_svc "cd '$TARGET_ROOT' && git reset --hard '$DEPLOY_REF' && npm ci --no-audit --no-fund"

DEPLOYED_SHA="$(run_svc "cd '$TARGET_ROOT' && git rev-parse --short HEAD")"
echo "Deployed commit: $DEPLOYED_SHA"

section "Smoke (build integrity)"
# better-sqlite3 must dlopen under the pinned node, the pinned payments-gateway
# must carry the hosted-AI sources, and the lock must reference a real commit.
run_svc "node -e \"require('$TARGET_ROOT/node_modules/better-sqlite3'); console.log('better-sqlite3 OK', process.version)\""
test -f "$TARGET_ROOT/node_modules/payments-gateway/src/ai-credits.js" \
	|| { echo "ERROR: payments-gateway missing ai-credits.js — bad pin?" >&2; exit 1; }
test -f "$TARGET_ROOT/node_modules/payments-gateway/src/rest-app.js"
test -f "$TARGET_ROOT/bin/rest.mjs"
test -f "$TARGET_ROOT/bin/mcp.mjs"
grep -qE "payments-gateway.git#[0-9a-f]{40}" "$TARGET_ROOT/package-lock.json" \
	|| { echo "ERROR: lock has no resolved payments-gateway commit" >&2; exit 1; }
echo "Smoke OK"

if [ "$RESTART_SERVICES" = "true" ]; then
	if [ ! -f /etc/winbit32/mcp.env ]; then
		echo "ERROR: /etc/winbit32/mcp.env missing — refusing to restart services." >&2
		exit 1
	fi
	section "Restart live services"
	for svc in "${SERVICES[@]}"; do
		sudo /usr/bin/systemctl restart "$svc"
	done
	sleep 2
	for svc in "${SERVICES[@]}"; do
		printf '%-22s %s\n' "$svc" "$(sudo /usr/bin/systemctl is-active "$svc")"
	done

	section "Health check (loopback)"
	# REST surface (8820): /v1/ai is the hosted-AI metadata (free, no paywall).
	AI_ENABLED="$(curl -fsS "http://127.0.0.1:$REST_PORT/v1/ai" 2>/dev/null | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).enabled)}catch{console.log('parse_error')}})" || echo 'unreachable')"
	echo "REST /v1/ai enabled=$AI_ENABLED"
	# MCP transport (8821): a bare GET returns 406 (needs the MCP Accept header)
	# but a live socket proves the unit is up; connection refused => fail.
	MCP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$MCP_PORT/" || echo '000')"
	echo "MCP loopback http=$MCP_CODE"
	if [ "$MCP_CODE" = "000" ]; then
		echo "ERROR: MCP transport not answering on $MCP_PORT" >&2
		exit 1
	fi
else
	echo "Service restart skipped for $DEPLOY_ENV"
fi

echo ""
echo "winbit32MCP deploy completed: $DEPLOY_ENV -> $TARGET_ROOT @ $DEPLOYED_SHA"
