#!/bin/bash
# Archive DeckTerm, then install it on the deck's iPhone or upload it to TestFlight.
#
#   scripts/release.sh install      # Ad Hoc build onto the iPhone 12 mini over USB (paired, unlocked)
#   scripts/release.sh testflight   # App Store build, uploaded with the App Store Connect API key
#
# Signs from the shared signing keychain (its password is on disk), so it works from a terminal that can't unlock
# the login keychain (codesign: errSecInternalComponent). Same pattern as ayikla/scripts/testflight.sh.
# The build number is the time, so every upload is new.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=RQ96AFW6H2
ISSUER=93179d25-e1b9-4256-941e-27126dcc7ea6
DEVICE=00008101-001E24522190001E   # iPhone 12 mini in the deck, registered on the team
SIGNING_CERT=2632468CDF18C5FAFC4A6C2CC26EC610EAE84922   # SHA-1: the display name isn't unique on this team
KEYCHAIN="$HOME/Library/Keychains/cobanov-signing.keychain-db"
BUILD_NUMBER=${BUILD_NUMBER:-$(date +%y%m%d%H%M)}
case ${1:-} in
  install) PROFILE="DeckTerm Ad Hoc"; METHOD=release-testing ;;
  testflight) PROFILE="DeckTerm App Store"; METHOD=app-store-connect ;;
  *) echo "usage: scripts/release.sh install|testflight" >&2; exit 2 ;;
esac
ARCHIVE=build/release/DeckTerm.xcarchive
EXPORT=build/release/$1

# The shared keychain stays out of the search list otherwise (a locked keychain there makes `security` prompt).
ORIGINAL=$(security list-keychains -d user | tr -d '"')
# shellcheck disable=SC2086
trap 'security list-keychains -d user -s $ORIGINAL' EXIT
security unlock-keychain -p "$(cat "$HOME/.cobanov-signing/.kcpass")" "$KEYCHAIN"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT"
# SwiftTerm runs a build-tool plugin; Xcode asks to trust it once, the command line needs the skip flag.
xcodebuild archive -project DeckTerm.xcodeproj -scheme DeckTerm -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -skipPackagePluginValidation -skipMacroValidation \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" DECKTERM_SIGN_STYLE=Manual DECKTERM_SIGN_IDENTITY="$SIGNING_CERT" \
  DECKTERM_PROFILE="$PROFILE" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" \
  COMPILER_INDEX_STORE_ENABLE=NO -quiet

mkdir -p "$EXPORT"
cat > "$EXPORT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>${METHOD}</string>
  <key>teamID</key><string>6U58AKY6F8</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>${SIGNING_CERT}</string>
  <key>provisioningProfiles</key><dict><key>dev.cobanov.deckterm</key><string>${PROFILE}</string></dict>
  <key>destination</key><string>export</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
# /usr/bin first: Homebrew's rsync breaks export's packaging step ("Copy failed").
PATH="/usr/bin:$PATH" xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$EXPORT/ExportOptions.plist" -quiet
IPA="$EXPORT/DeckTerm.ipa"
echo "built $IPA, build $BUILD_NUMBER ($(du -h "$IPA" | cut -f1))"

if [[ $1 == install ]]; then
  # installation_proxy (brew install ideviceinstaller): an Ad Hoc build needs no Developer Mode, devicectl does.
  ideviceinstaller -u "$DEVICE" install "$IPA"
else
  xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
  echo "uploaded: the build shows in App Store Connect → TestFlight after processing (a few minutes)"
fi
