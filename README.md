# winbit32MCP

The agent-facing [Winbit32](https://winbit32.com): an MCP + REST server that
lets AI agents **accept** and **make** private payments (Zcash, Monero, USDC
via x402) without ever holding a spending key. Public, MIT-licensed.

## Key custody

The **recommended** mode is split-key: the agent process holds at most
**one FROST share of a t-of-n key** (a WINBIT32 `.wult` file). Any tool
that moves funds returns a `WB32COSIGN` QR / deep-link; a human approves it
in a cosigner — the fast-boot
[winbit32.com/cosign](https://winbit32.com/cosign) app, cosign.exe in the
desktop, or (roadmap) the Chrome wallet extension. The human's share
signature IS the approval; in this mode there is nothing the agent can sign
alone.

It is the recommended mode, not the only one: every signing tool also
accepts directly supplied phrases or keys (operator config or explicit tool
input) for operators who accept holding key material. Docs and defaults
steer towards split-key; functionality is never gated on it.

For *accepting* payments the server is view-key-only: it can see funds
arrive but can never move them.

## Tool families

| Family | Tools | Keys needed |
| --- | --- | --- |
| accept | `request_payment`, view-key watches + webhooks, x402 paywall | view keys only |
| make | `make_payment`, `make_payment_status`, `make_payment_info` | one FROST share + human cosign (recommended), or a directly supplied phrase/key |
| wallet | balances, receive addresses, scan jobs | view keys only |
| utility | address generation/validation, phrase tools, Shamir split/unsplit | none (local, offline) |
| info | single-fact chain queries (height/fee/mempool) | none |

The end-state tool surface tracks the Winbit32 desktop itself — anything
the site can do, MCP should be able to do ("our PowerShell moment") — minus
the windows that exist for human play (the Minesweeper disguise) or niche
position management (THORChain/Maya liquidity pools).

## Lineage

This repo is the public home of the payments-gateway engine built for
[seneschal.space](https://seneschal.space), assembled from already-public
packages so there is one source of truth:

- [`viewkey-watch`](https://github.com/Rotwang9000/viewkey-watch) —
  Monero/Zcash view-key payment-watch engine;
- [`x402-server-kit`](https://github.com/Rotwang9000/x402-server-kit) —
  generic Fastify x402 paywall;
- `@winbit32/wallet-kit` — scanner clients + the WB32COSIGN FROST/Orchard
  cosign client (headless initiator pipeline) extracted from Winbit32.

Brand is config, not code: the same engine runs seneschal.space and the
winbit32 deployment.

## What works today

| Capability | Status |
| --- | --- |
| Accept USDC per-call via x402 (HTTP 402 + `transferWithAuthorization` on Base) | ✅ |
| View-key payment **webhooks** for Monero/Zcash ("ping me when funds land") | ✅ |
| Credit-metered watches with USDC top-ups | ✅ |
| One-off historical view-key scans (spendable/spent notes) | ✅ |
| Free view-key derivation from a phrase (rate-limited) | ✅ |
| Fund a watch by paying in **XMR/ZEC** to the operator's view-only wallet | ✅ |
| Single-fact ("Penny Oracle") privacy-chain queries (height/fee/mempool) | ✅ |
| **Make** outbound **ZEC** payments via 2-of-2 FROST co-signing (`make_payment` MCP tools) | ✅ |
| Wallet view-key tools (`zec_scan_*`, `zec_utxos`, `zec_broadcast`, `xmr_scan_*`) via `@winbit32/wallet-kit` | ✅ |
| Direct phrase/key signing mode; outbound USDC / XMR; utility (SecTools) tools | 🛣️ roadmap |

## Running it

```bash
npm ci
node bin/mcp.mjs     # MCP server for agents (Streamable HTTP)
node bin/rest.mjs    # REST + x402 paywall
node bin/private-watch-poller.mjs    # watch poller (cron-style)
node bin/crypto-recv-poller.mjs      # XMR/ZEC top-up poller
```

Or embed it: a host app mounts the engine onto its own Fastify + MCP
servers (`registerGatewayRoutes` / `registerGatewayMcpTools`) and injects a
config object — this is exactly how seneschal.space runs it, with its own
branding.

## Configuration

Environment-driven via `src/config.js` (`buildConfig(env)`). Key groups:

- **Server**: `GATEWAY_REST_PORT`, `GATEWAY_MCP_PORT`, `GATEWAY_REST_HOST`
- **Brand**: `GATEWAY_SERVICE_NAME`, `GATEWAY_WEBHOOK_SIGNATURE_HEADER`
- **x402**: `X402_RECIPIENT_ADDRESS`, `X402_NETWORK`, `X402_FACILITATOR_URL`,
  `X402_CDP_API_KEY_ID` / `X402_CDP_API_KEY_SECRET`, `X402_*_PRICE`
- **NFPT scanner**: `NFPT_BASE_URL`, `NFPT_API_KEY`
- **Private watch**: `PRIVATE_WATCH_DB`, `PRIVATE_WATCH_ENCRYPTION_KEY`
- **Privacy RPC**: `MONERO_RPC_URL`, `ZCASH_RPC_URL`
- **XMR/ZEC top-ups**: `XMR_RECV_ADDRESS` + `XMR_RECV_VIEW_KEY`,
  `ZEC_RECV_ADDRESS` + `ZEC_RECV_UFVK`, `CRYPTO_TOPUP_*`
- **Make payments (ZEC co-sign)**: `MAKE_PAYMENT_WULT_PATH` (+ optional
  `MAKE_PAYMENT_WULT_PASSWORD`), `MAKE_PAYMENT_WASM_DIR` (orchard-frost WASM
  artefacts), `MAKE_PAYMENT_RELAY_URL` (default `https://cosign.winbit32.com`),
  `MAKE_PAYMENT_PCZT_API_BASE`, `MAKE_PAYMENT_SCANNER_BASE`,
  `MAKE_PAYMENT_BIRTHDAY_HEIGHT`, and the safety rails
  `MAKE_PAYMENT_MAX_ZEC` / `MAKE_PAYMENT_MAX_PENDING`.

A capability stays `503 *_not_configured` (or its tools are simply not
registered) until its keys/addresses are set — the `make_payment` tools
only exist when `MAKE_PAYMENT_WULT_PATH` is configured.

## Status

Engine extracted and live in this repo: 6 test suites / 89 tests green
against the published `@winbit32/wallet-kit`. The seneschal.space embedded
deployment still runs its own copy pending consolidation onto this repo.
Plan and sequencing: the original repo's
[ROADMAP.md](https://github.com/FungeLLC/WINBIT32/blob/master/ROADMAP.md).

## Licence

MIT — see [LICENSE](LICENSE).
