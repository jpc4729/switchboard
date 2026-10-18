# Changelog

All notable changes to this project are in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
