#!/bin/bash
# Pinned, reproducible Ghostty build. Outputs are disposable and ignored by Git.
set -euo pipefail
cd "$(dirname "$0")/.."
revision=6ba144158577d033ccb6ed4b574e4013957c9161
zig_version=0.17.0
mkdir -p build/deps build/ghostty
root="$PWD"
source_dir="$root/build/deps/ghostty"
if [[ ! -d "$source_dir/.git" ]]; then
    git clone --filter=blob:none --no-checkout https://github.com/ghostty-org/ghostty.git "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" || ! -f "$source_dir/build.zig" ]]; then
    git -C "$source_dir" fetch origin "$revision"
    git -C "$source_dir" checkout --detach "$revision"
fi
# The patch is deliberately maintained here rather than following upstream main.
if git -C "$source_dir" apply --check "$root/patches/ghostty-runtime-metal.patch" 2>/dev/null; then
    git -C "$source_dir" apply "$root/patches/ghostty-runtime-metal.patch"
elif ! git -C "$source_dir" apply --reverse --check "$root/patches/ghostty-runtime-metal.patch"; then
    echo 'Ghostty source does not match the pinned patch.' >&2; exit 1
fi
if [[ -n "${ZIG:-}" ]]; then
    zig_bin="$ZIG"
else
    case "$(uname -m)" in
        arm64) zig_arch=aarch64; checksum=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a ;;
        x86_64) zig_arch=x86_64; checksum=4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6 ;;
        *) echo 'Unsupported macOS build architecture.' >&2; exit 1 ;;
    esac
    zig_dir="zig-${zig_arch}-macos-${zig_version}"
    zig_bin="$root/build/deps/$zig_dir/zig"
    if [[ ! -x "$zig_bin" ]]; then
        archive="$root/build/deps/$zig_dir.tar.xz"
        curl --fail --location --retry 3 "https://ziglang.org/download/$zig_version/$zig_dir.tar.xz" -o "$archive"
        echo "$checksum  $archive" | shasum -a 256 --check
        tar -xf "$archive" -C "$root/build/deps"
    fi
fi
[[ "$("$zig_bin" version)" == "$zig_version" ]] || { echo "Zig $zig_version required." >&2; exit 1; }
# Build a universal archive only when requested by the app build.
target=native
if [[ "${ARCH_FLAGS:-}" == *arm64* && "${ARCH_FLAGS:-}" == *x86_64* ]]; then target=universal; fi
cd "$source_dir"
architectures="$(uname -m)"
if [[ "$target" == universal ]]; then architectures="arm64 x86_64"; fi
archives=()
for architecture in $architectures; do
    zig_target=aarch64-macos
    if [[ "$architecture" == x86_64 ]]; then zig_target=x86_64-macos; fi
    prefix="$root/build/ghostty/$architecture"
    "$zig_bin" build -Doptimize=ReleaseFast -Dstrip -Dtarget="$zig_target" \
        -Demit-xcframework=false -Demit-macos-app=false -Demit-docs=false \
        -Demit-themes=false -Dsentry=false -Di18n=false --prefix "$prefix"
    archives+=("$prefix/lib/libghostty-internal.a")
done
lipo -create "${archives[@]}" -output "$root/build/ghostty/libghostty.a"
cp include/ghostty.h "$root/build/ghostty/ghostty.h"
mkdir -p "$root/build/ghostty/resources" "$root/build/ghostty/licenses"
ditto "$prefix/share" "$root/build/ghostty/resources"
cp LICENSE "$root/build/ghostty/licenses/Ghostty.txt"
# Preserve dependency notice paths, including bundled fonts and C libraries.
python3 - "$source_dir" "$root/build/ghostty/licenses" <<'PYNOTICES'
from pathlib import Path
import re, shutil, sys
source, destination = map(Path, sys.argv[1:])
for folder in ('vendor', 'zig-pkg', 'pkg'):
    for path in (source / folder).rglob('*'):
        if path.is_file() and re.match(r'^(LICENSE|COPYING|NOTICE|OFL|FTL)([._-]|$)', path.name, re.I):
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
PYNOTICES
printf '%s\n%s\n' "$revision" "$target" > "$root/build/ghostty/stamp"
rm -f "$root/build/ghostty/native.stamp" "$root/build/ghostty/universal.stamp"
cp "$root/build/ghostty/stamp" "$root/build/ghostty/$target.stamp"
