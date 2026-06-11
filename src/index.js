// payments-gateway — public barrel.
//
// Re-exports the building blocks a host needs to embed the gateway, plus the
// gateway's own config + x402 helpers. The view-key scanning/store/pricing
// primitives live in `viewkey-watch`; import those directly where needed.

export { buildConfig, config, default as gatewayConfig } from './config.js';

export {
	buildX402Config,
	createFacilitatorClient,
	registerX402,
	resolveRoutePrices,
	describePaywall,
	discoveryConfigForRouteKey,
	assertPrice,
	CDP_FACILITATOR_URL
} from './x402.js';

export { GATEWAY_PREMIUM_ROUTES, qFact } from './x402-routes.js';

export {
	CUSTOM_TOPUP_LIMITS,
	validateCustomTopupRequest,
	buildCustomPaymentRequirements,
	encodeChallenge,
	decodePaymentHeader,
	registerCustomTopupRoute
} from './private-watch-custom.js';

export {
	validateCryptoTopupRequest,
	withMoneroTag,
	generateMemo,
	formatUsdCents,
	buildInstructions,
	publicQuote,
	registerCryptoTopupRoutes
} from './private-watch-crypto-topup.js';

export {
	monRpc,
	zecRpc,
	qXmrHeight,
	qXmrMempool,
	qXmrFee,
	qXmrLastBlock,
	qZecHeight,
	qZecMempool,
	qZecLastBlock,
	CHAIN_QUESTION_REGISTRY,
	dispatchChainQuestion,
	createChainCache
} from './queries-q-chain.js';
