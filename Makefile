APP_NAME = Fun Fan Control
BUILD_DIR = build
APP = $(BUILD_DIR)/$(APP_NAME).app
CONFIG ?= release
BIN = .build/$(CONFIG)

.PHONY: all app run install-helper install clean probe

all: app

app:
	swift build -c $(CONFIG)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)/FunFanControl" "$(APP)/Contents/MacOS/"
	cp "$(BIN)/ffc-helper" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	codesign --force --deep --sign - "$(APP)"
	@echo "Built $(APP)"

run: app
	open "$(APP)"

# Marks the helper inside the built app setuid root (the app can also do this with a password prompt).
install-helper:
	sudo chown root:wheel "$(APP)/Contents/MacOS/ffc-helper"
	sudo chmod 4755 "$(APP)/Contents/MacOS/ffc-helper"

# Copies the app to /Applications. Re-run install-helper afterwards for the copied app.
install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app — open it and click Install helper in Settings."

probe:
	swift run -c $(CONFIG) ffc-probe

clean:
	rm -rf .build "$(BUILD_DIR)"
