.PHONY: build clean run run-cli test install uninstall icon refresh-services release

APP_NAME = TranslateKit
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
APP_EXECUTABLE = $(BUILD_DIR)/debug/$(APP_NAME)
CLI_EXECUTABLE = $(BUILD_DIR)/debug/tkit
ARM64_BUILD_DIR = $(BUILD_DIR)
X86_64_BUILD_DIR = $(BUILD_DIR)/x86_64
ARM64_RELEASE_DIR = $(ARM64_BUILD_DIR)/arm64-apple-macosx/release
X86_64_RELEASE_DIR = $(X86_64_BUILD_DIR)/x86_64-apple-macosx/release
RELEASE_DIR = $(BUILD_DIR)/universal-release
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
CODE_SIGN_IDENTITY_NAME = TranslateKit Dev
CODE_SIGN_IDENTITY = $(shell security find-identity -v -p codesigning | awk '/"$(CODE_SIGN_IDENTITY_NAME)"/ { print $$2; exit }')

build:
	swift build --product $(APP_NAME)
	swift build --product tkit

test:
	swift test

clean:
	swift package clean

icon:
	swift scripts/generate_icon.swift Resources
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

run: build
	$(APP_EXECUTABLE)

run-cli: build
	$(CLI_EXECUTABLE)

define make_bundle
	@test -n "$(CODE_SIGN_IDENTITY)" || \
		(echo "Missing valid code-signing identity: $(CODE_SIGN_IDENTITY_NAME)"; exit 1)
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(1)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp "$(1)/tkit" "$(APP_BUNDLE)/Contents/MacOS/tkit"
	@cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	@test -f "Resources/AppIcon.icns" && cp "Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/" || true
	@cp -R $(1)/*.resources "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	@cp -R $(1)/*.bundle "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(APP_BUNDLE)/Contents/MacOS/tkit"
	@codesign --force --deep --sign "$(CODE_SIGN_IDENTITY)" "$(APP_BUNDLE)"
endef

install: build
	@echo "Creating app bundle..."
	$(call make_bundle,$(BUILD_DIR)/debug)
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "/Applications/"
	@echo "Installed! Run 'make refresh-services' (or log out and back in) to register the Service."

# Universal release build: bundle + zip, signed with the stable development identity.
release:
	swift build -c release --arch arm64 --build-path "$(ARM64_BUILD_DIR)"
	swift build -c release --arch x86_64 --build-path "$(X86_64_BUILD_DIR)"
	@rm -rf "$(RELEASE_DIR)"
	@mkdir -p "$(RELEASE_DIR)"
	@lipo -create "$(ARM64_RELEASE_DIR)/$(APP_NAME)" "$(X86_64_RELEASE_DIR)/$(APP_NAME)" \
		-output "$(RELEASE_DIR)/$(APP_NAME)"
	@lipo -create "$(ARM64_RELEASE_DIR)/tkit" "$(X86_64_RELEASE_DIR)/tkit" \
		-output "$(RELEASE_DIR)/tkit"
	@cp -R $(ARM64_RELEASE_DIR)/*.resources "$(RELEASE_DIR)/" 2>/dev/null || true
	@cp -R $(ARM64_RELEASE_DIR)/*.bundle "$(RELEASE_DIR)/" 2>/dev/null || true
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
