#!/usr/bin/env bash
#
# @cwittlut, old username: @bekcpear
#

set -e

LOCK_FILE="${1:-package-lock.json}"
TMP_LOCK="/tmp/package-lock.json-$(uuidgen)"
DISTDIR="/var/cache/distfiles"

#NPM_EBUILD=""
#ebuild "${NPM_EBUILD}" fetch

cp -f "${LOCK_FILE}" "${TMP_LOCK}"

trap '
if [[ -f "${TMP_LOCK}" ]]; then
  rm "${TMP_LOCK}"
fi
' EXIT

_SYMBOL=('|' '/' '-' '\')
declare -i _SYMBOL_I=0
while read json; do
  if [[ ${json} == "" ]]; then
    echo "no sha1 integrity, exit"
    exit 0
  fi

  r=$(jq '.r' <<<"${json}")
  i=$(jq '.i' <<<"${json}")
  i=${i//\"/}
  distpath=${DISTDIR}/$(sed -E 's@^"https?://[^/]+/(.+)"@\1@;s@/@:2F@g' <<<${r})

  if [[ ! -f "${distpath}" ]]; then
    echo "the corresponding file '${distpath}'" of ${r} does not exist or is not a regular file. >&2
    exit 1
  fi

  sha1im="sha1-$(openssl dgst -sha1 -binary ${distpath} | openssl base64 -A)"
  if [[ "${i}" != "${sha1im}" ]]; then
    echo "the corresponding file '${distpath}'" of ${r} mismatches recorded sha1im. >&2
    exit 1
  fi

  sha512im="sha512-$(openssl dgst -sha512 -binary ${distpath} | openssl base64 -A)"
  i=${i//\//\\\/}
  i=${i//+/\\+}
  eval "sed -Ei '/^\s*\"integrity\":\s+\"${i}\",?$/s@${i}@${sha512im}@' ${TMP_LOCK}"

  echo -en "\e[G\e[K seding .. ${_SYMBOL[${_SYMBOL_I}]} "
  if [[ ${_SYMBOL_I} == 3 ]]; then
    _SYMBOL_I=0
  else
    _SYMBOL_I+=1
  fi
done <<<$(jq -c '.packages[] | select(has("integrity")) | select(.integrity|test("^sha1-")) | { "r": .resolved, "i": .integrity }' "${LOCK_FILE}")

echo

mv "${LOCK_FILE}" "${LOCK_FILE}.bak"
mv "${TMP_LOCK}" "${LOCK_FILE}"

PATCH_FILE="/tmp/package-lock-to-sha512-$(uuidgen).diff"
git --no-pager diff --patch "${LOCK_FILE}" >${PATCH_FILE} && \
  echo "Patch has been written to ${PATCH_FILE}"
