[![macOS 10.10+](https://img.shields.io/badge/macOS-10.10+-888)](#install)
[![Current release](https://img.shields.io/github/release/relikd/Memmon)](https://github.com/relikd/Memmon/releases)

<img src="img/icon.svg" width="180" height="180" style="margin: 0 10px; float: right;">

# Memmon

Memmon remembers what your Mac forgets – A simple deamon that restores your window positions on external monitors.

## FAQ

### Why‽

I am frustrated! Why does my Mac forget all window positions which I moved to a second screen? Every time I unplug the monitor. Every time I close my Macbook lid. Every time I lock my Mac.

Is it macOS 11? Is it the USB-C-to-HDMI converter dongle (notably one made by Apple)? Why do I have to fix things that Apple should have fixed long ago? …


### Aren't there other solutions?

Yes, for example [Mjolnir](https://github.com/mjolnirapp/mjolnir) or [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) (and some comercial ones). But I do not need a full-fledged window manager. Nor the dependencies they rely on. I just need to fix this damn bug.


### What is it good for?

First off, Memmon is just 130 lines of code – no dependencies. You can audit it in 5 minutes. Or just build it from scratch if you like (just run `make`).

Secondly, it does one thing and one thing only: Save and restore window positions whenever your monitor setup changes.


## Install

1. You will need macOS 10.10 or newer.
2. Grant Memmon the Accessibility privilege. Go to "System Preference" > "Security & Privacy" > "Accessibility" and add Memmon to that list. Otherwise, you can't move other application windows around and the app has no purpose.
3. Thats it. The app runs in your status bar.


### Hide Status Icon

You can hide the status icon either via the same-titled menu entry. If you do so, the only way to quit the app is by killing the process (with Activity.app or `killall Memmon`).

If you like to hide the icon directly on launch, use this app-setting:

```sh
# disable status icon completely
defaults write de.relikd.Memmon invisible -bool True
# re-enable status icon
defaults delete de.relikd.Memmon invisible
```
