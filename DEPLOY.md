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
