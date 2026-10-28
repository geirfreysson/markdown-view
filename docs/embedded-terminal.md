# Embedded editing terminal

On macOS 13 or later, **Edit** opens a Ghostty terminal below the document. Choose Claude Code or Codex on first use. The selected CLI must already be installed; the app does not install agents, store API keys, or submit an initial task. Agent authentication and permission settings remain controlled by the CLI.

By default, new sessions receive the displayed document's absolute path and instructions to use it for otherwise ambiguous document requests, while respecting explicit filenames and the established conversation target. The agent is told to read the latest file from disk and wait for your request. No opening message is submitted, and file contents are not preloaded. The terminal header shows **Editing: filename.md**, with the full path in its tooltip.

Turn this off with **Use the displayed document as agent context** in Settings. The header then shows **Document (context off): filename.md**. The choice applies to new sessions; hide/show preserves the existing session's context. Use Restart to apply changed settings.

Claude receives an appended system instruction. For Codex, the app reads the effective configuration through its local `app-server` config endpoint, preserves existing developer instructions, and adds document context through a per-session override. This starts no model turn and writes no configuration or project instruction files. The adapters use [Claude’s append-system-prompt flag](https://code.claude.com/docs/en/cli-reference#system-prompt-flags) and [Codex’s developer instructions](https://learn.chatgpt.com/docs/config-file/config-reference#developer_instructions). If Codex cannot supply its configuration, the session shows an error instead of replacing instructions blindly; update Codex or disable document context to launch without it.

The terminal starts in the document's folder. Drag the divider to resize it. **Hide** preserves the session; **Edit** reveals it again. **Stop** ends the session and **Restart** starts a fresh one with the current Settings. Closing a document or quitting asks before ending a live session. Final output remains visible after a normal process exit.

**Markdown View → Settings…** selects the default agent and optional executable paths. Blank paths use the login-shell PATH and common installation directories. Changes apply to new sessions. If an agent cannot be found, select its executable using **Choose…** in Settings.

The preview refreshes after saves while an editing session exists, including while hidden. Atomic file replacement is supported. Unreadable or temporarily missing files leave the last readable preview visible, with a status message. The existing source/rendered toggle remains available. Terminal output is not interpreted as Markdown or app commands.

## Build and maintenance

The macOS build downloads Ghostty revision `6ba144158577d033ccb6ed4b574e4013957c9161` and checksum-verified Zig 0.17.0 into `build/deps/`. The first build requires network access and is substantially slower than subsequent builds. The local universal-build dependency and library caches occupied about 3.4 GB; these are developer artifacts and are not shipped. `ZIG=/absolute/path/to/zig` overrides the downloaded compiler; the exact version is required. `make clean` removes the dependency build cache too.

Ghostty's full embedding API is internal. `src/terminal.m` isolates it from the rest of the application. `patches/ghostty-runtime-metal.patch` permits standalone static-library builds and compiles Metal source when the first terminal opens, so full Xcode and the Metal command-line compiler are unnecessary. Upgrade the pinned revision, patch, and tests together.

Only the macOS viewer links Ghostty. Quick Look and the Linux viewer retain their existing renderer dependencies. The app bundles terminfo, shell resources, and dependency license notices. No separate Ghostty installation is required.

```sh
make all test test-native test-terminal
make all test test-native test-terminal ARCH_FLAGS="-arch arm64 -arch x86_64"
./build/test-terminal --agents  # Also launch locally installed CLIs; submit no tasks
```

The terminal tests use an in-memory agent preference and a temporary shell. They exercise working-directory quoting, terminal input, copy/paste, PTY resize, hide/show, independent document windows, file watching, invalid saves, source mode, process cleanup, normal exit, and missing executables. The tests write `build/terminal-preview.png` for visual inspection.

## Footprint

The terminal engine is initialized only after Edit. Ordinary reading creates no terminal surface, agent process, or file watcher. The binary still contains Ghostty's code. A hidden terminal keeps its process and memory; stopping releases the surface, while shared engine caches remain until app exit. Scrollback is limited to approximately 10 MB per session.

Local Apple Silicon measurements, October 2026, using a small Markdown fixture:

| Measurement | Observed |
| --- | --- |
| Previous app bundle, native build | 852 KB |
| Embedded-terminal app bundle, universal build | About 35 MB |
| Compressed universal app ZIP | About 14 MB |
| Viewer process before opening terminal | About 22 MiB physical footprint |
| Viewer with terminal and shell, including screenshot capture | About 175–190 MiB physical footprint |
| Idle terminal + shell over two seconds | About 1% of one CPU core |

The terminal measurement includes Metal rendering, shader initialization, and AppKit screenshot buffers. It excludes the shell and agent child-process memory. Agent memory depends on the CLI, configuration, and workload; it must be counted separately. Three separate warm launches of the previous reader displayed the document in 242–261 ms after entry into `main()`, at 24.5–24.7 MiB physical footprint. The new universal reader measured 261–294 ms and 26.8 MiB with the terminal unopened. These launch measurements include window layout and use a separate process from the integration tests above. They exclude OS loader work.

These numbers are measurements of this machine and fixture, not guarantees or cold-start benchmarks.
