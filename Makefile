.PHONY: build clean run test install uninstall icon refresh-services release

APP_NAME = TranslateKit
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE = $(BUILD_DIR)/debug/$(APP_NAME)
RELEASE_DIR = $(BUILD_DIR)/apple/Products/Release
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

build:
	swift build

test:
	swift test

clean:
	swift package clean

icon:
	swift scripts/generate_icon.swift Resources
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

run: build
	$(EXECUTABLE)

define make_bundle
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(1)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	@test -f "Resources/AppIcon.icns" && cp "Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/" || true
	@cp -R $(1)/*.resources "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	@cp -R $(1)/*.bundle "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
endef

install: build
	@echo "Creating app bundle..."
	$(call make_bundle,$(BUILD_DIR)/debug)
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "/Applications/"
	@echo "Installed! Run 'make refresh-services' (or log out and back in) to register the Service."

# Universal release build: bundle + zip, ad-hoc signed (no Developer ID yet)
release:
	swift build -c release --arch arm64 --arch x86_64
	$(call make_bundle,$(RELEASE_DIR))
	@cd "$(BUILD_DIR)" && ditto -c -k --keepParent "$(APP_NAME).app" "$(APP_NAME)-$(VERSION).zip"
	@echo "Release artifact: $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip"

uninstall:
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "Uninstalled."

# Force-refresh macOS Services cache (no logout needed)
refresh-services:
	/System/Library/CoreServices/pbs -dump_pboard
	/System/Library/CoreServices/pbs -flush
	@echo "Services cache refreshed."
