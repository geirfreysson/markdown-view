#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo_dir="$PWD"
version="${VERSION:-0.3.0}"
mkdir -p dist
if [[ "$(uname -s)" == Darwin ]]; then
    if [[ "${MACOS_SIGNED:-0}" == 1 ]]; then
        echo 'macOS app and DMG: Developer ID signed, Apple notarized, and stapled.' > dist/MACOS_SIGNING.txt
    else
        echo 'macOS app: ad hoc signed; not Apple notarized. Explicit macOS approval may be required.' > dist/MACOS_SIGNING.txt
    fi
    stage="$(mktemp -d)"
    ditto 'build/Markdown View.app' "$stage/Markdown View.app"
    cp scripts/install-macos.sh "$stage/install.command"
    chmod +x "$stage/install.command"
    cp README.md "$stage/README.md"
    mkdir -p "$stage/licenses"
    cp vendor/md4c/LICENSE.md "$stage/licenses/MD4C.md"
    ditto -c -k --sequesterRsrc --keepParent "$stage/Markdown View.app" "dist/markdown-view-${version}-macos-universal.zip"
    # Installer and app side by side in the disk image; install.command also sets Finder integration.
    hdiutil create -volname 'Markdown View' -srcfolder "$stage" -format UDZO -ov "dist/markdown-view-${version}-macos-universal.dmg"
else
    arch="$(uname -m)"
    deb_arch="$(dpkg --print-architecture)"
    stage="$(mktemp -d)"
    install -Dm755 build/markdown-view "$stage/markdown-view/bin/markdown-view"
    install -Dm644 packaging/markdown-view.desktop "$stage/markdown-view/share/applications/markdown-view.desktop"
    cp README.md "$stage/markdown-view/README.md"
    mkdir -p "$stage/markdown-view/licenses"
    cp vendor/md4c/LICENSE.md "$stage/markdown-view/licenses/MD4C.md"
    tar -C "$stage" -czf "dist/markdown-view-${version}-linux-${arch}.tar.gz" markdown-view
    deb_stage="$(mktemp -d)"
    make install DESTDIR="$deb_stage" PREFIX=/usr
    mkdir -p "$deb_stage/DEBIAN" "$deb_stage/usr/share/doc/markdown-view"
    cp vendor/md4c/LICENSE.md "$deb_stage/usr/share/doc/markdown-view/MD4C-LICENSE"
    mkdir -p "$stage/debian"
    cat > "$stage/debian/control" <<CONTROL
Source: markdown-view
Section: text
Priority: optional
Maintainer: Geir Freysson <geirfreysson@users.noreply.github.com>

Package: markdown-view
Architecture: any
Description: Lightweight native Markdown viewer
CONTROL
    dependencies="$(cd "$stage" && dpkg-shlibdeps -O "$repo_dir/build/markdown-view" | sed -n 's/^shlibs:Depends=//p')"
    cat > "$deb_stage/DEBIAN/control" <<CONTROL
Package: markdown-view
Version: $version
Architecture: $deb_arch
Maintainer: Geir Freysson <geirfreysson@users.noreply.github.com>
Depends: $dependencies
Section: text
Priority: optional
Homepage: https://github.com/geirfreysson/markdown-view
Description: Lightweight native Markdown viewer
 A read-only GTK Markdown viewer with search, zoom, links, and local images.
CONTROL
    dpkg-deb --root-owner-group --build "$deb_stage" "dist/markdown-view-${version}-linux-${deb_arch}.deb"
fi
(cd dist && shasum -a 256 markdown-view-* > SHA256SUMS.txt)
