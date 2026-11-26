APPDIR ?= $(HOME)/Applications
AGENTDIR ?= $(HOME)/Library/LaunchAgents
LAUNCHCTL ?= launchctl
CODESIGN_IDENTITY ?=
BOOTOUT_WAIT_TRIES ?= 50
SWIFT_BUILD_FLAGS ?=
SECURITY ?= security
CODESIGN ?= codesign
OPENSSL ?= /usr/bin/openssl
SIGNING_NAME ?= HoverFocus Local Signing

export APPDIR AGENTDIR LAUNCHCTL CODESIGN_IDENTITY BOOTOUT_WAIT_TRIES SECURITY CODESIGN OPENSSL SIGNING_NAME

.PHONY: all build selftest icon bundle install uninstall clean signing-identity

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
	@id="$$CODESIGN_IDENTITY"; \
	if [ -z "$$id" ]; then \
		if "$$SECURITY" find-identity -p codesigning 2>/dev/null | grep -Fq "\"$$SIGNING_NAME\""; then \
			id="$$SIGNING_NAME"; \
		else \
			id="-"; \
		fi; \
	fi; \
	if [ "$$id" = "-" ]; then \
		echo "hoverfocus: signing with ad-hoc (-)"; \
	else \
		echo "hoverfocus: signing with $$id"; \
	fi; \
	rm -f build/.codesign-identity; \
	if ! "$$CODESIGN" --force --sign "$$id" build/HoverFocus.app; then \
		rm -rf build/HoverFocus.app; \
		if [ "$$id" = "-" ]; then \
			echo "hoverfocus: ad-hoc signing failed." >&2; \
		else \
			echo "hoverfocus: signing with \"$$id\" failed. If this is an SSH session, the login Keychain is probably locked: run make install at this Mac's keyboard, or build ad-hoc with make install CODESIGN_IDENTITY=- (HoverFocus then needs its Accessibility permission granted again)." >&2; \
		fi; \
		exit 1; \
	fi; \
	echo "$$id" > build/.codesign-identity

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
	@id=$$(cat build/.codesign-identity 2>/dev/null || echo "$$CODESIGN_IDENTITY"); \
	if [ "$$id" = "-" ]; then \
		echo "hoverfocus: ad-hoc signed build. If the menu shows \"Needs Accessibility permission\" although HoverFocus is enabled"; \
		echo "in System Settings, reset the old grant and grant again:"; \
		echo "  tccutil reset Accessibility com.wilddog64.hoverfocus"; \
		echo "then enable HoverFocus in System Settings > Privacy & Security > Accessibility."; \
		echo "run \"make signing-identity\" once at this Mac's keyboard so later builds keep the grant."; \
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

signing-identity:
	packaging/signing-identity.sh

clean:
	rm -rf build .build
