# Deploying winbit32MCP

Target shape: `mcp.winbit32.com` → nginx → the MCP server on a loopback
port. REST/x402 is a second unit on its own port (only if you want the
paid REST surface). Node >= 20.

> **Deployed (Jun 2026):** live at `https://mcp.winbit32.com/mcp` on `fin`
> following exactly this layout — `/opt/winbit32mcp` (service user
> `winbit32mcp`), env at `/etc/winbit32/mcp.env`, MCP on loopback `8821`
> (the config default), nginx vhost from this template + certbot. 21
> `winbit32_*` tools verified over public Streamable HTTP, including a live
> `q zec/height` against the local Zebra node.

## Install

```bash
sudo mkdir -p /opt/winbit32mcp && sudo chown "$USER" /opt/winbit32mcp
git clone https://github.com/FungeLLC/winbit32MCP.git /opt/winbit32mcp
cd /opt/winbit32mcp && npm ci --omit=dev
cp .env.example /etc/winbit32/mcp.env   # then edit: set at least GATEWAY_TOOL_PREFIX=winbit32
```

Secrets (`.wult` share, encryption keys) belong in `/etc/winbit32/` with
`chmod 600`, never in the repo directory.

## systemd

`/etc/systemd/system/winbit32-mcp.service`:

```ini
[Unit]
Description=winbit32 MCP server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=winbit32mcp
Group=winbit32mcp
WorkingDirectory=/opt/winbit32mcp
EnvironmentFile=/etc/winbit32/mcp.env
# Use the node >= 20 binary explicitly; distro /usr/bin/node may be ancient.
ExecStart=/usr/local/bin/node bin/mcp.mjs
Restart=on-failure
RestartSec=5
# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/winbit32mcp
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Point `PRIVATE_WATCH_DB` somewhere inside a `ReadWritePaths` entry
(`/var/lib/winbit32mcp/private-watches.db` above). Add equivalent units
for `bin/rest.mjs` and the pollers if those capabilities are configured.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now winbit32-mcp
curl -s http://127.0.0.1:8821/health   # → ok  (GATEWAY_MCP_PORT, default 8821)
```

## nginx

Start with an HTTP-only vhost, symlink into `sites-enabled`, `nginx -t`,
reload, then let certbot add TLS + the redirect:

```nginx
server {
	server_name mcp.winbit32.com;
	listen 80;

	location / {
		proxy_pass http://127.0.0.1:8821;
		proxy_http_version 1.1;
		# Streamable HTTP / SSE friendliness:
		proxy_buffering off;
		proxy_cache off;
		proxy_request_buffering off;
		proxy_read_timeout 300s;
		proxy_send_timeout 300s;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-Proto $scheme;
		proxy_set_header X-Real-IP $remote_addr;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	}
}
```

```bash
sudo ln -sf /etc/nginx/sites-available/mcp.winbit32.com.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d mcp.winbit32.com -n --agree-tos --keep-until-expiring
```

## Agent configuration

Once live, agents connect with:

```json
{
	"mcpServers": {
		"winbit32": {
			"url": "https://mcp.winbit32.com/mcp"
		}
	}
}
```

Tool names are `winbit32_*` (set by `GATEWAY_TOOL_PREFIX`). Free tools
work immediately; paid surfaces settle via x402 at the REST endpoint; the
`winbit32_make_payment` family appears only when the operator configures a
`.wult` FROST share (see `.env.example`).

## Smoke test

```bash
curl -s -X POST https://mcp.winbit32.com/mcp \
	-H 'content-type: application/json' \
	-H 'accept: application/json, text/event-stream' \
	-H 'mcp-protocol-version: 2025-03-26' \
	-d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Expect 21+ tools. `…_phrase_complete` with eleven `abandon`s should return
128 candidates including `about`.

## REST + x402 surface (incl. hosted AI)

The MCP unit above is free + agent-facing. The **paid** surface (x402 `q`
facts, private-watch top-ups, and the **hosted-AI credits + OpenAI-compatible
proxy**) lives in `bin/rest.mjs` on a second loopback port (`8820`). It shares
the same `/opt/winbit32mcp` install — including the node-built `better-sqlite3`
— so there is nothing extra to compile.

```bash
# Install/refresh the REST unit (overlay an updated engine if you have one):
PG_SRC=/home/rotwang/wbdev/payments-gateway sudo -E bash scripts/deploy-rest.sh
```

That installs `deploy/winbit32-rest.service`, enables it, and smoke-tests
`http://127.0.0.1:8820/v1/health`. Then expose it on the existing TLS host by
adding the location blocks from `deploy/nginx-mcp-ai.location.conf` to
`mcp.winbit32.com.conf` (above the catch-all `location /` that points at the
MCP port):

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s https://mcp.winbit32.com/v1/ai | jq .   # { enabled, base_url, … }
```

### Hosted AI — going live

The hosted-AI routes only **serve** once two pieces of config are present in
`/etc/winbit32/mcp.env` (until then they answer `503` by design — never a mock):

| Key | What it is |
|-----|------------|
| `X402_RECIPIENT_ADDRESS` | the Base (USDC) wallet that receives credit-bundle payments |
| `AI_UPSTREAM_API_KEY`     | the operator's upstream LLM key (never sent to the browser) |
| `AI_UPSTREAM_BASE_URL`    | OpenAI-compatible upstream (default `https://openrouter.ai/api/v1`) |
| `AI_DEFAULT_MODEL`        | model used when the client asks for `auto` |

