#!/usr/bin/env bash
# macOS arm64 unsigned release candidate for SliceApp (right-git release-candidate lane, runs on the mac runner).
#   build  swift build -c release, assemble dist/mac/SliceApp.app (no signing), build the UDZO DMG headless (right-release dmg build)
#   check  hdiutil verify, mount read-only, check the app bundle structure, Mach-O arch, Info.plist identity, and that nothing is signed
# Nothing here signs or notarizes. Developer ID signing and notarization belong to the macos-sign job (protected `release`
# environment secrets), which is not provisioned yet.
set -euo pipefail
action="${1:-}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
app_dir="$repo/examples/SliceApp"
out_root="${RIGHT_GIT_ARTIFACT_ROOT:?RIGHT_GIT_ARTIFACT_ROOT is not set}"
dest="$out_root/sliceapp/macos/arm64"
rr="$repo/node_modules/@rightkit/release/cli/right-release.mjs"
dmg="$app_dir/dist/mac/SliceApp_0.1.0_arm64.dmg"
app="$app_dir/dist/mac/SliceApp.app"

case "$action" in
  build)
    [[ -f "$rr" ]] || { echo "::error::right-release not installed at $rr (pnpm install at the repository root)"; exit 1; }
    cd "$app_dir"
    xcodebuild -version || true
    swift --version
    swift build -c release
    node "$rr" swift-package mac-app --config swift-package.json
    node "$rr" dmg build --app "$app" --out "$dmg" --volname SliceApp --background Mac/dmg/background.tiff \
      --icon-size 128 --app-position 158,231 --applications-position 492,231 --window 660,400
    mkdir -p "$dest"
    cp "$dmg" "$dest/"
    swift_version="$(swift --version 2>&1 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
    cat > "$dest/build-identity.json" <<JSON
{
  "schema": 1,
  "sourceRevision": "${RIGHT_GIT_SOURCE_REVISION:-}",
  "platform": "macos", "architecture": "arm64", "signed": false,
  "swiftVersion": $swift_version,
  "dmgSha256": "$(shasum -a 256 "$dmg" | cut -d' ' -f1)",
  "dmgBytes": $(stat -f %z "$dmg"),
  "executableSha256": "$(shasum -a 256 "$app/Contents/MacOS/SliceApp" | cut -d' ' -f1)"
}
JSON
    cat "$dest/build-identity.json"
    ;;
  check)
    cand="$dest/SliceApp_0.1.0_arm64.dmg"
    [[ -f "$cand" ]] || { echo "::error::candidate DMG missing: $cand"; exit 1; }
    expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["dmgSha256"])' "$dest/build-identity.json")"
    actual="$(shasum -a 256 "$cand" | cut -d' ' -f1)"
    [[ "$expected" == "$actual" ]] || { echo "::error::DMG sha256 $actual differs from build identity $expected"; exit 1; }
    hdiutil verify "$cand"
    mnt="$(mktemp -d "${RUNNER_TEMP:-/tmp}/sliceapp-dmg-XXXXXX")"
    # Bounded detach (retry, then -force) owned by RightKit hdiutil-detach.mjs; attach stays a raw call (no RightKit attach helper).
    cleanup() {
      MOUNT="$mnt" RK_RELEASE="$repo/node_modules/@rightkit/release" node --input-type=module -e '
        import { spawnSync } from "node:child_process";
        import { pathToFileURL } from "node:url";
        const { detachWithRetrySync } = await import(pathToFileURL(process.env.RK_RELEASE + "/hdiutil-detach.mjs").href);
        const r = detachWithRetrySync({ mount: process.env.MOUNT, detach: (args) => spawnSync("hdiutil", args, { encoding: "utf8" }), log: (e) => console.error(JSON.stringify(e)) });
        process.exit(r.ok ? 0 : 1);
      ' >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
    hdiutil attach "$cand" -readonly -nobrowse -noautoopen -mountpoint "$mnt"
    mapp="$mnt/SliceApp.app"
    for f in Contents/Info.plist Contents/MacOS/SliceApp; do [[ -e "$mapp/$f" ]] || { echo "::error::DMG app lacks $f"; exit 1; }; done
    [[ -L "$mnt/Applications" ]] || { echo "::error::DMG lacks the Applications link"; exit 1; }
    plutil -lint "$mapp/Contents/Info.plist"
    [[ "$(plutil -extract CFBundleIdentifier raw "$mapp/Contents/Info.plist")" == "dev.orthic.sliceapp" ]] || { echo "::error::wrong CFBundleIdentifier"; exit 1; }
    [[ "$(plutil -extract CFBundleShortVersionString raw "$mapp/Contents/Info.plist")" == "0.1.0" ]] || { echo "::error::wrong version"; exit 1; }
    arch="$(lipo -archs "$mapp/Contents/MacOS/SliceApp")"
    [[ "$arch" == "arm64" ]] || { echo "::error::executable architecture is '$arch', expected arm64"; exit 1; }
    sig="$(codesign -dv --verbose=2 "$mapp" 2>&1 || true)"
    echo "$sig"
    if grep -q "Authority=" <<<"$sig"; then echo "::error::the candidate app carries a signing authority; this lane must be unsigned"; exit 1; fi
    if grep -q "TeamIdentifier=[A-Z0-9]" <<<"$sig"; then echo "::error::the candidate app carries a team identifier"; exit 1; fi
    echo "unsigned DMG candidate ok: sha256 $actual, arm64, dev.orthic.sliceapp 0.1.0"
    ;;
  *) echo "usage: mac-candidate.sh build|check" >&2; exit 2 ;;
esac
