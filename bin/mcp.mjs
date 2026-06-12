#!/usr/bin/env node
// winbit32 deployment wrapper — the engine lives in payments-gateway.
// All behaviour comes from the environment (/etc/winbit32/mcp.env):
// GATEWAY_TOOL_PREFIX=winbit32, GATEWAY_SERVICE_NAME=winbit32, etc.
import 'payments-gateway/bin/mcp.mjs';
