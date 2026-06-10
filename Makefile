BINARY := systemmcp
RELEASE_BIN := .build/release/$(BINARY)
# Override with a Developer ID identity for a persistent TCC grant, e.g.
#   make sign SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
SIGN_IDENTITY ?= -

.PHONY: build release test format lint sign install clean run-reminder-serve run-calendar-serve

build:
	swift build

release:
	swift build -c release

test:
	swift test

format:
	swift format format --in-place --recursive Sources Tests Package.swift

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

# Code-sign the built binary so TCC can attribute and remember the permission grant.
# The Info.plist is already embedded at link time (see Package.swift linkerSettings).
sign: release
	codesign --force --sign "$(SIGN_IDENTITY)" "$(RELEASE_BIN)"
	@echo "Signed $(RELEASE_BIN)"
	@codesign -dvv "$(RELEASE_BIN)" 2>&1 | grep -E "Identifier|Authority|Signature" || true

# Build, sign, and print the absolute path to use in claude_desktop_config.json.
install: sign
	@echo "Binary ready at: $(abspath $(RELEASE_BIN))"
	@echo "Grant permissions once: $(abspath $(RELEASE_BIN)) reminder status && $(abspath $(RELEASE_BIN)) calendar status"

clean:
	swift package clean

run-reminder-serve: build
	.build/debug/$(BINARY) reminder serve

run-calendar-serve: build
	.build/debug/$(BINARY) calendar serve
