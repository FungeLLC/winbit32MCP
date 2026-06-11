# Deploying winbit32MCP

Target shape: `mcp.winbit32.com` → nginx → the MCP server on a loopback
port. REST/x402 is a second unit on its own port (only if you want the
paid REST surface). Node >= 20.

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
User=winbit32
WorkingDirectory=/opt/winbit32mcp
EnvironmentFile=/etc/winbit32/mcp.env
ExecStart=/usr/bin/node bin/mcp.mjs
Restart=on-failure
RestartSec=5
# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/winbit32mcp
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

If you enable private watches (`PRIVATE_WATCH_DB`) point it somewhere
inside a `ReadWritePaths` entry. Add equivalent units for `bin/rest.mjs`
and the pollers if those capabilities are configured.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now winbit32-mcp
curl -s http://127.0.0.1:8792/health   # → ok
```

## nginx

```nginx
server {
	server_name mcp.winbit32.com;
	listen 443 ssl http2;
	# ssl_certificate … (certbot)

	location / {
		proxy_pass http://127.0.0.1:8792;
		proxy_http_version 1.1;
		# Streamable HTTP / SSE friendliness:
		proxy_buffering off;
		proxy_cache off;
		proxy_read_timeout 300s;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-Proto $scheme;
		proxy_set_header X-Real-IP $remote_addr;
	}
}
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
