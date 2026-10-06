#!/usr/bin/env bash
# scripts/wrangler-container.sh -- runs `wrangler` inside the existing
# node:20-alpine podman image instead of installing it on the host.
#
# Why: this box's convention is to keep tooling containerized. node:20-alpine
# was already pulled (4 months idle, never wired to anything) -- this wires
# it up via `npx` rather than building a custom image, so there's nothing to
# rebuild/maintain beyond this script.
#
# 2026-09-03 (operator directive, consolidating three separate Cloudflare
# credentials down to one): the token now comes from
# CF_MANAGEMENT_API_TOKEN in /etc/corporatetraveldc/dispatch-secrets.env --
# the SAME account-scoped management token ctdi-dispatch-internal's
# cf-service-token-{mint,reconcile,breakglass}.sh already use, re-minted
# 2026-09-03 with Pages/Workers/DNS/Firewall/Access scopes added and IP
# Address Filtering locked to this Pi's two real egress addresses (wld0 +
# enu1). No longer reads ~/.secrets/csexec-website-cloudflare.env (was an
# empty, never-populated placeholder) or ~/.secrets/cloudflare.key
# (confirmed dead, see docs/HONEYPOT_FAIL2BAN.md in ctdi-dispatch-internal)
# -- both retired. Passed to the container as a single -e flag (not
# --env-file against the whole secrets file) so nothing else in
# dispatch-secrets.env is ever exposed to this throwaway container.
#
# Usage: scripts/wrangler-container.sh <wrangler args...>
#   e.g. scripts/wrangler-container.sh pages deploy www/ --project-name csexec-pages --commit-dirty=true
#   e.g. scripts/wrangler-container.sh deploy
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_DIR}"

SECRETS_ENV="/etc/corporatetraveldc/dispatch-secrets.env"
export CLOUDFLARE_API_TOKEN="$(grep -E '^CF_MANAGEMENT_API_TOKEN=' "${SECRETS_ENV}" 2>/dev/null | tail -1 | cut -d'=' -f2-)"
# 2026-09-03: this account-scoped token can't satisfy wrangler's own
# /memberships auth-discovery call (a user-scoped endpoint -- confirmed
# live, "Authentication failed (status: 400) [code: 9106]" on a plain
# `pages deploy`). Setting CLOUDFLARE_ACCOUNT_ID explicitly skips that
# discovery step entirely, same fix pattern as the earlier
# /user/tokens/verify mismatch.
export CLOUDFLARE_ACCOUNT_ID="$(grep -E '^CF_ACCOUNT_ID=' "${SECRETS_ENV}" 2>/dev/null | tail -1 | cut -d'=' -f2-)"
if [[ -z "${CLOUDFLARE_API_TOKEN}" || -z "${CLOUDFLARE_ACCOUNT_ID}" ]]; then
    echo "XX CF_MANAGEMENT_API_TOKEN or CF_ACCOUNT_ID not set in ${SECRETS_ENV}" >&2
    exit 2
fi

# Named volume, not a bind mount -- persists npx's downloaded wrangler
# package across runs (skip re-fetching ~40MB every deploy) without ever
# touching the repo tree or the host filesystem outside podman's own
# volume store.
podman volume create --ignore csexec-wrangler-npm-cache >/dev/null

echo "[wrangler-container] running: wrangler $*"
# 2026-09-01: a `wrangler whoami` run appeared to hang (near-zero CPU for
# minutes). Turned out NOT to be an interactive-prompt hang (CI=true /
# WRANGLER_SEND_METRICS=false below are harmless CI-convention defaults,
# but weren't the actual fix) -- this Pi's bandwidth is just severely
# constrained for large binary blobs specifically: a single package
# (@esbuild/linux-arm64's native binary) took a confirmed 11 minutes to
# download in the npm debug log, real progress the whole time, not stuck.
# Killing it early (twice) each time corrupted node_modules/.bin/ in the
# npx cache (npm links bin symlinks as one of its last install steps),
# which made the NEXT run fail fast with a misleading "wrangler: not
# found" that looked like a different bug entirely. `timeout` here is a
# safety net for a genuine hang, not a speed budget -- set generously
# (30 min) so a real slow-but-progressing install is never mistaken for
# one and killed mid-way again.
timeout 1800 podman run --rm \
    -e CLOUDFLARE_API_TOKEN \
    -e CLOUDFLARE_ACCOUNT_ID \
    -e CI=true \
    -e WRANGLER_SEND_METRICS=false \
    -v "${REPO_DIR}:/repo:Z" \
    -v "csexec-wrangler-npm-cache:/root/.npm:Z" \
    -w /repo \
    docker.io/library/node:20-alpine \
    npx --yes wrangler@4 "$@"
