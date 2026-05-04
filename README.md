# Hello – Releases

This repository contains official releases for **Hello**, a Lua-first game framework.

> Source code is maintained in a private repository. This public repo exists solely to distribute builds to players.

## Download

Go to the [Releases](../../releases) tab and download the latest `hello-x86_64-pc-windows-msvc.zip`.

Extract the zip and run `hello.exe`. The game will check for updates automatically on each launch.

## Automatic Updates

When you launch `hello.exe` it will:

1. Check this repo for a newer binary — if found, it updates itself and asks you to relaunch
2. Check for new, changed, or removed asset files and sync them automatically

Pass `--skip-update` to bypass both checks for a session.

## Platform Support

| Platform | Status |
|---|---|
| Windows (x86_64) | ✅ Supported |
| macOS | Planned |
| Linux | Planned |

## Third-Party Licenses

Hello is built on open source dependencies (Bevy, Rapier, mlua, and others) released under MIT, Apache-2.0, and similar licenses. Their full license texts are included in every release as `THIRD_PARTY_LICENSES.html` alongside `hello.exe`.
