#!/usr/bin/env bash
# CS Executive Services — site deploy script
# Run from /opt/csexec-website/ on the Pi.
#
# What this does (all outbound, nothing inbound to Pi):
#   1. git push main → triggers GitHub Actions → updates GitHub Pages (tertiary)
#   2. wrangler pages deploy → updates CF Pages (secondary fallback)
#   3. wrangler deploy → updates CF Worker at www.csexecutiveservices.com
#
# Usage:
#   ./deploy.sh                 full deploy
#   ./deploy.sh --pages-only    skip Worker deploy
#   ./deploy.sh --worker-only   skip Pages deploy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PAGES_ONLY=false
WORKER_ONLY=false
for arg in "$@"; do
  case $arg in
    --pages-only)  PAGES_ONLY=true  ;;
    --worker-only) WORKER_ONLY=true ;;
  esac
done

echo "=== CS Executive Services — deploy ==="
echo "    $(date '+%Y-%m-%d %H:%M %Z')"
echo ""

# ── 1. Git push (→ GitHub Pages via Actions) ────────────────────────────
if [[ "$WORKER_ONLY" == "false" ]]; then
  echo "[1/3] git push → GitHub Pages (tertiary failsafe)"
  git add -A
  if git diff --cached --quiet; then
    echo "      nothing to commit — skipping git push"
  else
    # DEPLOY_SIGNING_KEY (2026-09-03, operator directive): opt-in override,
    # unset by default -- a normal manual run of this script is completely
    # unaffected and still signs with whatever the operator's own global
    # git config points at (their real passphrase-protected key). Only set
    # by scripts/agent-deploy.sh, which routes through
    # scripts/sudo-approval-gate.sh (ntfy Allow/Deny) first -- see that
    # script and docs/AGENT_DEPLOY.md. Sibling of ctdi-dispatch-internal's
    # sign-manifest.sh --agent delegate-key pattern, with one real
    # difference: that one only ever signs an integrity MANIFEST, never a
    # commit -- this one has to sign the commit itself, since that's the
    # actual step deploy.sh needs unblocked. Treat this as strictly more
    # sensitive than that precedent, not an equivalent-risk copy of it.
    if [[ -n "${DEPLOY_SIGNING_KEY:-}" ]]; then
      git -c "user.signingkey=${DEPLOY_SIGNING_KEY}" commit -m "deploy: $(date '+%Y-%m-%d %H:%M') (agent, approval-gated)"
    else
      git commit -m "deploy: $(date '+%Y-%m-%d %H:%M')"
    fi
    git push origin main
    echo "      pushed — GitHub Actions will update gh-pages branch"
  fi
  echo ""
fi

# ── 2. CF Pages (secondary fallback) ────────────────────────────────────
# wrangler runs containerized (node:20-alpine via podman, see
# scripts/wrangler-container.sh) -- not installed on the host.
if [[ "$WORKER_ONLY" == "false" ]]; then
  echo "[2/3] wrangler pages deploy → CF Pages (secondary fallback)"
  # 2026-09-03: the real CF Pages project is named csexec-pages, not
  # csexec-site (confirmed live via `GET /accounts/{id}/pages/projects`
  # while re-minting the consolidated management token) -- this line had
  # been pointing at a project name that doesn't exist.
  ./scripts/wrangler-container.sh pages deploy www/ --project-name csexec-pages --commit-dirty=true
  echo ""
fi

# ── 3. CF Worker (smart router) ─────────────────────────────────────────
if [[ "$PAGES_ONLY" == "false" ]]; then
  echo "[3/3] wrangler deploy → CF Worker (smart router)"
  ./scripts/wrangler-container.sh deploy
  echo ""
fi

echo "=== deploy complete ==="
