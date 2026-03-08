APP_NAME = LLM Status
BUNDLE_NAME = LLMStatus.app
EXECUTABLE = LLMStatus
BUILD_DIR = .build/release
BUNDLE_DIR = build/$(BUNDLE_NAME)
IDENTITY ?= -

.PHONY: all build bundle sign clean run

all: bundle sign

build:
	swift build -c release

bundle: build
	@rm -rf build/$(BUNDLE_NAME)
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(EXECUTABLE) $(BUNDLE_DIR)/Contents/MacOS/
	@cp Info.plist $(BUNDLE_DIR)/Contents/
	@cp LLMStatus/Resources/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/
	@# Copy SPM resource bundle (contains MenuBarIcon.pdf etc.)
	@cp -R $(BUILD_DIR)/LLMStatus_LLMStatus.bundle $(BUNDLE_DIR)/Contents/Resources/
	@# Copy Python scripts
	@mkdir -p $(BUNDLE_DIR)/Contents/Resources/scripts
	@cp scripts/*.py $(BUNDLE_DIR)/Contents/Resources/scripts/
	@echo "✓ Bundle created at build/$(BUNDLE_NAME)"

sign: bundle
	codesign --deep --force --sign "$(IDENTITY)" \
		--entitlements LLMStatus.entitlements \
		--options=runtime \
		$(BUNDLE_DIR)
	@echo "✓ Signed with identity: $(IDENTITY)"

run: all
	@open build/$(BUNDLE_NAME)

clean:
	@rm -rf build/
	swift package clean
	@echo "✓ Cleaned"
