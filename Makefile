APP_NAME = LLM Status
BUNDLE_NAME = LLMStatus.app
EXECUTABLE = LLMStatus
NATIVE_ARCH := $(shell if [ "$$(sysctl -in hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then echo arm64; else uname -m; fi)
BUILD_DIR = .build/$(NATIVE_ARCH)-apple-macosx/release
BUNDLE_DIR = .build/app/$(BUNDLE_NAME)
LEGACY_BUNDLE_DIR = build/$(BUNDLE_NAME)
INSTALL_PATH = /Applications/$(BUNDLE_NAME)
IDENTITY ?= -

.PHONY: all build bundle sign install clean run

all: bundle sign

build:
	swift build -c release --arch $(NATIVE_ARCH)

bundle: build
	@if [ -d "$(BUNDLE_DIR)" ]; then trash "$(BUNDLE_DIR)"; fi
	@if [ -d "$(LEGACY_BUNDLE_DIR)" ]; then trash "$(LEGACY_BUNDLE_DIR)"; fi
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(EXECUTABLE) $(BUNDLE_DIR)/Contents/MacOS/
	@lipo -archs $(BUNDLE_DIR)/Contents/MacOS/$(EXECUTABLE) | tr ' ' '\n' | grep -qx "$(NATIVE_ARCH)" || (file $(BUNDLE_DIR)/Contents/MacOS/$(EXECUTABLE); exit 1)
	@cp Info.plist $(BUNDLE_DIR)/Contents/
	@cp LLMStatus/Resources/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/
	@# Copy SPM resource bundle (contains MenuBarIcon.pdf etc.)
	@cp -R $(BUILD_DIR)/LLMStatus_LLMStatus.bundle $(BUNDLE_DIR)/Contents/Resources/
	@echo "✓ Bundle created at $(BUNDLE_DIR)"

sign: bundle
	codesign --deep --force --sign "$(IDENTITY)" \
		--entitlements LLMStatus.entitlements \
		--options=runtime \
		$(BUNDLE_DIR)
	@echo "✓ Signed with identity: $(IDENTITY)"

# Canonical copy Spotlight / Launchpad / login items launch.
install: all
	@-pkill -x $(EXECUTABLE)
	@sleep 0.4
	@if [ -d "/Applications/LLM Status.app" ]; then trash "/Applications/LLM Status.app"; fi
	@ditto "$(BUNDLE_DIR)" "$(INSTALL_PATH)"
	@echo "✓ Installed to $(INSTALL_PATH)"

run: install
	@open "$(INSTALL_PATH)"

clean:
	@if [ -d ".build/app" ]; then trash ".build/app"; fi
	@if [ -d "build" ]; then trash "build"; fi
	swift package clean
	@echo "✓ Cleaned"
