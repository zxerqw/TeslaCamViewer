# TeslaCamViewer — CLI build harness.
# Run `make help` for the menu.

SCHEME         := TeslaCamViewer
PROJECT        := TeslaCamViewer.xcodeproj
SIMULATOR      := iPhone 17
DESTINATION    := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
DERIVED_DATA   := build
XCBEAUTIFY     := xcbeautify --renderer terminal

# Tell xcodebuild to be quiet about meta-output; xcbeautify formats the rest.
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) \
    -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) \
    COMPILER_INDEX_STORE_ENABLE=NO

.PHONY: help
help:
	@echo "Targets:"
	@echo "  generate   regenerate Xcode project from project.yml"
	@echo "  build      build for the configured simulator"
	@echo "  test       run the full test suite"
	@echo "  test-only TESTS=Class[/method]   run a subset"
	@echo "  clean      remove build/ and DerivedData"
	@echo "  boot       boot the default simulator"
	@echo "  install    install the built .app onto the booted simulator"
	@echo "  launch     launch the installed app on the booted simulator"
	@echo "  run        build + install + launch (end-to-end on simulator)"

.PHONY: generate
generate:
	xcodegen generate

# `generate` is cheap and idempotent; make every build step depend on it so
# that adding a new .swift file never requires you to remember to regen.
$(PROJECT): project.yml
	xcodegen generate

.PHONY: build
build: $(PROJECT)
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) build | $(XCBEAUTIFY)

.PHONY: test
test: $(PROJECT)
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) test | $(XCBEAUTIFY)

# Usage: make test-only TESTS=CameraAngleTests
# Or:    make test-only TESTS=CameraAngleTests/test_fileSuffix_mapsEachAngleToTeslaNaming
.PHONY: test-only
test-only: $(PROJECT)
	@if [ -z "$(TESTS)" ]; then echo "Set TESTS=Class or TESTS=Class/method"; exit 1; fi
	set -o pipefail && xcodebuild $(XCODEBUILD_FLAGS) \
	    -only-testing:TeslaCamViewerTests/$(TESTS) test | $(XCBEAUTIFY)

.PHONY: clean
clean:
	rm -rf $(DERIVED_DATA)

.PHONY: boot
boot:
	-xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a Simulator

.PHONY: install
install: build boot
	xcrun simctl install booted $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app

.PHONY: launch
launch:
	xcrun simctl launch --console-pty booted com.shanehou.$(SCHEME)

.PHONY: run
run: install launch
