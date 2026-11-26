#!/usr/bin/env bash
set -euo pipefail

die() {
	printf 'patch.sh: %s\n' "$*" >&2
	exit 1
}

readonly BIONIC_ERR='requires native Termux/Android arm64 with Bionic libc (not Linux/glibc, macOS, proot, or non-arm64)'

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
readonly ROOT

# Only user-selected artifact path: the downloaded .node, resolved before cd.
resolve_addon() {
	ADDON="${ADDON:-${1:-}}"
	if [[ -z "$ADDON" ]]; then
		die "provide the downloaded .node via ADDON or first argument"
	fi
	case "$ADDON" in
		/*) ;;
		*) ADDON="$(pwd -P)/$ADDON" ;;
	esac
}

# omp is derived from PATH; no user input needed. Capability checks replace path assumptions.
require_omp() {
	local omp
	if ! omp=$(command -v omp 2>/dev/null); then
		die "omp not found in PATH"
	fi
	if ! OMP_BIN=$(readlink -f "$omp" 2>/dev/null); then
		die "cannot resolve omp path: $omp"
	fi
	if [[ ! -f "$OMP_BIN" || ! -x "$OMP_BIN" ]]; then
		die "omp is not executable: $OMP_BIN"
	fi
}

# JS patch files ship in this repo, so the source dir is fixed; no user input needed.
require_native_dir() {
	NATIVE_DIR="$ROOT/native"
	if [[ ! -d "$NATIVE_DIR" ]]; then
		die "native dir not found: $NATIVE_DIR"
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

# Resolve both packages from omp by capability; no user input or path substring needed.
resolve_install_dir() {
	local cli_pkg natives_pkg
	if ! cli_pkg=$(bun -e 'const {createRequire}=require("node:module"); process.stdout.write(createRequire(process.argv[1]).resolve("@oh-my-pi/pi-coding-agent/package.json"))' "$OMP_BIN" 2>/dev/null); then
		die "cannot resolve @oh-my-pi/pi-coding-agent from omp"
	fi
	if ! natives_pkg=$(bun -e 'const {createRequire}=require("node:module"); process.stdout.write(createRequire(process.argv[1]).resolve("@oh-my-pi/pi-natives/package.json"))' "$OMP_BIN" 2>/dev/null); then
		die "cannot resolve @oh-my-pi/pi-natives from omp"
	fi
	CLI_ROOT="${cli_pkg%/package.json}"
	PKG_ROOT="${natives_pkg%/package.json}"
	INSTALL_DIR="$PKG_ROOT/native"
	if [[ ! -d "$INSTALL_DIR" ]]; then
		die "natives install dir not found: $INSTALL_DIR"
	fi
}

require_inputs() {
	local f
	if [[ ! -f "$ADDON" ]]; then
		die "addon not found: $ADDON"
	fi
	for f in loader-state.js desktop-adapter.js desktop.js; do
		if [[ ! -f "$NATIVE_DIR/$f" ]]; then
			die "missing $f in source native dir: $NATIVE_DIR/$f"
		fi
	done
}

require_version_match() {
	local cli_version pkg_version addon_version
	if ! cli_version=$(bun -e 'process.stdout.write(require(process.argv[1]).version)' "$CLI_ROOT/package.json" 2>/dev/null); then
		die "cannot read installed CLI version"
	fi
	if ! pkg_version=$(bun -e 'process.stdout.write(require(process.argv[1]).version)' "$PKG_ROOT/package.json" 2>/dev/null); then
		die "cannot read installed natives version"
	fi
	if ! addon_version=$(bun -e 'process.stdout.write(require(process.argv[1]).__piNativesBuildVersion())' "$ADDON" 2>/dev/null); then
		die "cannot read addon version"
	fi
	if [[ "$cli_version" != "$pkg_version" || "$pkg_version" != "$addon_version" ]]; then
		die "version mismatch (CLI $cli_version vs natives $pkg_version vs addon $addon_version)"
	fi
}

install_files() {
	local f
	install -m 755 "$ADDON" "$INSTALL_DIR/pi_natives.android-arm64.node"
	for f in loader-state.js desktop-adapter.js desktop.js; do
		install -m 644 "$NATIVE_DIR/$f" "$INSTALL_DIR/$f"
	done
}

main() {
	resolve_addon "$@"
	require_omp
	require_native_dir
	cd "$(dirname "$0")"
	require_android_bionic
	resolve_install_dir
	require_inputs
	require_version_match
	install_files
}

main "$@"
