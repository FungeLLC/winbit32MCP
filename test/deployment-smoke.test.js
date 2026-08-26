// Deployment smoke test: this repo is a thin wrapper, so the only thing
// worth pinning here is that the upstream engine installs, the winbit32
// branding applies, and the expected winbit32_* tool surface registers.
//
// The "from env alone" surface is: the free q/paywall oracle, the
// private-watch + zec/xmr scan + broadcast wallet kit, the phrase + shamir
// seed helpers, and the always-on public notice board (free reads; posting
// needs a writable NOTICE_BOARD_DB). Three families stay HIDDEN until an
// operator explicitly opts in — asserted below as a gating guard so a future
// regression can't silently expose them:
//   - make_payment_*  — needs an operator .wult co-sign share (custody call)
//   - paid_unlock_*   — needs PAID_UNLOCK_ENABLED ("paid private file" opt-in)
//   - zec_bus_*       — needs ZEC_BUS_ENABLED (non-custodial mixing rendezvous;
//                       requires a writable DB, no read-only fallback)

import { describe, it, expect } from '@jest/globals';
import { buildConfig, buildGatewayMcpServer } from 'payments-gateway';

const WINBIT32_ENV = {
	GATEWAY_SERVICE_NAME: 'winbit32',
	GATEWAY_TOOL_PREFIX: 'winbit32',
	MONERO_RPC_URL: 'http://127.0.0.1:18081',
	ZCASH_RPC_URL: 'http://127.0.0.1:8232',
	NFPT_BASE_URL: 'http://127.0.0.1:3555',
	NFPT_API_KEY: 'test-key'
};

// Expected always-on surface size. Bump deliberately (with a representative
// below) whenever the engine adds a family — it's a canary, not a guess.
// 29 = 26 + the free Zcash amount-privacy advisor (zec_amount_advice +
// zec_popular_amounts + zec_split_plan), which register by default and fall back
// to a curated blend-in list until the operator runs the shield-amount index
// poller.
// 37 = 29 + the ziving campaign-page family (info, get_page, featured,
// create_page, feature, topup, cancel, recover), always-on since ziving.org
// launched on this gateway. The old 36 was an artefact of a stale
// package-lock that shipped a pre-recover engine while the pin said newer.
// 38 = 37 + entropy_selftest, which runs the RNG health check guarding
// phrase_generate. Not a family — one tool — but an agent that mints a
// phrase should be able to ask whether the generator was working, which
// is exactly what nine Coldcard Mk3 releases had no way to answer.
// 40 = 38 + NFPT marketplace reads (nfpt_list_collections + nfpt_listings).
// Buy (nfpt_buy / nfpt_buy_status) stays gated on MAKE_PAYMENT_WULT_PATH,
// same as make_payment itself.
const EXPECTED_TOOL_COUNT = 40;

describe('winbit32 deployment of payments-gateway', () => {
	it('registers the expected winbit32_* surface from env alone', () => {
		const config = buildConfig(WINBIT32_ENV);
		const server = buildGatewayMcpServer({ config, toolPrefix: config.toolPrefix });

		// McpServer keeps registered tools keyed by name.
		const names = Object.keys(server._registeredTools ?? {});
		expect(names).toHaveLength(EXPECTED_TOOL_COUNT);
		names.forEach((name) => expect(name).toMatch(/^winbit32_/));

		// One representative per always-on family.
		for (const expected of [
			'winbit32_q',
			'winbit32_paywall_info',
			'winbit32_private_watch_info',
			'winbit32_zec_scan_start',
			'winbit32_xmr_scan_start',
			'winbit32_phrase_validate',
			'winbit32_shamir_split',
			'winbit32_entropy_selftest',
			'winbit32_board_list',
			'winbit32_zec_amount_advice',
			'winbit32_zec_split_plan',
			'winbit32_ziving_info',
			'winbit32_ziving_create_page',
			'winbit32_nfpt_list_collections'
		]) {
			expect(names).toContain(expected);
		}

		// Gated families stay hidden until an operator opts in:
		//   make_payment → a .wult co-sign share; paid_unlock → PAID_UNLOCK_ENABLED.
		expect(names.filter((n) => n.includes('make_payment'))).toHaveLength(0);
		expect(names.filter((n) => n.includes('paid_unlock'))).toHaveLength(0);
		expect(names.filter((n) => n.includes('zec_bus'))).toHaveLength(0);
		expect(names.filter((n) => n.includes('nfpt_buy'))).toHaveLength(0);
	});
});
