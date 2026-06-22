/*
 * winbit32MCP CI/CD pipeline — job "winbit32MCP-master"
 *
 * THIS IS THE DEPLOY PATH FOR mcp.winbit32.com (the MCP server on 8821 + the
 * REST/x402 surface incl. the hosted-AI proxy on 8820). winbit32MCP is a thin
 * deployment of the payments-gateway engine, pinned by commit in package.json.
 *
 * Flow (master only for the deploy stages):
 *   Install + Test         npm ci (validates the lock + builds better-sqlite3
 *                          for v23) then the deployment smoke test.
 *   Security Scans         secret grep + non-blocking audit.
 *   Deploy -> Staging      deploy-mcp-release.sh into a pristine deploy-user
 *                          tree (~/tools/staging/winbit32mcp): clone/reset +
 *                          npm ci + smoke. NO services touched.
 *   Staging Check          assert the pinned payments-gateway carries the
 *                          hosted-AI sources + the lock pins a real commit.
 *   Deployment Approval    MANUAL GATE.
 *   Deploy -> Live         deploy-mcp-release.sh into /opt/winbit32mcp as the
 *                          winbit32mcp service user (git reset --hard to the
 *                          exact built commit + npm ci), then restart
 *                          winbit32-rest + winbit32-mcp.
 *   Health Check           loopback probes (REST /v1/ai + MCP socket).
 *
 * Node: pinned to the system node (v23, /usr/local/bin) to match the live
 * services. Deploy + restart use passwordless sudo (Jenkins runs as a user
 * with NOPASSWD sudo on this host).
 */

pipeline {
	agent any

	environment {
		PATH = "/usr/local/bin:${env.PATH}"
		CI   = 'true'
		MCP_STAGING_ROOT = "${env.HOME}/tools/staging/winbit32mcp"
	}

	options {
		buildDiscarder(logRotator(numToKeepStr: '20'))
		timeout(time: 25, unit: 'MINUTES')
		timestamps()
		disableConcurrentBuilds()
	}

	stages {

		stage('Checkout Info') {
			steps {
				sh '''
					echo "Branch:  ${BRANCH_NAME:-$GIT_BRANCH}"
					echo "Commit:  $(git rev-parse --short HEAD || echo n/a)"
					echo "Node:    $(node --version)"
					echo "npm:     $(npm --version)"
					echo "Pin:     $(grep -oE 'payments-gateway#[0-9a-f]+' package.json || echo '?')"
				'''
			}
		}

		stage('Install + Test') {
			steps {
				// npm ci is also the lock-consistency gate (the typescript
				// override keeps it ci-clean) and builds better-sqlite3 for v23.
				sh 'npm ci --no-audit --fund=false'
				sh 'npm test'
			}
		}

		stage('Security Scans') {
			parallel {
				stage('Dependency Audit') {
					steps {
						sh 'npm audit --omit=dev --audit-level=critical 2>&1 | tail -25 || true'
					}
				}
				stage('Secret Scan') {
					steps {
						sh '''
							echo "Scanning for hardcoded secrets (bin/ + repo root)..."
							FOUND=$(grep -rnE "(PRIVATE_KEY|mnemonic|password|secret|api_?key)\\s*[:=]\\s*['\\"][^'\\"]+" bin/ *.mjs *.js 2>/dev/null \
								| grep -v "process\\.env" \
								| grep -viE "example|placeholder|<your" \
								| head -10 || true)
							if [ -n "$FOUND" ]; then
								echo "WARN: potential hardcoded secrets:"; echo "$FOUND"
							else
								echo "No hardcoded secrets detected"
							fi
							# .env.example must stay a template (no real key material).
							if grep -qE "sk-[a-zA-Z0-9_-]{16,}|0x[a-fA-F0-9]{40}=" .env.example 2>/dev/null; then
								echo "ERROR: .env.example contains what looks like a real secret/address" >&2
								exit 1
							fi
						'''
					}
				}
			}
		}

		stage('Deploy → Staging') {
			when { branch 'master' }
			steps {
				sh '''
					echo "Staging release → $MCP_STAGING_ROOT (fresh checkout + npm ci, no services)"
					echo "Built commit: ${GIT_COMMIT:-HEAD}"
					TARGET_ROOT="$MCP_STAGING_ROOT" \
					DEPLOY_ENV=staging \
					RESTART_SERVICES=false \
					DEPLOY_REF="${GIT_COMMIT}" \
					bash scripts/deploy-mcp-release.sh
				'''
			}
		}

		stage('Staging Check') {
			when { branch 'master' }
			steps {
				sh '''
					test -f "$MCP_STAGING_ROOT/node_modules/payments-gateway/src/ai-credits.js"
					test -f "$MCP_STAGING_ROOT/node_modules/payments-gateway/src/ai-session-store.js"
					grep -qE "payments-gateway.git#[0-9a-f]{40}" "$MCP_STAGING_ROOT/package-lock.json" \
						|| { echo "ERROR: staging lock has no resolved payments-gateway commit" >&2; exit 1; }
					# better-sqlite3 must load under the pinned node in the staging tree.
					node -e "require('$MCP_STAGING_ROOT/node_modules/better-sqlite3'); console.log('staging better-sqlite3 OK')"
					echo "winbit32MCP staging release ready at $MCP_STAGING_ROOT"
				'''
			}
		}

		stage('Deployment Approval') {
			when { branch 'master' }
			steps {
				input message: 'Staging release is ready. Deploy to LIVE (mcp.winbit32.com)? This resets /opt/winbit32mcp to the built commit as the winbit32mcp user, npm ci, and restarts winbit32-rest + winbit32-mcp.',
				      ok: 'Deploy Live'
			}
		}

		stage('Deploy → Live') {
			when { branch 'master' }
			steps {
				sh '''
					echo "Live deploy → /opt/winbit32mcp (as winbit32mcp) + service restarts"
					echo "Built commit: ${GIT_COMMIT:-HEAD}"
					TARGET_ROOT=/opt/winbit32mcp \
					DEPLOY_ENV=live \
					RESTART_SERVICES=true \
					SERVICE_USER=winbit32mcp \
					DEPLOY_REF="${GIT_COMMIT}" \
					bash scripts/deploy-mcp-release.sh
				'''
			}
		}

		stage('Health Check') {
			when { branch 'master' }
			steps {
				sh '''
					# Public TLS surface should report hosted AI enabled.
					for i in 1 2 3 4 5; do
						EN=$(curl -fsS https://mcp.winbit32.com/v1/ai 2>/dev/null | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).enabled)}catch{console.log('x')}})" 2>/dev/null || echo x)
						if [ "$EN" = "true" ]; then echo "Hosted AI live (enabled=true)"; exit 0; fi
						echo "waiting for /v1/ai... attempt $i (enabled=$EN)"; sleep 3
					done
					echo "ERROR: hosted AI did not report enabled=true within 25s" >&2
					exit 1
				'''
			}
		}
	}

	post {
		failure {
			echo "winbit32MCP pipeline FAILED — ${env.BRANCH_NAME ?: env.GIT_BRANCH} build #${env.BUILD_NUMBER}"
		}
		success {
			echo "winbit32MCP pipeline succeeded — ${env.BRANCH_NAME ?: env.GIT_BRANCH} build #${env.BUILD_NUMBER}"
		}
	}
}
