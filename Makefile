# usage: make [CONFIG=debug|release]

ifeq ($(CONFIG), debug)
    CFLAGS=-Onone -g
else
    CFLAGS=-O
endif

APP_DIR = Memmon.app/Contents

Memmon.app: SDK_PATH = $(shell xcrun --show-sdk-path --sdk macosx)
Memmon.app: src/*
	mkdir -p Memmon.app/Contents/MacOS/
	swiftc $(CFLAGS) src/main.swift \
	-target arm64-apple-macos10.10 -target x86_64-apple-macos10.10 \
	-emit-executable -sdk $(SDK_PATH) -o Memmon.app/Contents/MacOS/Memmon
	mkdir -p Memmon.app/Contents/Resources/
	cp src/AppIcon.icns Memmon.app/Contents/Resources/AppIcon.icns
	cp src/Info.plist Memmon.app/Contents/Info.plist
	echo 'APPL????' > Memmon.app/Contents/PkgInfo
	@touch Memmon.app

.PHONY: release
release: VERSION=$(shell grep -A1 CFBundleShortVersionString src/Info.plist | tail -1 | tr -d '[a-z \t</>]')
release: Memmon.app
	tar -czf "Memmon_v$(VERSION).tar.gz" Memmon.app
