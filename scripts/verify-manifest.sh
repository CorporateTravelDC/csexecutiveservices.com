#!/usr/bin/env bash
# scripts/verify-manifest.sh
# Verifies this repo's signed whole-repo-tree integrity manifest
# (MANIFEST.sha256 + MANIFEST.sha256.asc, see scripts/sign-manifest.sh) --
# same mechanism as ctdi-dispatch-internal's identical script (see that
# repo's docs/COMPLIANCE_SECURITY.md "Signed Manifest Integrity" section).
#
# Two modes, same underlying check:
#   scripts/verify-manifest.sh                 # collective: every covered
#                                               # file, like an ISO's
#                                               # sha256sum -c -- for
#                                               # validating a fresh clone
#                                               # is a genuine, untampered
#                                               # copy.
#   scripts/verify-manifest.sh <repo/rel/path>  # single-file: fast path for
#                                               # a runtime guard checking
#                                               # just itself/one file
#                                               # before doing anything.
#
# Both first verify MANIFEST.sha256.asc's signature against
# security/trusted-signing-key.pub.asc using an ISOLATED keyring -- never the
# caller's ambient GPG keyring.
#
# Exit 0 = verified clean. Any non-zero = do not trust the file(s).
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_DIR}"

MANIFEST="MANIFEST.sha256"
SIGNATURE="MANIFEST.sha256.asc"
PUBKEY="security/trusted-signing-key.pub.asc"

for f in "${MANIFEST}" "${SIGNATURE}" "${PUBKEY}"; do
    if [[ ! -f "${f}" ]]; then
        echo "verify-manifest: missing ${f} -- cannot verify, refusing to trust anything" >&2
        exit 2
    fi
done

GNUPGHOME_TMP="$(mktemp -d)"
trap 'rm -rf "${GNUPGHOME_TMP}"' EXIT
chmod 700 "${GNUPGHOME_TMP}"
export GNUPGHOME="${GNUPGHOME_TMP}"

gpg --quiet --import "${PUBKEY}" >/dev/null 2>&1

gpg_err="$(mktemp)"
if ! gpg --quiet --verify "${SIGNATURE}" "${MANIFEST}" 2>"${gpg_err}"; then
    echo "verify-manifest: SIGNATURE INVALID -- ${SIGNATURE} does not verify against ${PUBKEY}" >&2
    cat "${gpg_err}" >&2
    rm -f "${gpg_err}"
    exit 1
fi
rm -f "${gpg_err}"

if [[ $# -eq 0 ]]; then
    if sha256sum -c "${MANIFEST}" --quiet; then
        echo "verify-manifest: OK -- signature valid, all $(wc -l < "${MANIFEST}") files match."
        exit 0
    else
        echo "verify-manifest: INTEGRITY FAILURE -- one or more files do not match the signed manifest (see above)." >&2
        exit 1
    fi
fi

target="$1"
line="$(awk -v t="${target}" '$2==t {print; found=1} END{exit !found}' "${MANIFEST}")"
if [[ -z "${line}" ]]; then
    echo "verify-manifest: ${target} is not in the signed manifest at all -- refusing to trust it" >&2
    exit 1
fi
if ! printf '%s\n' "${line}" | sha256sum -c --quiet - >/dev/null 2>&1; then
    echo "verify-manifest: INTEGRITY FAILURE -- ${target} does not match its signed hash" >&2
    exit 1
fi
exit 0
