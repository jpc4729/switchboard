# Switchboard

Switchboard is a small, open source macOS menu bar app. It changes the input of each monitor that is connected to your Mac, so one monitor can show your Mac or another device without a cable change.

Status: the Must version is implemented. It is not tested on hardware yet.

## What it does

- A menu bar icon only. No Dock icon.
- Any number of screens and devices. You give each one a name.
- For each screen, the menu shows the Mac, each device and Off. A checkmark shows the current choice.
- When a screen shows a device, the Mac stops using that screen, so your windows move to the screens that you can see.
- Back to Computer turns all screens on again and switches each one back to the Mac. The shortcut is ⌃⌥⌘B. Quit, logout and restart also do this. If another app uses ⌃⌥⌘B, Switchboard tells you at launch, and you use the menu.
- The last screen always stays on. You select what the Mac does then: sleep or keep running.
- The menu bar shows the device names when a screen is away, and a warning icon when an action failed. Errors are in plain words.
- Setup finds each external screen, reads which input the Mac is on, and lets you name the device on each other input. A Test button shows the device for 5 seconds and then switches back to the Mac. Setup opens at first launch and from Set Up Screens… in the menu.

## Requirements

- macOS 13 or later.
- Apple Silicon. Intel Macs are not supported for input switching.
- Monitors with DDC/CI on. Most monitors have this setting in their own menu.

## Build and run

```sh
./scripts/bundle.sh
open build/Switchboard.app
```

For a debug build, use `swift build`. To build the rule tests, use `swift build --build-tests`. To run them, use `swift test`.

The maintainers run commands through a `quiet` wrapper. It is optional, and the repo does not need it.

## Privacy

Switchboard works offline. It collects nothing and sends nothing.

## Design notes

- Switchboard changes the monitor input with DDC/CI (VCP code 0x60) through the private Apple Silicon `IOAVService` calls. The code follows [MonitorControl](https://github.com/MonitorControl/MonitorControl) and [m1ddc](https://github.com/waydabber/m1ddc).
- macOS has no public API to disconnect a display. Switchboard uses the private CoreGraphics call `CGSConfigureDisplayEnabled`, inside a public `CGBeginDisplayConfiguration` and `CGCompleteDisplayConfiguration` transaction. [LightsOut](https://github.com/AlonX2/LightsOut) and [ScreenOff](https://github.com/zy0816/ScreenOff) use the same call.
- Because of the private APIs, Switchboard cannot be on the Mac App Store.
- A switch sends DDC first. If DDC fails, nothing changes.
- Some monitors do not accept DDC on an input that is not shown. Then Back to Computer turns the screen on again in macOS, and you select the Mac with the screen's own button. The order does not matter.
- The change uses the `.forSession` scope, so a logout or a restart turns all displays on again.
- A disabled display goes out of the system display lists. Switchboard saves the IDs and UUIDs of the displays that it disabled, so that it can turn them on again with their settings, also after a crash.
- macOS can report an error for a display change that worked. Switchboard reads the real display state and reports an error only when the state did not change.
- Switchboard never disables the last real screen. It keeps that screen on and, if you selected Sleep, puts the Mac to sleep.
- If no real screen is left on, for example after you disconnect a monitor, Switchboard does Back to Computer. It does not do this when you sent the last screen to a device yourself.
- Display and DDC calls can block for some seconds. Switchboard runs them on one background queue.

## License

[MIT](LICENSE)
