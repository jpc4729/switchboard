# Homebrew tap setup

`switchboard.rb` is the cask template. The release workflow copies it to the tap as `Casks/switchboard.rb` and replaces the lines that start with `  version "` and `  sha256 "`. Keep those two lines in that form.

One-time setup:

1. Create the public repo `jpc4729/homebrew-tap` with an empty `Casks/` folder.
2. Create a fine-grained personal access token with access to `jpc4729/homebrew-tap` only and the permission Contents: Read and write.
3. In `jpc4729/switchboard`, save that token as the Actions secret `HOMEBREW_TAP_TOKEN`.

Without the secret, the release still runs; it only skips the tap bump.

The `caveats` block says that the app is not notarized. When a release is notarized, the workflow removes that block from the tap's copy. Keep the block's first line as `  caveats <<~EOS` and its last line as `  EOS`, or the release stops with an error.

Users install with:

```sh
brew install --cask jpc4729/tap/switchboard
```

Check the template after a change. `brew style` uses the cask rules only for a file in a `Casks/` folder, so the check copies it into one:

```sh
dir="$(mktemp -d)/Casks" && mkdir -p "$dir" && cp packaging/homebrew/switchboard.rb "$dir/" && brew style "$dir/switchboard.rb"
```
