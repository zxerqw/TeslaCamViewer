# TeslaCamViewer — CLI build harness.
# Run `make help` for the menu.

SCHEME         := TeslaCamViewer
BUNDLE_ID      := com.shanehou.TeslaCamViewer
PROJECT        := TeslaCamViewer.xcodeproj
# override: make test SIMULATOR='iPhone 16 Pro'
SIMULATOR      := iPhone 17
DESTINATION    := platform=iOS Simulator,name=$(SIMULATOR),OS=latest
DERIVED_DATA   := build
XCBEAUTIFY     := xcbeautify --renderer terminal

# Tell xcodebuild to be quiet about meta-output; xcbeautify formats the rest.
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) \
    -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) \
    COMPILER_INDEX_STORE_ENABLE=NO

# --- Device (physical iPhone/iPad) ---
#
# Device installs require code signing, which needs a DEVELOPMENT_TEAM.
# Team IDs are per-developer so we don't hardcode one in project.yml.
# Two ways to provide it (in priority order):
#
#   1. Environment variable:     DEVELOPMENT_TEAM=ABCDE12345 make install-device
#   2. .env.local file (gitignored):
#        echo 'DEVELOPMENT_TEAM=ABCDE12345' > .env.local
#        echo 'DEVICE_ID=Shanes-iPhone'   >> .env.local   # optional; name or UUID
#
# Find your Team ID at https://developer.apple.com/account → Membership.
-include .env.local

DEVICE_DESTINATION := generic/platform=iOS
# -allowProvisioningUpdates lets Xcode create/refresh provisioning profiles
# on our behalf when they're missing — needed on fresh machines or new Team IDs.
DEVICE_BUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) \
    -destination '$(DEVICE_DESTINATION)' -derivedDataPath $(DERIVED_DATA) \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
    COMPILER_INDEX_STORE_ENABLE=NO
DEVICE_APP_PATH    := $(DERIVED_DATA)/Build/Products/Debug-iphoneos/$(SCHEME).app

.PHONY: help
help:
	@echo "Simulator targets:"
	@echo "  generate             regenerate Xcode project from project.yml"
	@echo "  build                build for the configured simulator"
	@echo "  test                 run the full test suite"
	@echo "  test-only TESTS=...  run a subset (Class or Class/method)"
	@echo "  clean                remove build/ and DerivedData"
	@echo "  boot                 boot the default simulator"
	@echo "  install              install the built .app onto the booted simulator"
	@echo "  launch               launch the installed app on the booted simulator"
	@echo "  run                  install + launch (simulator)"
	@echo ""
	@echo "Device targets (connected iPhone/iPad):"
	@echo "  list-devices         list connected devices (names/UUIDs for DEVICE_ID)"
	@echo "  build-device         build for physical device (needs DEVELOPMENT_TEAM)"
	@echo "  install-device       install .app onto the connected device"
	@echo "  launch-device        launch the installed app on the device (streams logs)"
	@echo "  run-device           install + launch (device)"
	@echo ""
	@echo "Device setup:"
	@echo "  export DEVELOPMENT_TEAM=ABCDE12345    # or put in .env.local"
	@echo "  export DEVICE_ID='Shanes iPhone'      # optional; name or UUID"

.PHONY: generate
generate:
	xcodegen generate

# Regenerate when project.yml changes so you don't have to remember to run
# `make generate` after editing the spec. Note: adding new .swift files
# still requires an explicit `make generate` — xcodegen only scans sources
# at regen time, not on every build.
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
	-xcrun simctl boot "$(SIMULATOR)" 2>/dev/null
	open -a Simulator

.PHONY: install
install: build boot
	xcrun simctl install booted $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app

.PHONY: launch
launch:
	xcrun simctl launch --console-pty booted $(BUNDLE_ID)

.PHONY: run
run: install launch

# --- Device targets ---------------------------------------------------------

.PHONY: list-devices
list-devices:
	@xcrun devicectl list devices 2>/dev/null | grep -v "Apple Watch" | \
	    awk 'NR==1 || /available/ { print }'

# Resolve DEVICE_ID at command time:
#   1. $(DEVICE_ID) from env or .env.local
#   2. otherwise, pick the first non-Watch available device
DEVICE_LOOKUP = $(shell \
    if [ -n "$(DEVICE_ID)" ]; then \
        echo "$(DEVICE_ID)"; \
    else \
        xcrun devicectl list devices 2>/dev/null | \
            awk '/available/ && !/Apple Watch/ { \
                for (i=NF; i>=1; i--) if ($$i ~ /^[0-9A-F-]{36}$$/) { print $$i; exit } \
            }'; \
    fi)

.PHONY: _check-device-env
_check-device-env:
	@if [ -z "$(DEVELOPMENT_TEAM)" ]; then \
	    echo "error: DEVELOPMENT_TEAM not set."; \
	    echo "  Put it in .env.local (echo 'DEVELOPMENT_TEAM=ABCDE12345' > .env.local)"; \
	    echo "  or export it: export DEVELOPMENT_TEAM=ABCDE12345"; \
	    echo "  Find your Team ID at https://developer.apple.com/account → Membership."; \
	    exit 1; \
	fi

.PHONY: _check-device-connected
_check-device-connected:
	@dev="$(DEVICE_LOOKUP)"; \
	if [ -z "$$dev" ]; then \
	    echo "error: no device connected (or DEVICE_ID not resolvable)."; \
	    echo "  Run: make list-devices"; \
	    echo "  Then: export DEVICE_ID='Your iPhone'   # name or UUID"; \
	    exit 1; \
	fi; \
	echo "Using device: $$dev"

.PHONY: build-device
build-device: _check-device-env $(PROJECT)
	set -o pipefail && xcodebuild $(DEVICE_BUILD_FLAGS) build | $(XCBEAUTIFY)

.PHONY: install-device
install-device: _check-device-env _check-device-connected build-device
	xcrun devicectl device install app \
	    --device "$(DEVICE_LOOKUP)" \
	    "$(DEVICE_APP_PATH)"

.PHONY: launch-device
launch-device: _check-device-connected
	xcrun devicectl device process launch \
	    --device "$(DEVICE_LOOKUP)" \
	    --console \
	    --terminate-existing \
	    $(BUNDLE_ID)

.PHONY: run-device
run-device: install-device launch-device
