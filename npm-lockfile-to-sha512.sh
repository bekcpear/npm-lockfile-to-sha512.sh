#!/usr/bin/env bash
#
# @cwittlut, old username: @bekcpear
#

set -e

LOCK_FILE="${1:-package-lock.json}"
DIFF_PATH="${2:-frontend/package-lock.json}"
TMP_LOCK="/tmp/package-lock.json-$(uuidgen)"
DISTDIR="/var/cache/distfiles"
REPO_PATH="/home/ryan/Git/npm-lockfile-to-sha512.sh"
DIFF_NAME="npm-lockfile-to-sha512.diff"

#NPM_EBUILD=""
#ebuild "${NPM_EBUILD}" fetch

mkdir -p $(dirname "${TMP_LOCK}/${DIFF_PATH}")
cp -f "${LOCK_FILE}" "${TMP_LOCK}/${DIFF_PATH}"
pushd "${TMP_LOCK}" >/dev/null
git init -q
git add .
git commit -q --no-gpg-sign -m 'diff'

trap '
if [[ -d "${TMP_LOCK}" ]]; then
  rm -rf "${TMP_LOCK}"
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
  eval "sed -Ei '/^\s*\"integrity\":\s+\"${i}\",?$/s@${i}@${sha512im}@' ${TMP_LOCK}/${DIFF_PATH}"

  echo -en "\e[G\e[K seding .. ${_SYMBOL[${_SYMBOL_I}]} "
  if [[ ${_SYMBOL_I} == 3 ]]; then
    _SYMBOL_I=0
  else
    _SYMBOL_I+=1
  fi
done <<<$(jq -c '.packages[] | select(has("integrity")) | select(.integrity|test("^sha1-")) | { "r": .resolved, "i": .integrity }' "${TMP_LOCK}/${DIFF_PATH}")

echo

PATCH_FILE="/tmp/package-lock-to-sha512-$(uuidgen).diff"
git --no-pager diff --patch "${TMP_LOCK}/${DIFF_PATH}" >${PATCH_FILE}
if [[ $? == 0 ]]; then
  read -p "Enter the tag name: " tagname
  pushd "${REPO_PATH}"
  if git rev-parse diff &>/dev/null; then
    git checkout diff
  else
    git checkout --orphan diff
    git rm -rf .
  fi
  if ! ls -1 | grep -v "${DIFF_NAME}"; then
    cp "${PATCH_FILE}" ./"${DIFF_NAME}"
    git add ./"${DIFF_NAME}"
    git commit -m "update ${DIFF_NAME}"
    git tag -a ${tagname} -m "new tag: ${tagname}"
    #git push --tags
    rm "${PATCH_FILE}"
  else
    echo "error!" >&2
  fi
fi
