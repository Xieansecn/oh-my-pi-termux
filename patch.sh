#!/usr/bin/env bash
set -euo pipefail
ADDON="${ADDON:-${1:-}}"
if [ -z "$ADDON" ]; then
	echo "patch.sh: provide the downloaded .node via ADDON or first argument" >&2
	exit 1
fi
case "$ADDON" in
	/*) ;;
	*) ADDON="$(pwd -P)/$ADDON" ;;
esac
cd "$(dirname "$0")"
ROOT=$(pwd -P)

if ! OMP_BIN=$(command -v omp); then
	echo "patch.sh: omp not found" >&2
	exit 1
fi
OMP_REAL=$(readlink -f "$OMP_BIN")
if [[ "$OMP_REAL" != */.bun/install/global/* ]]; then
	echo "patch.sh: omp is not a Bun-global install" >&2
	exit 1
fi
if ! PLATFORM=$(bun -e 'process.stdout.write(process.platform)' 2>/dev/null); then
	echo "patch.sh: cannot determine platform with bun" >&2
	exit 1
fi
if [ "$PLATFORM" != android ]; then
	echo "patch.sh: platform is not Android" >&2
	exit 1
fi
if ! N_MAIN=$(bun -e 'const {createRequire}=require("node:module"); process.stdout.write(createRequire(process.argv[1]).resolve("@oh-my-pi/pi-natives"))' "$OMP_REAL" 2>/dev/null); then
	echo "patch.sh: cannot resolve @oh-my-pi/pi-natives from omp" >&2
	exit 1
fi
case "$N_MAIN" in
	*/node_modules/@oh-my-pi/pi-natives/*)
		PKG_ROOT="${N_MAIN%%/node_modules/@oh-my-pi/pi-natives/*}/node_modules/@oh-my-pi/pi-natives"
		;;
	*)
		echo "patch.sh: cannot derive natives package root" >&2
		exit 1
		;;
esac
NATIVE_DIR="$PKG_ROOT/native"
if [ ! -f "$ADDON" ]; then
	echo "patch.sh: addon not found: $ADDON" >&2
	exit 1
fi
for f in loader-state.js desktop-adapter.js desktop.js; do
	if [ ! -f "$ROOT/native/$f" ]; then
		echo "patch.sh: missing native/$f" >&2
		exit 1
	fi
done
if ! PKG_VERSION=$(bun -e 'process.stdout.write(require(process.argv[1]).version)' "$PKG_ROOT/package.json" 2>/dev/null); then
	echo "patch.sh: cannot read installed natives version" >&2
	exit 1
fi
if ! ADDON_VERSION=$(bun -e 'process.stdout.write(require(process.argv[1]).__piNativesBuildVersion())' "$ADDON" 2>/dev/null); then
	echo "patch.sh: cannot read addon version" >&2
	exit 1
fi
if [ "$PKG_VERSION" != "$ADDON_VERSION" ]; then
	echo "patch.sh: version mismatch ($PKG_VERSION vs $ADDON_VERSION)" >&2
	exit 1
fi

install -m 755 "$ADDON" "$NATIVE_DIR/pi_natives.android-arm64.node"
for f in loader-state.js desktop-adapter.js desktop.js; do
	install -m 644 "$ROOT/native/$f" "$NATIVE_DIR/$f"
done
