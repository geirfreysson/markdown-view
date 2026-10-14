#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
source_app="${1:-$script_dir/Markdown View.app}"
destination="$HOME/Applications/Markdown View.app"
if [[ ! -d "$source_app/Contents" ]]; then
    echo "Cannot find Markdown View.app at: $source_app" >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
if [[ -e "$destination" && "$source_app" != "$destination" ]]; then
    backup="$HOME/Applications/Markdown View.backup-$(date +%Y%m%d-%H%M%S).app"
    mv "$destination" "$backup"
    echo "Previous installation saved to: $backup"
fi
if [[ "$source_app" != "$destination" ]]; then
    ditto "$source_app" "$destination"
fi
"$destination/Contents/MacOS/mdv-integrate" --install "$destination"
extension="$destination/Contents/PlugIns/MarkdownPreview.appex"
pluginkit -a "$extension"
pluginkit -e use -i io.github.markdownview.viewer.quicklook
qlmanage -r >/dev/null
open "$destination"
echo "Installed: $destination"
echo "Markdown files now open in Markdown View."
echo "Select a Markdown file in Finder and press Space for Quick Look."
echo "If macOS asks, enable Markdown Preview in System Settings → General → Login Items & Extensions → Quick Look."
