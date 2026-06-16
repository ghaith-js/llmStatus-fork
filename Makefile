APP_NAME = LLM Status
BUNDLE_NAME = LLMStatus.app
EXECUTABLE = LLMStatus
BUILD_DIR = .build/release
BUNDLE_DIR = .build/app/$(BUNDLE_NAME)
LEGACY_BUNDLE_DIR = build/$(BUNDLE_NAME)
IDENTITY ?= -

.PHONY: all build bundle sign clean run

all: bundle sign

build:
	swift build -c release

bundle: build
	@if [ -d "$(BUNDLE_DIR)" ]; then trash "$(BUNDLE_DIR)"; fi
	@if [ -d "$(LEGACY_BUNDLE_DIR)" ]; then trash "$(LEGACY_BUNDLE_DIR)"; fi
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(EXECUTABLE) $(BUNDLE_DIR)/Contents/MacOS/
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

run: all
	@open $(BUNDLE_DIR)

clean:
	@if [ -d ".build/app" ]; then trash ".build/app"; fi
	@if [ -d "build" ]; then trash "build"; fi
	swift package clean
	@echo "✓ Cleaned"
