# winbit32MCP

The agent-facing [Winbit32](https://winbit32.com): an MCP + REST server that
lets AI agents **accept** and **make** private payments (Zcash, Monero, USDC
via x402) without ever holding a spending key. Public, MIT-licensed.

## The key-custody invariant

The agent process holds at most **one FROST share of a t-of-n key** (a
WINBIT32 `.wult` file). Any tool that moves funds returns a `WB32COSIGN` QR
/ deep-link; a human approves it in a cosigner — the fast-boot
[winbit32.com/cosign](https://winbit32.com/cosign) app, cosign.exe in the
desktop, or (roadmap) the Chrome wallet extension. The human's share
signature IS the approval. There is nothing the agent can sign alone.

For *accepting* payments the server is view-key-only: it can see funds
arrive but can never move them.

## Tool families

| Family | Tools | Keys needed |
| --- | --- | --- |
| accept | `request_payment`, view-key watches + webhooks, x402 paywall | view keys only |
| make | `make_payment`, `make_payment_status`, `make_payment_info` | one FROST share + human cosign |
| wallet | balances, receive addresses, scan jobs | view keys only |
| info | single-fact chain queries (height/fee/mempool) | none |

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

## Status

Scaffolding — code lands here as it is extracted from the private host
repo. The plan and sequencing live in the original repo's
[ROADMAP.md](https://github.com/FungeLLC/WINBIT32/blob/master/ROADMAP.md).

## Licence

MIT — see [LICENSE](LICENSE).
