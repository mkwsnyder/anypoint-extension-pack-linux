#!/usr/bin/env bash
# Build Linux VSIXes of the Anypoint Extension Pack (Anypoint Code Builder) from the
# official macOS builds on the VS Code Marketplace.
#
# A Linux build differs from the macOS one in only three bundled payloads, all swapped here:
#   - Temurin JDK    salesforce.mule-dx-dependencies
#   - Node runtime   salesforce.mule-dx-api-component
#   - acv validator  salesforce.mule-dx-api-component (built from source)
# Everything else is platform-neutral or already ships Linux binaries.
#
# Usage: ./build.sh [out-dir]       (default: ./dist)
# Env:   ARCH=x64|arm64             (default: this machine's)
#        WORK_DIR=<dir>             (default: ./work; downloads are cached here)
set -euo pipefail
shopt -s nullglob

die() { printf '%b\n' "error: $*" >&2; exit 1; }
log() { printf '%s\n' "$*" >&2; }

here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "${1:-$here/dist}" && out=$(cd "${1:-$here/dist}" && pwd)
work=${WORK_DIR:-$here/work}
dl=$work/downloads stage=$work/stage
pack=salesforce.mule-dx-extension-pack
gallery=https://marketplace.visualstudio.com/_apis/public/gallery
# Commit of aml-org/amf-custom-validator matching the shipped acv binary. The build
# stops below if a new release ships an acv built from different dependencies.
acv_commit=64506ed734c260c666792b66ded36f7273a984eb

host=$(uname -m); host=${host/x86_64/x64}; host=${host/aarch64/arm64}
ARCH=${ARCH:-$host}
case $ARCH in
  x64)   jdk_arch=x64     go_arch=amd64 ;;
  arm64) jdk_arch=aarch64 go_arch=arm64 ;;
  *) die "unsupported ARCH '$ARCH' (use x64 or arm64)" ;;
esac
src_platform=darwin-$ARCH target=linux-$ARCH

for c in curl jq unzip zip tar xz git go file sha256sum; do
  command -v "$c" >/dev/null || die "missing required command: $c"
done

# download URL DEST: fetch once, cache in $dl.
download() {
  [[ -f $2 ]] && return
  curl -fL --retry 3 --compressed --progress-bar -o "$2.part" "$1"
  mv "$2.part" "$2"
}

# Latest stable version of extension $1 (publisher.name) with a $src_platform build.
latest_version() {
  curl -fsS --retry 3 -X POST "$gallery/extensionquery" \
    -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=7.2-preview.1' \
    -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$1\"}]}],\"flags\":17}" |
  jq -er --arg p "$src_platform" '[.results[0].extensions[0].versions[]
      | select(.targetPlatform == $p)
      | select(any(.properties[]?; .key == "Microsoft.VisualStudio.Code.PreRelease" and .value == "true") | not)
    ][0].version'
}

# fetch ID: download the $src_platform build of extension ID and unzip it into $stage/ID.
fetch() {
  local v
  v=$(latest_version "$1") || die "no $src_platform build of $1 on the Marketplace"
  log "fetching $1 $v ($src_platform)"
  download "$gallery/publishers/${1%%.*}/vsextensions/${1#*.}/$v/vspackage?targetPlatform=$src_platform" \
    "$dl/$1-$v-$src_platform.vsix"
  unzip -q "$dl/$1-$v-$src_platform.vsix" -d "$stage/$1"
}

