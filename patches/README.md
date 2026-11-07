# Patches

These patches are applied, in the order of their numbers, on top of upstream
[settlers-remake](https://github.com/paulwedeck/settlers-remake) pull request #92 (commit `47d1d4e`) by `build-jsettlers-macos-dmg.sh`.
They are the same patches that are embedded in the script; see the [changelog](../CHANGELOG.md) for what each one does.

To apply them by hand:

```
git clone https://github.com/paulwedeck/settlers-remake.git
cd settlers-remake
git fetch origin pull/92/head && git checkout FETCH_HEAD
for p in /path/to/patches/*.patch; do git apply --whitespace=nowarn "$p"; done
```

Not covered by the patches (done by the build script with small text replacements): JOGL as default graphics backend on macOS and the version label.
