# Repository Guidelines

## Project Structure & Module Organization

Markdown View is a read-only native Markdown viewer for macOS and Linux. `src/render.c` and `src/render.h` define the shared C renderer, backed by vendored MD4C in `vendor/md4c/`. AppKit rendering lives in `src/native.m`; `src/macos.m`, `src/quicklook.m`, and `src/integration.m` handle the macOS app, Finder preview, and installation integration. `src/linux.c` implements the GTK interface.

`tests/` contains assertion-based C/Objective-C tests and Markdown/image fixtures. `packaging/` holds platform metadata and entitlements; `scripts/` handles installation, signing, and packaging. Documentation and screenshots live in `docs/`. Generated files belong in `build/` and `dist/`.

## Build, Test, and Development Commands

Use Apple command-line tools on macOS. Linux requires a C toolchain, `pkg-config`, and GTK 3 development headers; native smoke tests also require `xvfb`.

- `make`: build the executable and, on macOS, the app and Quick Look bundle.
- `./build/markdown-view tests/sample.md`: open a fixture locally.
- `make test`: compile and run shared renderer tests.
- `make test-native`: run native smoke tests and macOS-specific assertions; Linux uses `xvfb-run`.
- `make clean`: remove build outputs.
- `make ARCH_FLAGS="-arch arm64 -arch x86_64"`: build universal macOS binaries after cleaning.
- `make package`: produce platform downloads in `dist/`.

## Coding Style & Naming Conventions

Follow the existing compact C11 and Objective-C style: four-space indentation, same-line opening braces, and local formatting conventions. Use `snake_case` for C functions and variables, `mdv_` for shared functions, `Mdv` for shared types, and `MDV_` for constants. Keep platform APIs in their platform modules. The Makefile enables `-Wall -Wextra`; no dedicated formatter or linter is configured.

## Testing Guidelines

Add renderer regressions to `tests/test_render.c`, AppKit assertions to `tests/test_native.m`, and reusable examples to `tests/*.md`. Run `make test` and `make test-native` for affected platforms. CI tests both platforms and runs AddressSanitizer/UndefinedBehaviorSanitizer checks. No numerical coverage threshold is configured.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, such as “Give tables independent spacing after lists and paragraphs.” Follow that pattern and keep changes focused. PRs should explain the behavior change, link relevant issues, and report validation and platforms tested. Include screenshots for layout changes and update documentation when user-facing behavior changes.
