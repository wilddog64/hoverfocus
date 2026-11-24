APPDIR ?= $(HOME)/Applications
AGENTDIR ?= $(HOME)/Library/LaunchAgents
LAUNCHCTL ?= launchctl
CODESIGN_IDENTITY ?= -
BOOTOUT_WAIT_TRIES ?= 50
SWIFT_BUILD_FLAGS ?=

export APPDIR AGENTDIR LAUNCHCTL CODESIGN_IDENTITY BOOTOUT_WAIT_TRIES

.PHONY: all build selftest icon bundle install uninstall clean

all: build

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

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
	codesign --force --sign "$$CODESIGN_IDENTITY" build/HoverFocus.app

install: bundle
	@if [ -z "$$APPDIR" ] || [ -z "$$AGENTDIR" ]; then \
		echo "APPDIR and AGENTDIR must not be empty" >&2; exit 1; \
	fi
	mkdir -p "$$APPDIR" "$$AGENTDIR"
	rm -rf "$$APPDIR/HoverFocus.app"
	cp -R build/HoverFocus.app "$$APPDIR/HoverFocus.app"
	cp packaging/com.wilddog64.hoverfocus.plist.tmpl "$$AGENTDIR/com.wilddog64.hoverfocus.plist"
	plutil -replace ProgramArguments -array "$$AGENTDIR/com.wilddog64.hoverfocus.plist"
	plutil -insert ProgramArguments.0 -string "$$APPDIR/HoverFocus.app/Contents/MacOS/hoverfocus" "$$AGENTDIR/com.wilddog64.hoverfocus.plist"
	@if [ "$$CODESIGN_IDENTITY" = "-" ]; then \
		echo "hoverfocus: ad-hoc signed build. If the menu shows \"Needs Accessibility permission\" although HoverFocus is enabled"; \
		echo "in System Settings, reset the old grant and grant again:"; \
		echo "  tccutil reset Accessibility com.wilddog64.hoverfocus"; \
		echo "then enable HoverFocus in System Settings > Privacy & Security > Accessibility."; \
	fi
	@mgr=$$("$$LAUNCHCTL" managername 2>/dev/null || true); \
	if [ "$$mgr" != "Aqua" ]; then \
		echo "hoverfocus: not a GUI login session (launchctl managername: $$mgr); files are installed but the agent is not loaded." >&2; \
		echo "To load it from this session, run:" >&2; \
		echo "  sudo launchctl asuser $$(id -u) launchctl bootout gui/$$(id -u)/com.wilddog64.hoverfocus" >&2; \
		echo "  sudo launchctl asuser $$(id -u) launchctl bootstrap gui/$$(id -u) '$$AGENTDIR/com.wilddog64.hoverfocus.plist'" >&2; \
		exit 0; \
	fi; \
	"$$LAUNCHCTL" bootout gui/$$(id -u)/com.wilddog64.hoverfocus 2>/dev/null || true; \
	tries=0; \
	loaded=1; \
	while [ "$$tries" -lt "$$BOOTOUT_WAIT_TRIES" ]; do \
		if ! "$$LAUNCHCTL" print gui/$$(id -u)/com.wilddog64.hoverfocus >/dev/null 2>&1; then \
			loaded=0; \
			break; \
		fi; \
		tries=$$((tries + 1)); \
		sleep 0.1; \
	done; \
	if [ "$$loaded" -eq 1 ]; then \
		echo "hoverfocus: agent still loaded after bootout; not bootstrapping" >&2; \
		exit 1; \
	fi; \
	"$$LAUNCHCTL" bootstrap gui/$$(id -u) "$$AGENTDIR/com.wilddog64.hoverfocus.plist"

uninstall:
	@if [ -z "$$APPDIR" ] || [ -z "$$AGENTDIR" ]; then \
		echo "APPDIR and AGENTDIR must not be empty" >&2; exit 1; \
	fi
	@mgr=$$("$$LAUNCHCTL" managername 2>/dev/null || true); \
	if [ "$$mgr" != "Aqua" ]; then \
		echo "hoverfocus: not a GUI login session (launchctl managername: $$mgr); files are removed but the agent is not unloaded." >&2; \
		echo "To unload it from this session, run:" >&2; \
		echo "  sudo launchctl asuser $$(id -u) launchctl bootout gui/$$(id -u)/com.wilddog64.hoverfocus" >&2; \
	else \
		"$$LAUNCHCTL" bootout gui/$$(id -u)/com.wilddog64.hoverfocus 2>/dev/null || true; \
	fi
	rm -f "$$AGENTDIR/com.wilddog64.hoverfocus.plist"
	rm -rf "$$APPDIR/HoverFocus.app"

clean:
	rm -rf build .build
