#!/usr/bin/env bash
set -euo pipefail

die() {
	printf 'build.sh: %s\n' "$*" >&2
	exit 1
}

readonly BIONIC_ERR='requires native Termux/Android arm64 with Bionic libc (not Linux/glibc, macOS, proot, or non-arm64)'

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# Product source; override UPSTREAM_REPO for a fork that carries the same patch.
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/can1357/oh-my-pi.git}"
# Bundled patch targets v19.2.1; override UPSTREAM_REF only for a matching ref.
UPSTREAM_REF="${UPSTREAM_REF:-v19.2.1}"
# Repo-local build cache keeps rebuilds idempotent; override SRC to share a checkout.
SRC="${SRC:-$ROOT/.build/oh-my-pi}"
# Explicit NAPI wins; PATH shim is next on Termux, then the known cached tool path.
if [[ -z "${NAPI:-}" ]]; then
	if command -v napi >/dev/null 2>&1; then
		NAPI="$(command -v napi)"
	else
		NAPI="$HOME/.cache/omp-android/tools/node_modules/.bin/napi"
	fi
fi
# Derived from SRC so one override moves source and output; override OUT independently if needed.
OUT="${OUT:-$SRC/packages/natives/native/android-build}"
# Shipped with this repo and tied to UPSTREAM_REF; not user-selectable.
PATCH="$ROOT/patches/android-bionic-build-v19.2.1.patch"
# Product artifact filename in OUT; derived from OUT.
ADDON="$OUT/pi_natives.android-arm64.node"

readonly ROOT
readonly UPSTREAM_REPO
readonly UPSTREAM_REF
readonly SRC
readonly NAPI
readonly OUT
readonly PATCH
readonly ADDON

preflight() {
	local tool
	if [[ ! -x "$NAPI" ]]; then
		die "napi not found: $NAPI"
	fi
	for tool in git bun llvm-strip file readelf; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			die "$tool not found"
		fi
	done
	if [[ ! -f "$PATCH" ]]; then
		die "patch not found: $PATCH"
	fi
}

# Rejects Linux/glibc, macOS, proot and non-arm64 hosts.
require_android_bionic() {
	local prefix platform arch kernel abi linker bun_path bun_info
	if [[ -z "${PREFIX:-}" ]]; then
		die "$BIONIC_ERR"
	fi
	if ! prefix=$(readlink -f "$PREFIX" 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	case "$prefix" in
		/data/data/*/files/usr|/data/user/0/*/files/usr) ;;
		*) die "$BIONIC_ERR" ;;
	esac
	if ! platform=$(bun -e 'process.stdout.write(process.platform)' 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if [[ "$platform" != android ]]; then
		die "$BIONIC_ERR"
	fi
	if ! arch=$(bun -e 'process.stdout.write(process.arch)' 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if [[ "$arch" != arm64 ]]; then
		die "$BIONIC_ERR"
	fi
	if ! kernel=$(uname -o 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if [[ "$kernel" != Android ]]; then
		die "$BIONIC_ERR"
	fi
	if ! command -v getprop >/dev/null 2>&1; then
		die "$BIONIC_ERR"
	fi
	if ! abi=$(getprop ro.product.cpu.abi 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if [[ "$abi" != arm64-v8a ]]; then
		die "$BIONIC_ERR"
	fi
	if [[ ! -e /system/bin/linker64 ]]; then
		die "$BIONIC_ERR"
	fi
	if ! linker=$(readlink -f /system/bin/linker64 2>/dev/null) || [[ ! -x "$linker" ]]; then
		die "$BIONIC_ERR"
	fi
	if ! bun_path=$(command -v bun 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if ! bun_path=$(readlink -f "$bun_path" 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	if ! bun_info=$(file -b -L "$bun_path" 2>/dev/null); then
		die "$BIONIC_ERR"
	fi
	case "$bun_info" in
		*"ELF 64-bit LSB"*) ;;
		*) die "$BIONIC_ERR" ;;
	esac
	case "$bun_info" in
		*"ARM aarch64"*) ;;
		*) die "$BIONIC_ERR" ;;
	esac
	case "$bun_info" in
		*"/system/bin/linker64"*|*"/apex/com.android.runtime/bin/linker64"*) ;;
		*) die "$BIONIC_ERR" ;;
	esac
}

