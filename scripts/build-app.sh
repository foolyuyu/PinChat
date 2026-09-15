#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
output_dir="${1:-${package_dir}/Release}"
app_dir="${output_dir}/PinChat.app"

cd "$package_dir"
swift build -c release

binary_path="$(swift build -c release --show-bin-path)/PinChat"
test -x "$binary_path"

mkdir -p "$output_dir"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"

ditto "$binary_path" "$app_dir/Contents/MacOS/PinChat"
ditto "$package_dir/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/PinChat"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
