A lightweight, native Markdown viewer for macOS and Linux.

- **macOS:** Download the universal `.dmg` (Apple Silicon and Intel; macOS 12+). Open it and run `install.command` to install in `~/Applications`, make Markdown View the default Markdown opener, and register the Quick Look extension. Enable **Markdown Preview** under System Settings → General → Login Items & Extensions → Quick Look if macOS asks. The `.zip` contains just the app for manual installation.
- **Debian / Ubuntu Linux (x86_64):** Download the `.deb`, then run `sudo apt install ./markdown-view-*-linux-amd64.deb`.
- **Other Linux distributions (x86_64):** Download the `.tar.gz`. GTK 3 and GLib 2.66+ are required; the binary is built on Ubuntu 22.04 and requires glibc 2.34+.

These community macOS builds are ad hoc signed and are not Apple-notarized. macOS may require an explicit Open / Open Anyway approval for a downloaded app or installer. Quick Look activation depends on macOS accepting and enabling the bundled extension.

Includes headings, emphasis, lists, read-only tasks, quotes, code, basic tables, links, local images, search, and zoom. Raw HTML is displayed as text; remote images are linked descriptions.

`SHA256SUMS.txt` contains checksums for every download.