rm -rf "${stage:?}" && mkdir -p "$stage" "$dl"
rm -f "$out"/*-"$target".vsix

fetch "$pack"
mapfile -t members < <(jq -r '.extensionPack[]' "$stage/$pack/extension/package.json")
for id in "${members[@]}"; do fetch "$id"; done

# --- JDK -----------------------------------------------------------------------
deps=$stage/salesforce.mule-dx-dependencies/extension
releases=("$deps"/build/deps/jdk-*/Contents/Home/release)
(( ${#releases[@]} == 1 )) || die "expected exactly one macOS JDK in $deps/build/deps"
grep -q '^IMPLEMENTOR="Eclipse Adoptium"' "${releases[0]}" || die "bundled JDK is no longer Temurin"
jdk_dir=${releases[0]%/Contents/Home/release}
jdk_ver=$(sed -n 's/^IMPLEMENTOR_VERSION="Temurin-\(.*\)"$/\1/p' "${releases[0]}")   # e.g. 17.0.20.1+1
major=${jdk_ver%%.*}
jdk_tgz=OpenJDK${major}U-jdk_${jdk_arch}_linux_hotspot_${jdk_ver/+/_}.tar.gz
jdk_url=https://github.com/adoptium/temurin${major}-binaries/releases/download/jdk-${jdk_ver/+/%2B}/$jdk_tgz
log "fetching Temurin $jdk_ver ($jdk_arch)"
download "$jdk_url" "$dl/$jdk_tgz"
curl -fsSL --retry 3 "$jdk_url.sha256.txt" > "$dl/$jdk_tgz.sha256"
(cd "$dl" && sha256sum -c --quiet "$jdk_tgz.sha256")
rm -rf "${jdk_dir:?}"
tar -xzf "$dl/$jdk_tgz" -C "$(dirname "$jdk_dir")"
[[ -x $jdk_dir/bin/java ]] || die "Temurin archive did not unpack to $jdk_dir"
jq '.contributes["acb.java.home"] |= map(sub("/Contents/Home$"; ""))' "$deps/package.json" > "$deps/package.json.new"
mv "$deps/package.json.new" "$deps/package.json"

# --- Node runtime ----------------------------------------------------------------
api=$stage/salesforce.mule-dx-api-component/extension/dist/deps
node_ver=$(awk '/#define NODE_(MAJOR|MINOR|PATCH)_VERSION/ {printf "%s%s", s, $3; s="."}' \
  "$api/node-runtime/include/node/node_version.h")
node_txz=node-v$node_ver-linux-$ARCH.tar.xz
log "fetching Node $node_ver ($ARCH)"
download "https://nodejs.org/dist/v$node_ver/$node_txz" "$dl/$node_txz"
curl -fsSL --retry 3 "https://nodejs.org/dist/v$node_ver/SHASUMS256.txt" | grep " $node_txz\$" > "$dl/$node_txz.sha256"
(cd "$dl" && sha256sum -c --quiet "$node_txz.sha256")
rm -rf "${api:?}/node-runtime" && mkdir "$api/node-runtime"
tar -xJf "$dl/$node_txz" -C "$api/node-runtime" --strip-components=1

# --- acv -----------------------------------------------------------------------
log "building acv ($go_arch)"
[[ -d $dl/acv-src ]] || git clone -q https://github.com/aml-org/amf-custom-validator.git "$dl/acv-src"
git -C "$dl/acv-src" cat-file -e "$acv_commit^{commit}" 2>/dev/null || git -C "$dl/acv-src" fetch -q origin
git -C "$dl/acv-src" -c advice.detachedHead=false checkout -q "$acv_commit"
CGO_ENABLED=0 GOOS=linux GOARCH=$go_arch GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
  go -C "$dl/acv-src" build -trimpath -o "$work/acv" ./cmd/main.go
mod_deps() { go version -m "$1" | awk '$1 == "dep" {print $2, $3}'; }
diff <(mod_deps "$api/acv/acv") <(mod_deps "$work/acv") >&2 ||
  die "the shipped acv was built from different dependencies than commit $acv_commit;\n" \
      "find the matching amf-custom-validator commit and update acv_commit"
mv "$work/acv" "$api/acv/acv"

# --- Checks --------------------------------------------------------------------
# Any macOS binary still in the tree is a new platform-specific payload this script
# doesn't know about. Only allow the places that ship every platform side by side.
leftover=$(find "$stage" -type f -exec file -F $'\t' {} + | awk -F'\t' '/Mach-O/ {print $1}' |
  grep -Ev '/prebuilds/(darwin|ios)-[^/]+/|/lib/boot/tanuki/' || true)
[[ -z $leftover ]] || die "macOS binaries with no Linux replacement:\n$leftover"

if [[ $ARCH == "$host" ]]; then
  "$jdk_dir/bin/java" -version 2>&1 | head -1 >&2
  log "node $("$api/node-runtime/bin/node" --version)"
  "$api/acv/acv" help >/dev/null
fi

# --- Package -------------------------------------------------------------------
for id in "$pack" "${members[@]}"; do
  sed -i "s/TargetPlatform=\"[^\"]*\"/TargetPlatform=\"$target\"/" "$stage/$id/extension.vsixmanifest"
  v=$(jq -r .version "$stage/$id/extension/package.json")
  (cd "$stage/$id" && zip -qrX "$out/$id-$v-$target.vsix" .)
  log "built $out/$id-$v-$target.vsix"
done
rm -rf "${stage:?}"
