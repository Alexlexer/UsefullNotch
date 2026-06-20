# Useful Notch

A small macOS app experiment for making the MacBook notch useful while learning Swift.

The first scaffold is a menu bar app that shows a floating panel centered near the top of the screen. It is intentionally small so the project stays easy to understand and evolve.

Current behavior:

- Hover near the notch area to reveal the panel.
- Enjoy a smooth animated reveal with a soft ambient glow.
- Drop files onto the panel to keep a small temporary shelf of recent files.
- Feel lightweight trackpad haptics when the panel opens or files are added on supported Macs.
- Click the menu bar laptop icon to show or hide the panel manually.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain or newer
- Full Xcode is recommended for app development, previews, signing, and debugging

## Run

From the project root:

```sh
swift run UsefulNotch
```

The app appears in the menu bar. Move your pointer near the top-center notch area to show the panel, drop files onto it, or click the laptop icon to show or hide it manually.

## Project Direction

Good next learning steps:

- Open dropped files from the shelf.
- Persist the shelf between launches.
- Add quick widgets: calendar, timers, clipboard history, and media controls.
- Package the executable as a signed `.app`.

## Notes

This is currently a Swift Package executable that uses AppKit directly. That keeps the repository simple and terminal-friendly while the project is still taking shape.
