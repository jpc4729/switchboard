# Contributing to Switchboard

Thank you for your help. Switchboard is a small app, and these rules keep it small.

## Before you start

- Open an issue before you open a pull request. Tell us the problem first. Then we can agree on a fix before you write code.
- For a bug, use the bug report form.
- For a monitor that works or does not work, use the monitor report form. These reports help most, because the maintainers cannot test every monitor.
- For an idea, use the feature request form.

## Pull requests

- Make small, focused changes. One pull request does one thing.
- Do not add new dependencies.
- Follow the style of the code around your change.
- Write commit messages with [Conventional Commits](https://www.conventionalcommits.org/), for example `fix: keep the last screen on after wake`.
- Tell us how you tested the change. Tell us which Mac and which monitors you used, if the change touches displays or DDC.

## Build and check

You need macOS 13 or later and Apple Silicon.

```sh
swift build
swift build --build-tests
swift test
./scripts/bundle.sh
```

`swift build` makes a debug build. `swift build --build-tests` builds the rule tests, and `swift test` runs them. `./scripts/bundle.sh` makes `build/Switchboard.app`.

If you change a shell script, run `shellcheck` on it.

Make sure that all of these pass before you open a pull request. CI runs them too.

## Decisions

The maintainer decides what goes into Switchboard. A good change can still be out of scope. If we say no, we tell you why.

## Security

Do not report a security problem in a public issue. Read [SECURITY.md](SECURITY.md).
