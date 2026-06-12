// Deployment smoke test: this repo is a thin wrapper, so the only thing
// worth pinning here is that the upstream engine installs, the winbit32
// branding applies, and the expected 21-tool surface registers under the
// winbit32_ prefix (make_payment family stays hidden until an operator
// stages a .wult share — custody is the operator's call).

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

describe('winbit32 deployment of payments-gateway', () => {
	it('registers the 21-tool winbit32_* surface from env alone', () => {
		const config = buildConfig(WINBIT32_ENV);
		const server = buildGatewayMcpServer({ config, toolPrefix: config.toolPrefix });

		// McpServer keeps registered tools keyed by name.
		const names = Object.keys(server._registeredTools ?? {});
		expect(names).toHaveLength(21);
		names.forEach((name) => expect(name).toMatch(/^winbit32_/));

		// One representative per family.
		for (const expected of [
			'winbit32_q',
			'winbit32_paywall_info',
			'winbit32_private_watch_info',
			'winbit32_zec_scan_start',
			'winbit32_xmr_scan_start',
			'winbit32_phrase_validate',
			'winbit32_shamir_split'
		]) {
			expect(names).toContain(expected);
		}

		// No .wult share configured → no make_payment tools.
		expect(names.filter((n) => n.includes('make_payment'))).toHaveLength(0);
	});
});
