# winbit32MCP

The agent-facing [Winbit32](https://winbit32.com), live at
**`https://mcp.winbit32.com/mcp`** (Streamable HTTP). Public, MIT.

```json
{ "mcpServers": { "winbit32": { "url": "https://mcp.winbit32.com/mcp" } } }
```

This repo is a **thin deployment** of
[`payments-gateway`](https://github.com/Rotwang9000/payments-gateway) —
the generic MCP + REST payments engine. Everything here is config,
branding and ops: the `bin/` wrappers re-export the upstream entry
points, `.env` sets `GATEWAY_TOOL_PREFIX=winbit32` (plus backends), and
[DEPLOY.md](DEPLOY.md) records the production layout (systemd + nginx +
certbot). Engine code, features and tests live upstream; bump the pinned
`payments-gateway` commit in `package.json` to take new releases.

## What agents get

40 `winbit32_*` tools today: Penny Oracle single-fact queries (`q`),
Zcash/Monero view-key scan jobs, UTXOs + broadcast, private balance
watches with webhooks and XMR/ZEC/USDC top-ups, x402 paywall metadata,
and the offline phrase/Shamir utilities. NFPT marketplace reads
(`nfpt_list_collections` / `nfpt_listings`) land when the
payments-gateway pin is at **v0.19.0+**. The `make_payment` family
(outbound co-signed ZEC with `cosignUrl` deep links) — and the matching
`nfpt_buy` / `nfpt_buy_status` — appear once the operator stages a FROST
`.wult` share: the gateway share alone can never spend; a human approves
every payment in their cosigner.

## Key custody

Split-key recommended (one FROST share, human co-signs via
[winbit32.com/cosign](https://winbit32.com/cosign)); directly supplied
phrases/keys remain supported for operators who accept holding key
material. Accepting payments is view-key-only.

## Running locally

```bash
npm ci
npm run start:mcp    # MCP server (default loopback :8821)
npm run start:rest   # REST + x402 paywall (optional)
npm test             # deployment smoke: 21 winbit32_* tools register
```

## Licence

MIT — see [LICENSE](LICENSE).
