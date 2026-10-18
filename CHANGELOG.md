# Changelog

All notable changes to this project are in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- An alert no longer stops ⌃⌥⌘B, the menu bar state and Quit from finishing while it is open.
- A display that turns off a moment after the change is now saved as turned off.
- At launch, Switchboard checks the screens, so screens that a crash left off come back when no screen is on.
- Screens kept on while they show a device are saved, so Keep Running still holds the Mac awake after a relaunch. Back to Computer and Quit forget a kept screen that is no longer connected.
- Display IDs saved before a restart are ignored, so no unknown display shows in the menu.
- A DDC reply that has no input value, such as a busy monitor's null message, is no longer read as input 0.
- The warning icon stays after a failed switch until the next action.
- The 30-second input check also runs while the menu or an alert is open.
- Setup's Test no longer makes Back to Computer wait 5 seconds, and one Test runs at a time.
- Sleep reports an error when `pmset` fails.
- A prerelease build has only numbers and dots in `CFBundleVersion`.

### Changed

- ⌃⌥⌘B is registered exclusively. The menu says that another app uses it only when that app holds it exclusively, and the lid alert tells you what to do if ⌃⌥⌘B does nothing.
- On an Intel Mac, a switch to a device says that it needs Apple silicon.
- Switchboard saves the config only when it changes, and checks the screens once per burst of screen changes.

## [0.1.0] - 2026-10-18

### Added

- Menu bar app with no Dock icon.
- A menu with each screen. For each screen you select the Mac, a device or Off. A checkmark shows the current choice.
- When a screen shows a device or is off, the Mac stops using that screen.
- Back to Computer turns all screens on and switches each one back to the Mac. The shortcut is ⌃⌥⌘B. Quit, logout and restart also do this. If another app uses the shortcut, Switchboard tells you at launch.
- The menu bar shows the device names when a screen is away, and a warning icon when an action failed.
- When you open the menu, Switchboard reads the input of each set-up screen.
- Setup finds each external screen and reads its input. Test shows an input for 5 seconds. You can add other input codes (1 to 255).
- Set Up Screens… in the menu, and Set Up This Screen… on a new screen.
- After the Mac wakes, Switchboard checks the screens again.
- The last screen always stays on. When No Screen Is Left in the menu selects Sleep or Keep Running. Keep Running holds a power assertion that prevents idle sleep.
- A warning before a switch would leave a Mac with a closed lid running with no screen.
- Open at Login in the menu.
- Open Window shows the same controls in a small window.
- `switchboard://back` and `switchboard://switch?screen=<screen>&to=<to>` links for other apps.
- `switchboard` command line tool with `back`, `switch` and `--print`. It ships inside the app.
- App icon from `assets/logo.png`.
- CI workflow that builds, tests and lints each push to main and each pull request.
- Release workflow that publishes `Switchboard-X.Y.Z.zip` for a `v*` tag. Signing and notarization turn on only when the Developer ID secrets exist.
- Homebrew cask template for the `jpc4729/tap` tap.

[Unreleased]: https://github.com/jpc4729/switchboard/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jpc4729/switchboard/releases/tag/v0.1.0
