BINARY := systemmcp
RELEASE_BIN := .build/release/$(BINARY)
# Override with a Developer ID identity for a persistent TCC grant, e.g.
#   make sign SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
SIGN_IDENTITY ?= -
# Stable install location on $PATH. Re-builds overwrite .build/release, so we copy
# the signed binary here for day-to-day use (hermes, Claude Desktop, shell).
# Override with: make install INSTALL_DIR=/somewhere/else
INSTALL_DIR ?= $(HOME)/.local/bin
INSTALLED_BIN := $(INSTALL_DIR)/$(BINARY)

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

# Build, sign, and copy the binary to a stable $PATH location ($(INSTALL_DIR)).
# A plain byte copy preserves the embedded signature and cdhash, so the existing
# TCC grant for jp.mzp.systemmcp keeps working without re-approval.
install: sign
	@mkdir -p "$(INSTALL_DIR)"
	@# Atomic replace via temp + mv. Overwriting a signed Mach-O in place (cp -f over
	@# the same inode) makes the kernel kill it with "Killed: 9" on next exec, because
	@# the cached page hashes no longer match. A new inode + rename avoids that.
	@cp -f "$(RELEASE_BIN)" "$(INSTALLED_BIN).tmp"
	@mv -f "$(INSTALLED_BIN).tmp" "$(INSTALLED_BIN)"
	@echo "Installed: $(INSTALLED_BIN)"
	@codesign --verify --verbose=1 "$(INSTALLED_BIN)" 2>&1 | tail -1 || true
	@echo "Grant permissions once from a GUI terminal/app (so the prompt appears):"
	@echo "  $(INSTALLED_BIN) reminder status && $(INSTALLED_BIN) calendar status"

clean:
	swift package clean

run-reminder-serve: build
	.build/debug/$(BINARY) reminder serve

run-calendar-serve: build
	.build/debug/$(BINARY) calendar serve
