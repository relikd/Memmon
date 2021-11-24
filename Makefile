# usage: make [CONFIG=debug|release]

ifeq ($(CONFIG), debug)
    CFLAGS=-Onone -g
else
    CFLAGS=-O
endif

PLIST=$(shell grep -A1 $(1) src/Info.plist | tail -1 | cut -d'>' -f2 | cut -d'<' -f1)


Memmon.app: SDK_PATH=$(shell xcrun --show-sdk-path --sdk macosx)
Memmon.app: src/*
	@mkdir -p Memmon.app/Contents/MacOS/
	swiftc ${CFLAGS} src/main.swift -target x86_64-apple-macos10.10 \
	-emit-executable -sdk ${SDK_PATH} -o bin_x64
	swiftc ${CFLAGS} src/main.swift -target arm64-apple-macos10.10 \
	-emit-executable -sdk ${SDK_PATH} -o bin_arm64
	lipo -create bin_x64 bin_arm64 -o Memmon.app/Contents/MacOS/Memmon
	@rm bin_x64 bin_arm64
	@echo 'APPL????' > Memmon.app/Contents/PkgInfo
	@mkdir -p Memmon.app/Contents/Resources/
	@cp src/AppIcon.icns Memmon.app/Contents/Resources/AppIcon.icns
	@cp src/Info.plist Memmon.app/Contents/Info.plist
	@touch Memmon.app
	@echo
	codesign -v -s 'Apple Development' --options=runtime --timestamp Memmon.app
	@echo
	@echo 'Verify Signature...'
	@echo
	codesign -dvv Memmon.app
	@echo
	codesign -vvv --deep --strict Memmon.app
	@echo
	spctl -vvv --assess --type exec Memmon.app

.PHONY: release
release: VERSION=$(call PLIST,CFBundleShortVersionString)
release: Memmon.app
	tar -czf "Memmon_v${VERSION}.tar.gz" Memmon.app
