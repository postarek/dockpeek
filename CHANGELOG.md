# Changelog

Versions follow [semver](https://semver.org): patch for fixes, minor for new features, major for big
changes. Bump with `./build.sh --bump [patch|minor|major]`. Each section below becomes the release notes
shown in DockPeek's update prompt, so it is written in English.

## 1.1.1 — 2026-11-16

- With Dock auto-hide on, the Dock now stays visible while you move into a preview, instead of hiding
  and leaving the preview floating. Can be turned off in System Settings › DockPeek.

## 1.1.0 — 2026-11-16

- DockPeek now updates itself: it checks GitHub for new versions and installs them with one click.
- New "Check for Updates…" menu item, plus an automatic-check option in System Settings › DockPeek.

## 1.0.2 — 2026-11-16

- Fixed: the preview could appear after the pointer had already left the icon and stay stuck open.

## 1.0.1 — 2026-11-16

- Fixed: the preview stayed open after the Dock hid or the pointer left the icon quickly.
- The version is shown in the menu bar menu.

## 1.0.0 — 2026-11-16

- First version: window previews on Dock hover, System Settings pane, guided permission setup and
  `.pkg` installer.
