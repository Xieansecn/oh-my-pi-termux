#!/usr/bin/env bash
set -euo pipefail

SRC="$HOME/tmp/omp-android-src"
ADDON="$SRC/packages/natives/native/android-build/pi_natives.android-arm64.node"
OMP="$(readlink -f "$(command -v omp)")"
N_INDEX="$(node -e 'const {createRequire}=require("node:module"); console.log(createRequire(process.argv[1]).resolve("@oh-my-pi/pi-natives"))' "$OMP")"
N="$(dirname "$N_INDEX")"
VERSION="$(node -p "require('$N/../package.json').version")"
BACKUP="$HOME/.cache/omp-android/natives-backup-$VERSION-$(date +%Y%m%d-%H%M%S)"
FILES=(loader-state.js desktop-adapter.js desktop.js)
INSTALLED=0
HAD_ADDON=0
SMOKE_DIR=""

[[ "$(node -p 'process.platform')" == android ]] || { echo "Run this in Termux." >&2; exit 1; }
[[ -f "$ADDON" ]] || { echo "Missing $ADDON; run ~/bin/omp-android-build.sh first." >&2; exit 1; }
[[ "$(node -p "require('$SRC/packages/natives/package.json').version")" == "$VERSION" ]] || {
  echo "Source natives version does not match installed $VERSION; rebuild from the matching tag." >&2
  exit 1
}

bun -e '
const a = require(process.argv[1]);
if (a.__piNativesBuildVersion() !== process.argv[2]) throw new Error("addon version mismatch");
console.log(`addon probe: ${Object.keys(a).length} exports, v${a.__piNativesBuildVersion()}`);
' "$ADDON" "$VERSION"

on_exit() {
  local rc=$?
  if [[ $rc -ne 0 && $INSTALLED -eq 1 ]]; then
    echo "Smoke test failed; restoring $BACKUP" >&2
    for file in "${FILES[@]}"; do cp -a "$BACKUP/$file" "$N/$file"; done
    if [[ $HAD_ADDON -eq 1 ]]; then
      cp -a "$BACKUP/pi_natives.android-arm64.node" "$N/pi_natives.android-arm64.node"
    else
      rm -f "$N/pi_natives.android-arm64.node"
    fi
  fi
  if [[ -n $SMOKE_DIR ]]; then rm -rf "$SMOKE_DIR"; fi
}
trap on_exit EXIT

mkdir -p "$BACKUP"
for file in "${FILES[@]}"; do cp -a "$N/$file" "$BACKUP/$file"; done
if [[ -f "$N/pi_natives.android-arm64.node" ]]; then
  cp -a "$N/pi_natives.android-arm64.node" "$BACKUP/"
  HAD_ADDON=1
fi

INSTALLED=1
for file in "${FILES[@]}"; do cp -a "$SRC/packages/natives/native/$file" "$N/$file"; done
install -m 755 "$ADDON" "$N/pi_natives.android-arm64.node"

omp --version
omp --help >/dev/null
SMOKE_DIR="$(mktemp -d "$HOME/.cache/omp-android/smoke.XXXXXX")"
printf 'omp-android-ok\n' > "$SMOKE_DIR/sample.txt"
SMOKE_DIR="$SMOKE_DIR" N="$N/.." EXPECTED_VERSION="$VERSION" bun -e '
import assert from "node:assert/strict";
const n = await import(process.env.N);
const dir = process.env.SMOKE_DIR;
assert.equal(n.__piNativesBuildVersion(), process.env.EXPECTED_VERSION);
assert.ok(n.countTokens("omp android") > 0);
const grep = await n.grep({ pattern: "omp-android-ok", path: dir });
assert.equal(grep.totalMatches, 1);
const glob = await n.glob({ pattern: "*.txt", path: dir });
assert.equal(glob.matches.length, 1);
let output = "";
const shell = await n.executeShell({ command: "printf omp-shell-ok", cwd: dir }, (error, chunk) => {
  if (error) throw error;
  output += chunk;
});
assert.equal(shell.exitCode, 0);
assert.ok(output.includes("omp-shell-ok"));
const store = new n.EditStore();
store.recordSnapshot(`${dir}/sample.txt`, "omp-edit-ok");
assert.equal(store.headText(`${dir}/sample.txt`), "omp-edit-ok");
console.log("native smoke: grep, glob, shell, EditStore, tokenizer OK");
'
echo "Installed Android addon into $N"
echo "Backup: $BACKUP"