```bash
sudoedit /etc/winbit32/mcp.env      # set the four keys above (+ tune AI_* pricing)
sudo systemctl restart winbit32-rest
# Buyers: one x402 USDC payment at POST /v1/ai/credits → { token, baseUrl,
# credits }; spend the token at POST /v1/ai/chat/completions.
```

The flow is **non-custodial on the buyer's side**: WINBIT32's Messenger pays the
bundle from the user's own vault via the x402 vault payer, so we hold no card
and no provider key for them. See `.env.example` for the full `AI_*` knob list.

## Zcash shield-amount index (popular "blend in" amounts)

The `zec_amount_advice` / `zec_split_plan` / `zec_popular_amounts` tools (and the
matching free `GET /v1/zec/amount-advice` + `/v1/zec/split-plan` +
`/v1/zec/popular-amounts` routes) always answer: with no index they fall back to
a static blend-in set. To turn the *"N others shielded this exact amount"*
counts on, point the poller at the local Zebra
node — it reads blocks with `getblock(height, 2)` and tallies shield/deshield
boundary crossings into a SQLite histogram. **No view keys, no wallets** — only
public per-pool `valueBalanceZat` totals.

Set the `ZEC_SHIELD_INDEX_*` keys in `/etc/winbit32/mcp.env` (see
`.env.example`), making sure `ZEC_SHIELD_INDEX_DB` sits inside a
`ReadWritePaths` entry, then add a poller **timer** (cron-style; the binary
scans one bounded batch per run and exits):

`/etc/systemd/system/winbit32-zec-shield-index.service`:

```ini
[Unit]
Description=winbit32 Zcash shield-amount index poller
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=winbit32mcp
Group=winbit32mcp
WorkingDirectory=/opt/winbit32mcp
EnvironmentFile=/etc/winbit32/mcp.env
ExecStart=/usr/local/bin/node bin/zec-shield-index-poller.mjs
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/winbit32mcp
PrivateTmp=true
```

`/etc/systemd/system/winbit32-zec-shield-index.timer`:

```ini
[Unit]
Description=Run the winbit32 Zcash shield-amount index poller periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now winbit32-zec-shield-index.timer
# One-shot catch-up / smoke test (logs JSON: scanned range, tallied, cursor):
sudo -u winbit32mcp --preserve-env \
	/usr/local/bin/node /opt/winbit32mcp/bin/zec-shield-index-poller.mjs
curl -s https://mcp.winbit32.com/v1/zec/popular-amounts?side=shield | jq .
```

The first run from a low `FROM_HEIGHT` can take a while; each invocation only
advances by `ZEC_SHIELD_INDEX_MAX_BLOCKS_PER_TICK` blocks and records its
cursor, so the timer naturally back-fills then tracks the tip.

### Zcash "Bus Station" — non-custodial mixing coordination (opt-in)

A rendezvous so many users leave the Zcash pool with the **same** blend-in
amount, route and short window — their swaps then look identical on-chain (one
anonymity set). It is **non-custodial**: the server holds no funds or keys and
stores **no** destinations or txids — only `(route, amount, seat count,
departure window)`. Each rider broadcasts their own swap from their own wallet.

Unlike the shield index there is **no poller and no read-only fallback** — the
tools (`zec_bus_*`) and routes (`/v1/zec/bus*`) stay hidden until you enable it
and point it at a writable DB:

```ini
# /etc/winbit32/mcp.env
ZEC_BUS_ENABLED=1
ZEC_BUS_DB=/var/lib/winbit32mcp/zec-bus.db   # inside ReadWritePaths
#ZEC_BUS_FILL_TTL_MS=86400000                # unfilled buses expire after 24h
#ZEC_BUS_DEPART_WINDOW_MS=1200000            # 20-min broadcast window once ready
```

```bash
# Verify (returns the open buses list once enabled):
curl -s https://mcp.winbit32.com/v1/zec/bus | jq .
```