prepare_source() {
	if [[ -d "$SRC" ]] && git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		return
	fi
	if [[ -e "$SRC" && ! -d "$SRC" ]]; then
		die "source path is not a directory: $SRC"
	fi
	if ! git clone --quiet --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_REPO" "$SRC"; then
		die "cannot clone $UPSTREAM_REPO@$UPSTREAM_REF into $SRC"
	fi
}

apply_patch() {
	local patch="$PATCH"
	if ! git -C "$SRC" apply --check --reverse "$patch" >/dev/null 2>&1; then
		if ! git -C "$SRC" diff --quiet; then
			die "dirty worktree: $SRC"
		fi
		if ! git -C "$SRC" diff --cached --quiet; then
			die "dirty index: $SRC"
		fi
		if ! git -C "$SRC" apply --check "$patch" >/dev/null 2>&1; then
			die "patch does not apply to $SRC"
		fi
		if ! git -C "$SRC" apply "$patch" >/dev/null 2>&1; then
			die "cannot apply Android patch to $SRC"
		fi
	fi
	if ! git -C "$SRC" diff --check >/dev/null 2>&1; then
		die "patch introduced whitespace errors"
	fi
}

build_addon() {
	mkdir -p "$OUT"
	(
		cd "$SRC/crates/natives"
		CARGO_BUILD_JOBS=2 \
		CMAKE_POLICY_VERSION_MINIMUM=3.5 \
		PCRE2_SYS_STATIC=1 \
		RUSTC_BOOTSTRAP=1 \
		RUSTFLAGS='-C target-cpu=generic' \
		"$NAPI" build \
			--manifest-path Cargo.toml \
			--package-json-path "$SRC/packages/natives/package.json" \
			--platform \
			--no-js \
			--dts index.d.ts \
			-o "$OUT" \
			--profile local
	)
}

strip_addon() {
	if ! llvm-strip --strip-unneeded "$ADDON"; then
		die "cannot strip addon"
	fi
}

stamp_addon() {
	if ! bun "$SRC/scripts/stamp-native-version.ts" "$ADDON"; then
		die "cannot stamp addon version"
	fi
}

verify_artifact() {
	local info exports src_version addon_version dynamic
	if [[ ! -f "$ADDON" ]]; then
		die "addon not found: $ADDON"
	fi
	if ! info=$(file -b "$ADDON"); then
		die "cannot inspect addon"
	fi
	if [[ "$info" != *"ARM aarch64"* ]]; then
		die "unexpected addon architecture: $info"
	fi
	if ! src_version=$(bun -e 'process.stdout.write(require(process.argv[1]).version)' "$SRC/packages/natives/package.json" 2>/dev/null); then
		die "cannot read source natives version"
	fi
	if ! addon_version=$(bun -e 'process.stdout.write(require(process.argv[1]).__piNativesBuildVersion())' "$ADDON" 2>/dev/null); then
		die "cannot read addon version"
	fi
	if [[ "$addon_version" != "$src_version" ]]; then
		die "version mismatch ($src_version vs $addon_version)"
	fi
	if ! exports=$(bun -e 'const a = require(process.argv[1]); console.log(`loaded ${Object.keys(a).length} exports; version=${a.__piNativesBuildVersion()}`)' "$ADDON"); then
		die "cannot load addon with bun"
	fi
	if ! dynamic=$(readelf -d "$ADDON" 2>/dev/null); then
		die "cannot read addon dynamic section"
	fi
	case "$dynamic" in
		*"[libc.so]"*) ;;
		*) die "addon is not linked against Bionic libc" ;;
	esac
	case "$dynamic" in
		*"libc.so.6"*) die "addon is linked against glibc" ;;
	esac
	printf '%s\n' "$exports"
}

main() {
	cd "$(dirname "$0")"
	preflight
	require_android_bionic
	prepare_source
	apply_patch
	build_addon
	strip_addon
	stamp_addon
	verify_artifact
	printf '%s\n' "$ADDON"
}

main "$@"
