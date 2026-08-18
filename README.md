<img width="338" height="372" alt="Screenshot 2026-08-18 at 4 55 28 PM" src="https://github.com/user-attachments/assets/d1ef02d2-4987-435b-87e7-e668086c5724" />

# Fan Control

Menu bar app for Apple Silicon Macs. Pin the fans at hardware max, or give them back to Apple's thermal curve.

Apple Silicon often keeps fans off until the chip is already hot. This is for when you want them spinning now.

Verified on a MacBook Pro M5 Max running macOS 26.

## Usage

- **Left click** the menu bar fan: toggle Max / Auto
- **Right click**: open the panel
- Filled blades = Max. Outline = Auto.

Max does not survive sleep. Click Max again after wake, or use Auto.

## Install

Needs Command Line Tools (`xcode-select --install`). No Homebrew, Xcode, or Swift.

```bash
make install
make setup-sudo
open ~/Applications/FanControl.app
```

`make setup-sudo` lets the menu bar app run `max` and `auto` without a password prompt. It only allows those two commands.

## CLI

```bash
fanctl list
sudo fanctl max
sudo fanctl auto
```

## Warning

This writes SMC fan keys. Use it to pin fans at the hardware maximum or to restore automatic control. Setting fans too low can overheat the machine. There is no warranty.

Manual mode can reset on sleep or reboot.

## Credits

SMC unlock behavior follows public research in [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) and [2dubu/macfanctl](https://github.com/2dubu/macfanctl).
