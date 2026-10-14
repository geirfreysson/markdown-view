#!/bin/bash
# Uses the same GitHub secret names as geirfreysson/raynard.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CSC_LINK:?Missing CSC_LINK (base64 Developer ID .p12)}"
: "${CSC_KEY_PASSWORD:?Missing CSC_KEY_PASSWORD}"
: "${APPLE_API_ISSUER:?Missing APPLE_API_ISSUER}"
: "${APPLE_API_KEY_ID:?Missing APPLE_API_KEY_ID}"
: "${APPLE_API_KEY_BASE64:?Missing APPLE_API_KEY_BASE64}"
signing_dir="$(mktemp -d)"
keychain_path="$signing_dir/markdown-view.keychain-db"
keychain_password="$(openssl rand -hex 24)"
security list-keychains -d user > "$signing_dir/previous-keychains.txt"
cleanup() {
    python3 - "$signing_dir" <<'PY'
import pathlib,shlex,subprocess,sys
folder=pathlib.Path(sys.argv[1])
subprocess.run(['security','list-keychains','-d','user','-s',*shlex.split((folder/'previous-keychains.txt').read_text())],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['security','delete-keychain',str(folder/'markdown-view.keychain-db')],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
for name in ['developer-id.p12','api-key.p8']:
 (folder/name).unlink(missing_ok=True)
PY
}
trap cleanup EXIT
printf '%s' "$CSC_LINK" | sed -E 's#^data:[^,]+,##' | base64 --decode > "$signing_dir/developer-id.p12"
printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$signing_dir/api-key.p8"
chmod 600 "$signing_dir/developer-id.p12" "$signing_dir/api-key.p8"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_dir/developer-id.p12" -k "$keychain_path" -P "$CSC_KEY_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" login.keychain-db
identity="$(security find-identity -v -p codesigning "$keychain_path" | sed -nE 's/.*"(Developer ID Application:[^"]+)".*/\1/p' | head -1)"
[[ -n "$identity" ]] || { echo 'No valid Developer ID Application certificate found.' >&2; exit 1; }
app='build/Markdown View.app'
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/mdv-integrate"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements packaging/QuickLook.entitlements "$app/Contents/PlugIns/MarkdownPreview.appex"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
notarize() {
    local target="$1"
    xcrun notarytool submit "$target" --key "$signing_dir/api-key.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait --output-format json > "$signing_dir/result.json"
    if ! python3 - "$signing_dir/result.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]));print('Notarization:',result.get('status','unknown'))
sys.exit(0 if result.get('status')=='Accepted' else 1)
PY
    then
        submission_id="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$signing_dir/result.json")"
        xcrun notarytool log "$submission_id" --key "$signing_dir/api-key.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER"
        return 1
    fi
}
ditto -c -k --keepParent "$app" "$signing_dir/app.zip"
notarize "$signing_dir/app.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
MACOS_SIGNED=1 ./scripts/package.sh
for dmg_path in dist/markdown-view-*-macos-universal.dmg; do
    codesign --force --timestamp --sign "$identity" "$dmg_path"
    notarize "$dmg_path"
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
done
(cd dist && shasum -a 256 markdown-view-* > SHA256SUMS.txt)
