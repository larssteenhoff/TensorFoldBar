#!/bin/bash
set -euo pipefail
runtime="$1"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
curl --fail --location --silent --show-error --retry 2 https://api.github.com/repos/ashhart/TensorFold/releases/latest -o "$scratch/release.json"
/usr/bin/ruby -rjson -e '
r = JSON.parse(File.read(ARGV[0]))
assets = r.fetch("assets")
a = assets.find { |x| x["name"].match?(/\Atensorfold-[0-9][A-Za-z0-9.\-]*-macos-arm64\.tar\.gz\z/) }
abort "No Apple Silicon archive in latest release" unless a
c = assets.find { |x| x["name"] == a["name"] + ".sha256" }
abort "Release has no checksum" unless c
[a,c].each { |x| abort "Unexpected download host" unless x["browser_download_url"].start_with?("https://github.com/ashhart/TensorFold/releases/download/") }
File.write(ARGV[1], [a["name"], a["browser_download_url"], c["browser_download_url"]].join("\n") + "\n")
' "$scratch/release.json" "$scratch/assets"
{ read -r archive; read -r archive_url; read -r checksum_url; } < "$scratch/assets"
curl --fail --location --silent --show-error --retry 2 "$archive_url" -o "$scratch/$archive"
curl --fail --location --silent --show-error --retry 2 "$checksum_url" -o "$scratch/checksum"
expected=$(awk 'NR==1 {print $1}' "$scratch/checksum")
actual=$(shasum -a 256 "$scratch/$archive" | awk '{print $1}')
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ && "$actual" == "$expected" ]] || { echo 'Checksum mismatch; existing engine retained.'; exit 1; }
mkdir "$scratch/unpack"
tar -xzf "$scratch/$archive" -C "$scratch/unpack"
engine="$scratch/unpack/${archive%.tar.gz}"
test -x "$engine/bin/tensorfold-native"
"$engine/bin/tensorfold-native" --version
# Stage beside the original so replacement is on the same filesystem.
test ! -e "$runtime.new"
ditto "$engine" "$runtime.new"
if ! mv "$runtime" "$runtime.previous"; then rm -rf "$runtime.new"; exit 1; fi
if ! mv "$runtime.new" "$runtime"; then mv "$runtime.previous" "$runtime"; exit 1; fi
rm -rf "$runtime.previous"
echo 'TensorFold update complete. Click Start TensorFold.'
