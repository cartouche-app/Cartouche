## Summary

<!-- What changes, and why. -->

## How it was tested

<!-- Commands run, devices and iOS versions, CI runs. For a fix: the test that fails without it, and where it runs. -->

## Checklist

- [ ] A fix comes with a test that fails without it: unit, storage, UI or Python, where the bug was.
- [ ] Nothing in this pull request contains or links to games, keys or firmware.
- [ ] Changes to LiveContainer or SideStore are patches in `app/patches/`, not edits to the submodules.
- [ ] A change to the launcher that makes sense on a Mac reaches Cartouche's console there: a file the Mac shares, or `builder/mac/console/unshared.json` with its reason.
- [ ] A change players can see shows them before and after, in screenshots.
- [ ] No version raised and no release notes written: the pull request of a version does that.
- [ ] Docs are updated where behaviour changes.
