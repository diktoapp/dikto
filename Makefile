# Dikto — build orchestration for Rust core + Swift bindings + macOS app

CARGO        = $(HOME)/.cargo/bin/cargo
RUST_LIB     = target/release/libdikto_core.a
BINDINGS_DIR = DiktoApp/Generated
SWIFT_FILE   = $(BINDINGS_DIR)/dikto_core.swift
HEADER_FILE  = $(BINDINGS_DIR)/dikto_coreFFI.h
MODULE_MAP   = $(BINDINGS_DIR)/dikto_coreFFI.modulemap
UDLLIB       = target/release/libdikto_core.dylib

.PHONY: all build-rust generate-bindings build-app clean test clippy package release

all: build-rust generate-bindings build-app

## Build the Rust static library (release, with Metal)
build-rust:
	$(CARGO) build --release --package dikto-core

## Generate Swift bindings from the compiled dylib
generate-bindings: build-rust
	mkdir -p $(BINDINGS_DIR)
	$(CARGO) run --release --bin uniffi-bindgen -- generate \
		--library $(UDLLIB) \
		--language swift \
		--out-dir $(BINDINGS_DIR)
	@echo "Generated: $(SWIFT_FILE) $(HEADER_FILE) $(MODULE_MAP)"

## Build the macOS app bundle
build-app: generate-bindings
	./build-app.sh

## Run all tests
test:
	$(CARGO) test --workspace

## Run clippy lints
clippy:
	$(CARGO) clippy --workspace -- -D warnings

## Create distributable DMG
package: build-app
	./package-dmg.sh

## Build release (enforces proper signing)
release: build-rust generate-bindings
	./build-app.sh --release

## Clean all build artifacts
clean:
	$(CARGO) clean
	rm -rf $(BINDINGS_DIR)
	rm -rf build/
