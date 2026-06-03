SHELL := /bin/zsh

PRODUCT := Matrix.saver
BUILD_DIR := build
MODULE_CACHE := $(BUILD_DIR)/ModuleCache
BUNDLE := $(BUILD_DIR)/$(PRODUCT)
CONTENTS := $(BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
EXECUTABLE := Matrix
SWIFT_SOURCES := $(wildcard Sources/*.swift)

.PHONY: all clean install probes

all: $(BUNDLE)
probes: $(BUILD_DIR)/probe_swift $(BUILD_DIR)/probe_original

$(BUNDLE): $(MACOS)/$(EXECUTABLE) $(BUILD_DIR)/resources-copied $(CONTENTS)/Info.plist

$(MACOS)/$(EXECUTABLE): $(SWIFT_SOURCES)
	@mkdir -p $(MACOS) $(MODULE_CACHE)
	swiftc -emit-library -parse-as-library -module-name Matrix \
		-target arm64-apple-macos12.0 \
		-module-cache-path $(MODULE_CACHE) \
		-framework Cocoa -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore \
		-Xlinker -bundle \
		-o $@ $^

$(BUILD_DIR)/resources-copied: $(shell find Resources -type f)
	@mkdir -p $(RESOURCES)
	cp -R Resources/. $(RESOURCES)/
	@touch $@

$(CONTENTS)/Info.plist: Info.plist
	@mkdir -p $(CONTENTS)
	cp $< $@

$(BUILD_DIR)/probe_swift: Tools/probe_swift.swift $(BUNDLE)
	@mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	swiftc -module-cache-path $(MODULE_CACHE) \
		-framework Cocoa -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore \
		-o $@ $<

$(BUILD_DIR)/probe_original: Tools/probe_original.cpp
	@mkdir -p $(BUILD_DIR)
	clang++ -std=c++17 -O0 $< \
		-framework Cocoa -framework ScreenSaver -framework Metal -framework MetalKit -framework GLKit -framework OpenGL \
		-o $@

install: all
	@mkdir -p "$$HOME/Library/Screen Savers"
	cp -R $(BUNDLE) "$$HOME/Library/Screen Savers/$(PRODUCT)"

clean:
	rm -rf $(BUILD_DIR)
