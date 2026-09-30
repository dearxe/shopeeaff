#!/bin/bash
set -euo pipefail
# Never enable shell tracing: signing material is provided through environment secrets.
: "${APPLE_TEAM_ID:?Set the APPLE_TEAM_ID environment variable in GitHub}"
: "${SIGNING_CERTIFICATE_BASE64:?Missing Apple distribution certificate}"
: "${SIGNING_PRIVATE_KEY_BASE64:?Missing private key matching the certificate}"
: "${PROVISION_PROFILE_BASE64:?Missing App Store provisioning profile}"
mkdir -p artifacts/export
SIGNING_DIR=$(mktemp -d "$RUNNER_TEMP/affiliate-signing.XXXXXX")
KEYCHAIN_PATH="$SIGNING_DIR/build.keychain-db"
PROFILE_INSTALLED=""
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  if [ -n "$PROFILE_INSTALLED" ]; then rm -f "$PROFILE_INSTALLED"; fi
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
printf '%s' "$SIGNING_CERTIFICATE_BASE64" | base64 --decode > "$SIGNING_DIR/distribution.cer"
printf '%s' "$SIGNING_PRIVATE_KEY_BASE64" | base64 --decode > "$SIGNING_DIR/distribution.key"
printf '%s' "$PROVISION_PROFILE_BASE64" | base64 --decode > "$SIGNING_DIR/profile.mobileprovision"
security cms -D -i "$SIGNING_DIR/profile.mobileprovision" > "$SIGNING_DIR/profile.plist"
export SIGNING_DIR
python3 - <<'PY'
import os, plistlib, datetime
from pathlib import Path
path = Path(os.environ['SIGNING_DIR'])
profile = plistlib.loads((path / 'profile.plist').read_bytes())
team = os.environ['APPLE_TEAM_ID']
assert team in profile['TeamIdentifier'], 'Profile belongs to another team'
identifier = profile['Entitlements']['application-identifier']
assert identifier.split('.', 1)[1] == 'com.simplelifesolution.affiliatehelper', 'Wrong Bundle ID in profile'
assert not profile.get('ProvisionedDevices'), 'Use an App Store profile, not development/ad hoc'
assert not profile.get('ProvisionsAllDevices'), 'Do not use an enterprise profile'
assert not profile['Entitlements'].get('get-task-allow', False), 'Debug profile is not valid for distribution'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Profile expired'
(path / 'profile-uuid').write_text(profile['UUID'])
options = {'method': 'app-store-connect', 'destination': 'export', 'teamID': team,
           'signingStyle': 'manual', 'signingCertificate': 'Apple Distribution',
           'provisioningProfiles': {'com.simplelifesolution.affiliatehelper': profile['UUID']}}
(path / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
PROFILE_UUID=$(cat "$SIGNING_DIR/profile-uuid")
PROFILE_INSTALLED="$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
mkdir -p "$(dirname "$PROFILE_INSTALLED")"
cp "$SIGNING_DIR/profile.mobileprovision" "$PROFILE_INSTALLED"
openssl x509 -inform DER -in "$SIGNING_DIR/distribution.cer" -out "$SIGNING_DIR/distribution.pem"
P12_PASSWORD=$(openssl rand -hex 24)
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$P12_PASSWORD"
echo "::add-mask::$KEYCHAIN_PASSWORD"
export P12_PASSWORD
openssl pkcs12 -export -inkey "$SIGNING_DIR/distribution.key" -in "$SIGNING_DIR/distribution.pem" \
  -out "$SIGNING_DIR/distribution.p12" -passout env:P12_PASSWORD
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_DIR/distribution.p12" -k "$KEYCHAIN_PATH" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"
xcodebuild -project LinkAff.xcodeproj -scheme LinkAff -configuration Release \
  -destination 'generic/platform=iOS' -archivePath artifacts/AffiliateHelper.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
  archive
xcodebuild -exportArchive -archivePath artifacts/AffiliateHelper.xcarchive \
  -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -exportPath artifacts/export
if [ "${UPLOAD_TO_TESTFLIGHT:-false}" = 'true' ]; then
  : "${ASC_KEY_ID:?Missing App Store Connect key ID}"
  : "${ASC_ISSUER_ID:?Missing App Store Connect issuer ID}"
  : "${ASC_PRIVATE_KEY_BASE64:?Missing App Store Connect private key}"
  mkdir -p "$SIGNING_DIR/private_keys"
  printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$SIGNING_DIR/private_keys/AuthKey_$ASC_KEY_ID.p8"
  export API_PRIVATE_KEYS_DIR="$SIGNING_DIR/private_keys"
  IPA_PATH=$(find artifacts/export -maxdepth 1 -name '*.ipa' -print -quit)
  test -n "$IPA_PATH"
  xcrun altool --validate-app -f "$IPA_PATH" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app -f "$IPA_PATH" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
