# Security policy

## Supported versions

Only the latest release gets security fixes. Update to the latest release before you report a problem.

## Report a problem

Do not open a public issue for a security problem.

Use GitHub private vulnerability reporting:

1. Go to the [Security tab](https://github.com/jpc4729/switchboard/security) of this repo.
2. Select Report a vulnerability.
3. Tell us what the problem is, how to make it occur, and which version and macOS version you use.

We reply as soon as we can. We tell you when a fix is ready, and we give you credit if you want it.

## Scope

These parts are in scope:

- Private APIs: Switchboard uses private Apple calls for DDC/CI (`IOAVService`) and to turn displays off and on (`CGSConfigureDisplayEnabled`). Report a way to misuse these calls through Switchboard.
- Display state: Report a way to leave the Mac with no screen that you can see, or to stop Switchboard from turning the screens on again.
- URL scheme input: Other apps can open `switchboard://` links. Report input to these links that makes Switchboard crash, act in a way that the link does not ask for, or do something without your consent.

These parts are out of scope:

- A monitor that does not accept DDC/CI. Use the monitor report form for this.
- A warning from macOS at first launch of a release that is not notarized. The README tells you how to open it.
