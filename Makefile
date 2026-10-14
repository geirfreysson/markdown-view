CC = cc
CFLAGS = -O2 -Wall -Wextra -std=c11
CPPFLAGS = -Isrc -Ivendor/md4c
UNAME_S := $(shell uname -s)
COMMON = src/render.c vendor/md4c/md4c.c
BUILD = build

.PHONY: all test clean install test-native package
ifeq ($(UNAME_S),Darwin)
APP = $(BUILD)/Markdown View.app
BIN = $(BUILD)/markdown-view
MAC_FLAGS = -fobjc-arc -mmacosx-version-min=12.0 $(ARCH_FLAGS)
MAC_COMMON = src/native.m $(COMMON)
all: $(BUILD)/macos.stamp
$(BIN): src/macos.m $(MAC_COMMON) src/native.h src/render.h src/entities.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(CPPFLAGS) $(MAC_FLAGS) src/macos.m $(MAC_COMMON) -framework Cocoa -framework UniformTypeIdentifiers -o "$@"
$(BUILD)/markdown-preview: src/quicklook.m $(MAC_COMMON) src/native.h src/render.h src/entities.h
	$(CC) $(CFLAGS) $(CPPFLAGS) $(MAC_FLAGS) -fapplication-extension src/quicklook.m $(MAC_COMMON) -framework Cocoa -framework QuickLookUI -o "$@"
$(BUILD)/test-quicklook: src/quicklook.m $(MAC_COMMON) src/native.h src/render.h src/entities.h
	$(CC) $(CFLAGS) $(CPPFLAGS) $(MAC_FLAGS) -DMDV_QUICKLOOK_TEST src/quicklook.m $(MAC_COMMON) -framework Cocoa -framework QuickLookUI -o "$@"
$(BUILD)/mdv-integrate: src/integration.m
	$(CC) $(CFLAGS) -Wno-deprecated-declarations $(MAC_FLAGS) src/integration.m -framework Cocoa -framework CoreServices -framework UniformTypeIdentifiers -o "$@"
$(BUILD)/macos.stamp: $(BUILD)/mdv-integrate $(BIN) $(BUILD)/markdown-preview packaging/Info.plist packaging/QuickLook-Info.plist packaging/QuickLook.entitlements
	mkdir -p "$(APP)/Contents/MacOS"
	cp $(BIN) "$(APP)/Contents/MacOS/markdown-view"
	cp $(BUILD)/mdv-integrate "$(APP)/Contents/MacOS/mdv-integrate"
	cp packaging/Info.plist "$(APP)/Contents/Info.plist"
	mkdir -p "$(APP)/Contents/PlugIns/MarkdownPreview.appex/Contents/MacOS"
	cp $(BUILD)/markdown-preview "$(APP)/Contents/PlugIns/MarkdownPreview.appex/Contents/MacOS/markdown-preview"
	cp packaging/QuickLook-Info.plist "$(APP)/Contents/PlugIns/MarkdownPreview.appex/Contents/Info.plist"
	codesign --force --sign - --entitlements packaging/QuickLook.entitlements "$(APP)/Contents/PlugIns/MarkdownPreview.appex"
	codesign --force --sign - "$(APP)"
	touch $@
test-native: all $(BUILD)/test-quicklook
	$(BIN) --smoke-test tests/sample.md
	$(BUILD)/test-quicklook tests/sample.md
install: all
	./scripts/install-macos.sh "$(APP)"
else
GTK_CFLAGS := $(shell pkg-config --cflags gtk+-3.0)
GTK_LIBS := $(shell pkg-config --libs gtk+-3.0)
BIN = $(BUILD)/markdown-view
PREFIX ?= /usr/local
all: $(BIN)
$(BIN): src/linux.c $(COMMON) src/render.h src/entities.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(CPPFLAGS) $(GTK_CFLAGS) src/linux.c $(COMMON) $(GTK_LIBS) -o $@
test-native: all
	xvfb-run -a $(BIN) --smoke-test tests/sample.md
install: all
	install -Dm755 $(BIN) "$(DESTDIR)$(PREFIX)/bin/markdown-view"
	install -Dm644 packaging/markdown-view.desktop "$(DESTDIR)$(PREFIX)/share/applications/markdown-view.desktop"
endif
$(BUILD)/test-render: tests/test_render.c $(COMMON) src/render.h src/entities.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(CPPFLAGS) tests/test_render.c $(COMMON) -o $@
test: $(BUILD)/test-render
	$(BUILD)/test-render
clean:
	rm -rf $(BUILD)

package: all
	./scripts/package.sh
