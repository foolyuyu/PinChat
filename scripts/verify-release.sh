#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
output_dir="${1:-${package_dir}/Release}"
app_dir="${output_dir}/PinChat.app"
baseline="${output_dir}/REQUIREMENTS_BASELINE_v1.0.md"
baseline_checksum="${output_dir}/REQUIREMENTS_BASELINE_v1.0.sha256"

cd "$package_dir"
swift test
"$script_dir/build-app.sh" "$output_dir"

test -x "$app_dir/Contents/MacOS/PinChat"
plutil -lint "$app_dir/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_dir/Contents/Info.plist")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_dir/Contents/Info.plist")" = "14.0"
codesign --verify --deep --strict "$app_dir"

test -r "$baseline"
test -r "$baseline_checksum"
(
    cd "$output_dir"
    shasum -a 256 -c "${baseline_checksum:t}"
)

echo "PinChat release verification passed: $app_dir"
