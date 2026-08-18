PREFIX  ?= /usr/local
APPDIR  ?= $(HOME)/Applications
BUILD   := build
APP     := FanControl.app

.PHONY: all helper app install setup-sudo uninstall clean

all: helper app

helper: $(BUILD)/fanctl

$(BUILD)/fanctl: src/fanctl.c
	mkdir -p $(BUILD)
	clang -O2 -Wall -Wextra -o $@ $< -framework IOKit

app: $(APP)/Contents/MacOS/FanControl

$(APP)/Contents/MacOS/FanControl: src/FanControl.m src/Info.plist
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp src/Info.plist $(APP)/Contents/Info.plist
	clang -fobjc-arc -O2 -fmodules -framework Cocoa -o $@ src/FanControl.m
	codesign --force --sign - $(APP)

install: all
	sudo install -m 755 $(BUILD)/fanctl $(PREFIX)/bin/fanctl
	mkdir -p $(APPDIR)
	rm -rf $(APPDIR)/FanControl.app
	cp -R $(APP) $(APPDIR)/FanControl.app

setup-sudo:
	sudo cp sudoers/fanctl /etc/sudoers.d/fanctl
	sudo chmod 440 /etc/sudoers.d/fanctl
	sudo visudo -cf /etc/sudoers.d/fanctl

uninstall:
	sudo rm -f $(PREFIX)/bin/fanctl /etc/sudoers.d/fanctl
	rm -rf $(APPDIR)/FanControl.app

clean:
	rm -rf $(BUILD) $(APP)
