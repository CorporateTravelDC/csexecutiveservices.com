#!/usr/bin/env bash
# scripts/sign-manifest.sh
# Generates and GPG-signs a whole-repo-tree integrity manifest for this repo
# -- same mechanism as ctdi-dispatch-internal's identical script (see that
# repo's docs/COMPLIANCE_SECURITY.md "Signed Manifest Integrity" section for
# the full design and threat model).
#
# This is a DELIBERATE, human-run step -- same posture as this repo's signed
# commits (git config commit.gpgsign=true): nothing re-signs the manifest
# automatically. Run this after making changes you're ready to trust, as
# part of the same review/commit pass, using your own GPG passphrase.
#
# Usage:
#   scripts/sign-manifest.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_DIR}"

ENV_FILE="security/signing.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "XX Missing ${ENV_FILE} -- copy security/signing.env.example, fill in your" >&2
    echo "   own SIGNING_KEY_FINGERPRINT, and re-run." >&2
    exit 2
fi
# shellcheck source=/dev/null
source "${ENV_FILE}"
: "${SIGNING_KEY_FINGERPRINT:?SIGNING_KEY_FINGERPRINT not set in ${ENV_FILE}}"
if [[ "${SIGNING_KEY_FINGERPRINT}" == "0000000000000000000000000000000000000000" ]]; then
    echo "XX ${ENV_FILE} still has the placeholder fingerprint -- fill in your real one." >&2
    exit 2
fi

MANIFEST="MANIFEST.sha256"
SIGNATURE="MANIFEST.sha256.asc"

# 2026-09-01: backported from ctdi-dispatch-internal's identical script
# (its 2026-08-19/20 fixes) after this exact old pattern -- unconditional
# `rm -f "${SIGNATURE}"` immediately followed by a bare gpg call, with
# MANIFEST written directly in place too -- produced a repo with NO valid
# signature at all. gpg failed or was interrupted mid-run (headless
# passphrase prompt, terminal disconnect, whatever) after the old
# signature was already deleted; `set -e` then aborted the script, but
# the tree was already left with a regenerated MANIFEST.sha256 and a
# MISSING MANIFEST.sha256.asc, which got committed as-is. Both files now
# only ever change together, atomically, on a fully successful run --
# the trap below fires on any early exit and leaves the real MANIFEST/
# SIGNATURE pair exactly as they were.
TMP_MANIFEST="$(mktemp "${MANIFEST}.XXXXXX")"
trap 'rm -f "${TMP_MANIFEST}" "${TMP_SIGNATURE:-}"' EXIT

echo "[sign-manifest] Hashing every tracked AND untracked-but-not-ignored file (true whole-repo-tree coverage)..."
# See ctdi-dispatch-internal's identical script for why this isn't just
# `git ls-files` (tracked-only) -- that silently excluded every new file
# not yet `git add`ed, including this fix's own predecessor.
#
# contact-api/MANIFEST.sha256 and contact-api/MANIFEST.sha256.asc are
# ALSO excluded here, not just the top-level pair -- they're copies
# refreshed below (line ~60) AFTER this hash step runs, so including them
# is an unresolvable chicken-and-egg: whatever content they held BEFORE
# this run gets hashed/signed, then immediately overwritten by this run's
# fresh copies, so verify-manifest.sh would find them "mismatched"
# forever, one generation behind, on every single run. Their integrity is
# already anchored independently -- contact-api/main.py's _verify_self()
# GPG-verifies contact-api/MANIFEST.sha256.asc's signature directly (a
# valid detached signature is self-authenticating; it doesn't also need
# an outer hash-manifest entry pointing at itself).
#
# Exclude the whole MANIFEST.sha256* family, not just the two exact final
# names -- otherwise a stray mktemp temp file left behind by a killed
# concurrent run gets picked up by `git ls-files --others` and baked into
# the manifest as a real (soon-to-vanish) entry.
git ls-files --cached --others --exclude-standard -z \
    | grep -zvE "^(${MANIFEST}(\..*)?|contact-api/${MANIFEST}(\..*)?)\$" \
    | xargs -0 sha256sum \
    | sort -k2 \
    > "${TMP_MANIFEST}"

echo "[sign-manifest] $(wc -l < "${TMP_MANIFEST}") files covered."
echo "[sign-manifest] Signing with key ${SIGNING_KEY_FINGERPRINT} (you'll be prompted for your passphrase)..."
TMP_SIGNATURE="$(mktemp "${SIGNATURE}.XXXXXX")"
if gpg --local-user "${SIGNING_KEY_FINGERPRINT}" --detach-sign --armor --yes \
       -o "${TMP_SIGNATURE}" "${TMP_MANIFEST}"; then
    mv "${TMP_MANIFEST}" "${MANIFEST}"
    mv "${TMP_SIGNATURE}" "${SIGNATURE}"
else
    echo "[sign-manifest] FAILED -- gpg did not produce a signature (see error above)." >&2
    echo "[sign-manifest] ${MANIFEST} + ${SIGNATURE} left untouched -- no valid pair was destroyed." >&2
    exit 1
fi

echo "[sign-manifest] OK -- ${MANIFEST} + ${SIGNATURE} written."

# contact-api's image has always been built with contact-api/ itself as the
# build context (confirmed via the existing image's history before this was
# added), so it can't COPY from ../security or ../MANIFEST.sha256 directly.
# Keep its duplicated copies in lockstep by refreshing them on every sign,
# rather than relying on someone remembering to do it by hand.
if [[ -d "contact-api" ]]; then
    cp "${MANIFEST}" "${SIGNATURE}" "security/trusted-signing-key.pub.asc" contact-api/
    echo "[sign-manifest] Refreshed contact-api/'s duplicated manifest + pubkey copies."
fi

echo "[sign-manifest] Verify with: scripts/verify-manifest.sh"
echo "[sign-manifest] Remember to commit both files (and contact-api/'s refreshed copies) alongside the changes they cover."
