.PHONY: build clean run install uninstall icon

APP_NAME = TranslateKit
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE = $(BUILD_DIR)/debug/translate-kit

build:
	swift build

clean:
	swift package clean

icon:
	swift scripts/generate_icon.swift Resources
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

run: build
	$(EXECUTABLE)

install: build
	@echo "Creating app bundle..."
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(EXECUTABLE)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/"
	@test -f "Resources/AppIcon.icns" && cp "Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/" || true
	@cp -R ".build/debug/TranslateKit_TranslateKit.resources/"* "$(APP_BUNDLE)/Contents/Resources/" 2>/dev/null || true
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "/Applications/"
	@echo "Installed! Log out and back in to register the Service."

uninstall:
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "Uninstalled."

# Force-refresh macOS Services cache (no logout needed)
refresh-services:
	/System/Library/CoreServices/pbs -dump_pboard
	/System/Library/CoreServices/pbs -flush
	@echo "Services cache refreshed."
