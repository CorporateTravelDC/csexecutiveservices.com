#!/usr/bin/env bash
# scripts/agent-deploy.sh -- ntfy-approval-gated site deploy for
# unattended/agent use (2026-09-03, operator directive: "sibling
# delegated [key], via ntfy sudo-approval-gate logic" to
# ctdi-dispatch-internal's sign-manifest.sh --agent pattern).
#
# What this actually does: requests human Allow/Deny over ntfy (via
# ctdi-dispatch-internal's scripts/sudo-approval-gate.sh -- a shared,
# box-level utility, not repo-specific; it reads the shared
# dispatch-secrets.env and hits the shared admin API on this same Pi),
# and only on an explicit Allow runs deploy.sh with DEPLOY_SIGNING_KEY
# set so its one git commit signs with the no-passphrase delegate key
# below instead of hanging on an interactive passphrase prompt (which is
# the actual problem this exists to solve -- deploy.sh's git commit needs
# a passphrase deploy.sh has no way to supply non-interactively).
#
# Real difference from the sign-manifest.sh --agent precedent this
# mirrors: that one's delegate key only ever signs an integrity MANIFEST
# file, never a git commit -- every commit in that repo is still made,
# and signed with the operator's own key, by the operator directly. This
# script's delegate key signs the COMMIT itself. Treat it as a distinct,
# more sensitive grant -- narrowly scoped to this one repo's routine
# content/deploy commits, not a precedent for git-committing anywhere
# else as this key or removing the operator from the commit path in
# general.
#
# Delegate GPG key: CS Executive Services Website Agent
#   108E5C6AB59D01F359ED6BC6674764DFF4B7E73E
#   <agent@example.com>, no passphrase, ultimate trust,
#   expires 2027-09-03. Not published to /keys/ -- see
#   docs/GPG_KEYS_PUBLISHED.md in ctdi-dispatch-internal for why the
#   automated-signing keys stay unpublished (no external party has a
#   reason to verify against them).
#
# Delegate SSH key: ~/.ssh/agent-deploy-github ("agent-deploy-key"), no
# passphrase, registered account-wide on GitHub via
# `gh ssh-key add --type authentication` (2026-09-03) -- works for this
# repo, ctdi-dispatch-internal, and any future repo with zero extra
# per-repo setup. Root cause it fixes: the operator's own push identity
# (~/.ssh/corporatetraveldc-github) is passphrase-protected, same shape
# as the GPG issue one layer up -- confirmed via verbose ssh that GitHub
# correctly accepts that key ("Server accepts key"), so this was never a
# GitHub-side permissions problem, purely a local can't-prompt-for-a-
# passphrase-non-interactively one.
#
# Both delegate keys share the identical "opt-in override, unset/absent
# by default" shape, deliberately: neither is a default identity a plain
# manual run of deploy.sh (or `git commit`/`git push` on its own) would
# ever pick up. The GPG key is never set as any global/repo
# user.signingkey -- DEPLOY_SIGNING_KEY below is the ONLY thing that
# activates it, via a one-off `git -c user.signingkey=...` inside
# deploy.sh. The SSH key is never added to ~/.ssh/config -- GIT_SSH_COMMAND
# below is the ONLY thing that activates it. Both env vars are set here,
# in this script, and nowhere else -- meaning both delegate identities are
# reachable ONLY by going through sudo-approval-gate.sh's ntfy Allow/Deny
# first. A human running deploy.sh directly, or `git push` directly,
# always uses their own real, passphrase-protected keys, unaffected by
# any of this.
#
# Usage: agent-deploy.sh [deploy.sh args, e.g. --pages-only/--worker-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GATE="/opt/corporatetraveldc/private/ctdi-dispatch-internal/scripts/sudo-approval-gate.sh"
DELEGATE_KEY="108E5C6AB59D01F359ED6BC6674764DFF4B7E73E"
AGENT_SSH_KEY="${HOME}/.ssh/agent-deploy-github"

if [[ ! -x "${GATE}" ]]; then
    echo "ERROR: approval-gate script not found/executable at ${GATE}" >&2
    exit 1
fi
if [[ ! -f "${AGENT_SSH_KEY}" ]]; then
    echo "ERROR: agent SSH key not found at ${AGENT_SSH_KEY}" >&2
    exit 1
fi

export DEPLOY_SIGNING_KEY="${DELEGATE_KEY}"
export GIT_SSH_COMMAND="ssh -i ${AGENT_SSH_KEY} -o IdentitiesOnly=yes"

exec "${GATE}" \
    "website-deploy:csexecutiveservices" \
    "Deploy csexecutiveservices-website (content/site update) -- signs its one git commit with the no-passphrase website-agent delegate key, not the operator's real key." \
    -- bash "${REPO_DIR}/deploy.sh" "$@"
