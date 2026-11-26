#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd -P)

ADDON="${ADDON:-${1:-}}"
if [ -z "$ADDON" ]; then
	echo "patch.sh: provide the downloaded .node via ADDON or first argument" >&2
	exit 1
fi

OMP_BIN=$(command -v omp) || {
	echo "patch.sh: omp not found" >&2
	exit 1
}
OMP_REAL=$(readlink -f "$OMP_BIN")
if [[ "$OMP_REAL" != */.bun/install/global/* ]]; then
	echo "patch.sh: omp is not a Bun-global install" >&2
	exit 1
fi
if [ "$(node -p process.platform)" != android ]; then
	echo "patch.sh: platform is not Android" >&2
	exit 1
fi
N_PKG=$(node -e 'process.stdout.write(require.resolve("@oh-my-pi/pi-natives/package.json",{paths:[process.argv[1]]}))' "$(dirname "$OMP_REAL")") || {
	echo "patch.sh: cannot resolve @oh-my-pi/pi-natives from omp" >&2
	exit 1
}
N=$(dirname "$N_PKG")
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
PKG_VERSION=$(node -p 'require(process.argv[1]).version' "$N_PKG")
ADDON_VERSION=$(node -e 'process.stdout.write(require(process.argv[1]).__piNativesBuildVersion())' "$ADDON")
if [ "$PKG_VERSION" != "$ADDON_VERSION" ]; then
	echo "patch.sh: version mismatch ($PKG_VERSION vs $ADDON_VERSION)" >&2
	exit 1
fi

install -m 755 "$ADDON" "$N/pi_natives.android-arm64.node"
for f in loader-state.js desktop-adapter.js desktop.js; do
	install -m 644 "$ROOT/native/$f" "$N/$f"
done
