APP_NAME = Fun Fan Control
BUILD_DIR = build
APP = $(BUILD_DIR)/$(APP_NAME).app
CONFIG ?= release
BIN = .build/$(CONFIG)

.PHONY: all app run install-helper install clean probe

all: app

HELPER = $(APP)/Contents/MacOS/ffc-helper

# Stops a running copy of the app first so it can hand the fans back to macOS while the
# installed (setuid) helper still exists, then rebuilds the bundle. The helper is only
# replaced when its binary actually changed, so an installed helper survives UI-only rebuilds.
app:
	swift build -c $(CONFIG)
	@if pgrep -x FunFanControl >/dev/null; then echo "Stopping running app…"; pkill -x FunFanControl; sleep 1.5; fi
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)/FunFanControl" "$(APP)/Contents/MacOS/"
	@if cmp -s "$(BIN)/ffc-helper" "$(HELPER)"; then \
		echo "Helper unchanged, keeping installed copy"; \
	else \
		rm -f "$(HELPER)"; cp "$(BIN)/ffc-helper" "$(HELPER)"; \
		echo "Helper replaced: run 'make install-helper' or click Install helper in the app"; \
	fi
	cp Resources/Info.plist "$(APP)/Contents/"
	codesign --force --sign - "$(APP)/Contents/MacOS/FunFanControl"
	@if [ "$$(stat -f %Su "$(HELPER)")" != "root" ]; then codesign --force --sign - "$(HELPER)"; fi
	@echo "Built $(APP)"

run: app
	open "$(APP)"

# Marks the helper inside the built app setuid root (the app can also do this with a password prompt).
install-helper:
	sudo chown root:wheel "$(HELPER)"
	sudo chmod 4755 "$(HELPER)"

# Copies the app to /Applications. Re-run install-helper afterwards for the copied app.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app — open it and click Install helper in Settings."

probe:
	swift run -c $(CONFIG) ffc-probe

clean:
	rm -rf .build "$(BUILD_DIR)"
