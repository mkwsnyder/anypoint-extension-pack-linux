#!/usr/bin/env bash
# Install the VSIXes from build.sh in dependency order. VS Code fetches missing
# dependencies from the Marketplace, which has no Linux builds, so order matters.
#
# Usage: ./install.sh [dist-dir]    (default: ./dist)
# Env:   CODE=codium|code-oss|...   (default: code; may include extra CLI flags)
#        ARCH=x64|arm64             (default: this machine's)
set -euo pipefail
shopt -s nullglob

here=$(cd "$(dirname "$0")" && pwd)
dist=${1:-$here/dist}
host=$(uname -m); host=${host/x86_64/x64}; host=${host/aarch64/arm64}
files=("$dist"/*-linux-"${ARCH:-$host}".vsix)
(( ${#files[@]} )) || { echo "no linux-${ARCH:-$host} VSIXes in $dist; run ./build.sh first" >&2; exit 1; }

declare -A vsix
edges=""
for f in "${files[@]}"; do
  pkg=$(unzip -p "$f" extension/package.json)
  id=$(jq -r '.publisher + "." + .name' <<<"$pkg")
  vsix[$id]=$f
  # "a b" = install a before b. Packs go after their members.
  edges+=$(jq -r --arg id "$id" \
    '"\($id) \($id)", (((.extensionDependencies // []) + (.extensionPack // []))[] + " " + $id)' <<<"$pkg")$'\n'
done

for id in $(tsort <<<"$edges"); do
  [[ -n ${vsix[$id]:-} ]] || continue   # built-ins such as vscode.git
  # shellcheck disable=SC2086  # CODE may carry extra flags
  ${CODE:-code} --install-extension "${vsix[$id]}" --force
done
