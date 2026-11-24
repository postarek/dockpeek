# Changelog

Versions follow [semver](https://semver.org): patch for fixes, minor for new features, major for big
changes. Bump with `./build.sh --bump [patch|minor|major]`. Each section below becomes the release notes
shown in DockPeek's update prompt, so it is written in English.

## 1.2.6 — 2026-11-24

- Fixed: holding the Dock open while the pointer is in a preview no longer makes macOS reserve the
  Dock's space, so desktop icons stay put and apps filling the screen are no longer resized. The Dock
  hides again normally when the pointer leaves the preview.

## 1.2.5 — 2026-11-18

- Fixed: the auto-hiding Dock often stayed stuck open after using a preview. DockPeek again keeps the
  Dock up by turning auto-hide off only while the pointer is inside a preview, and back on as soon as it
  leaves. While it is off, macOS reserves the Dock's space, so desktop icons that are sorted
  automatically may move; use View › Sort By › None on the desktop to avoid that.
- The preview now sits just above the Dock icons (10 pt), so there is almost no gap to cross on the
  way in (crossing it made the Dock start hiding and flicker). It could also drift far above the Dock.
- The preview has a small tail pointing at its Dock icon, like the Dock's own name label.
- The preview opens together with the hover and closes together with the Dock: the window list is kept
  ready while the pointer is near the Dock, the pointer is tracked as it moves, and both delays now
  default to 0 ms (still adjustable in System Settings › DockPeek).

## 1.2.4 — 2026-11-16

- Fixed: desktop icons rearranged while a preview was open. DockPeek no longer turns Dock auto-hide off
  to keep the Dock up; while the pointer is in a preview it tells the Dock the pointer is still on the
  icon, so the Dock stays up floating, without reserving screen space.
- The preview fades in and out very quickly instead of popping.

## 1.2.3 — 2026-11-16

- The preview now fully covers the Dock's own app-name label instead of leaving it visible below.
- The preview has a dark, solid background, in both light and dark mode.
- Fixed: the preview flickered (closed and reopened) when moving between Dock icons. Recently seen
  window thumbnails now show right away.

## 1.2.2 — 2026-11-16

- Fixed: with Dock magnification, the preview jumped when it appeared and wobbled while the pointer
  moved over the Dock. It now sits above the fully magnified icon and stays still.
- Fixed: coming out of Dock auto-hide, the preview could appear stuck down at the Dock's base.
- The preview background is no longer see-through, so the Dock's own app-name label doesn't show
  behind it.

## 1.2.1 — 2026-11-16

- System Settings › DockPeek shows the version at the top, next to the running status.

## 1.2.0 — 2026-11-16

- New "Hide delay" setting in System Settings › DockPeek: how long the preview stays after the pointer
  leaves it. Default is now 150 ms (it was a fixed 300 ms), and the preview reacts faster.

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
