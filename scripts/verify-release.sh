#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
output_dir="${1:-${package_dir}/Release}"
app_dir="${output_dir}/PinChat.app"
baseline="${output_dir}/REQUIREMENTS_BASELINE_v1.0.md"
baseline_checksum="${output_dir}/REQUIREMENTS_BASELINE_v1.0.sha256"
optimization_baseline="${output_dir}/OPTIMIZATION_REQUIREMENTS_BASELINE_v1.1.md"
optimization_baseline_checksum="${output_dir}/OPTIMIZATION_REQUIREMENTS_BASELINE_v1.1.sha256"
product_baseline="${output_dir}/PRODUCT_REQUIREMENTS_BASELINE_v2.0.md"
product_baseline_checksum="${output_dir}/PRODUCT_REQUIREMENTS_BASELINE_v2.0.sha256"
visual_baseline="${output_dir}/VISUAL_OPTIMIZATION_REQUIREMENTS_BASELINE_v2.1.md"
visual_baseline_checksum="${output_dir}/VISUAL_OPTIMIZATION_REQUIREMENTS_BASELINE_v2.1.sha256"

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
test -r "$optimization_baseline"
test -r "$optimization_baseline_checksum"
test -r "$product_baseline"
test -r "$product_baseline_checksum"
test -r "$visual_baseline"
test -r "$visual_baseline_checksum"
(
    cd "$output_dir"
    shasum -a 256 -c "${baseline_checksum:t}"
    shasum -a 256 -c "${optimization_baseline_checksum:t}"
    shasum -a 256 -c "${product_baseline_checksum:t}"
    shasum -a 256 -c "${visual_baseline_checksum:t}"
)

echo "PinChat release verification passed: $app_dir"
