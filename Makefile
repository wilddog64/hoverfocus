APPDIR ?= $(HOME)/Applications
AGENTDIR ?= $(HOME)/Library/LaunchAgents
LAUNCHCTL ?= launchctl
CODESIGN_IDENTITY ?= -

.PHONY: all build selftest icon bundle install uninstall clean

all: build

build:
	swift build -c release

selftest:
	swift run hoverfocus-selftest

icon:
	mkdir -p build/AppIcon.iconset
	swift packaging/render_icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

bundle: build icon
	rm -rf build/HoverFocus.app
	mkdir -p build/HoverFocus.app/Contents/MacOS
	mkdir -p build/HoverFocus.app/Contents/Resources
	cp .build/release/hoverfocus build/HoverFocus.app/Contents/MacOS/hoverfocus
	cp packaging/Info.plist build/HoverFocus.app/Contents/Info.plist
	cp build/AppIcon.icns build/HoverFocus.app/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(CODESIGN_IDENTITY)" build/HoverFocus.app

install: bundle
	@if [ -z "$(APPDIR)" ] || [ -z "$(AGENTDIR)" ]; then \
		echo "APPDIR and AGENTDIR must not be empty" >&2; exit 1; \
	fi
	mkdir -p "$(APPDIR)" "$(AGENTDIR)"
	rm -rf "$(APPDIR)/HoverFocus.app"
	cp -R build/HoverFocus.app "$(APPDIR)/HoverFocus.app"
	sed 's|__PROGRAM__|$(APPDIR)/HoverFocus.app/Contents/MacOS/hoverfocus|g' packaging/com.wilddog64.hoverfocus.plist.tmpl > "$(AGENTDIR)/com.wilddog64.hoverfocus.plist"
	$(LAUNCHCTL) bootout gui/$$(id -u)/com.wilddog64.hoverfocus 2>/dev/null || true
	$(LAUNCHCTL) bootstrap gui/$$(id -u) "$(AGENTDIR)/com.wilddog64.hoverfocus.plist"

uninstall:
	@if [ -z "$(APPDIR)" ] || [ -z "$(AGENTDIR)" ]; then \
		echo "APPDIR and AGENTDIR must not be empty" >&2; exit 1; \
	fi
	$(LAUNCHCTL) bootout gui/$$(id -u)/com.wilddog64.hoverfocus 2>/dev/null || true
	rm -f "$(AGENTDIR)/com.wilddog64.hoverfocus.plist"
	rm -rf "$(APPDIR)/HoverFocus.app"

clean:
	rm -rf build .build
