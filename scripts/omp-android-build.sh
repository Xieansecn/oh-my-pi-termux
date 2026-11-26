#!/usr/bin/env bash
set -euo pipefail

SRC="${SRC:-$HOME/tmp/omp-android-src}"
NAPI="$HOME/.cache/omp-android/tools/node_modules/.bin/napi"
OUT="$SRC/packages/natives/native/android-build"
ADDON="$OUT/pi_natives.android-arm64.node"

cd "$SRC/crates/natives"
rm -rf "$OUT"
mkdir -p "$OUT"

CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" \
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

llvm-strip --strip-unneeded "$ADDON"
bun "$SRC/scripts/stamp-native-version.ts" "$ADDON"
bun -e 'const a = require(process.argv[1]); console.log(`loaded ${Object.keys(a).length} exports; version=${a.__piNativesBuildVersion()}`)' "$ADDON"
