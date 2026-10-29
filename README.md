# SniperClip

**SniperClip** is a lightweight clipboard manager for Windows. It captures the clipboard into a grid of clickable cells: each cell stores a piece of content (text or otherwise), can be given a background color, renamed, and re-pasted with a single click, with a preview on hover.

- **Author**: Vincent VELIO + AI
- **Version**: 1.0
- **Platform**: Windows (PowerShell 5.1 + Windows Forms, no installation required)
- **License**: MIT (Open source) — see the `LICENSE` file

## Features

- Clipboard-capture cell grid, paste in one click.
- Custom background color and name for each cell.
- Content preview on hover, with fonts adapted to cell size.
- Persistent history in an **SQLite** database (`%APPDATA%\SniperClip`).
- Systray icon with a full menu (About, start with Windows, language).
- Global show/hide shortcut (**Ctrl+Alt+V**).
- Resizable window, full screen or half screen; size and position are remembered.
- Taskbar Jump List (most recently used cells).
- Configuration export / import.

## Installation

1. Download `SniperClip.exe` from the [releases page](https://github.com/Denden294/SniperClip/releases).
2. Put it wherever you like (e.g. `%LOCALAPPDATA%\SniperClip\`) and run it: no installation is required.
3. On first launch, Windows may display a SmartScreen warning: click "More info" and then "Run anyway" (the exe is not yet known to Microsoft).

Data (database, backup, log) is stored in `%APPDATA%\SniperClip`.

## Building from Source

The executable is generated from `SniperClip.ps1` with the build kit:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The script creates an adapted copy in `build\`, compiles it with [ps2exe](https://www.powershellgallery.com/packages/ps2exe) into `dist\SniperClip.exe`, and copies `LICENSE` and `README.md` there. Options: `-Sign -SelfSigned` to sign the exe with a local self-signed certificate, or `-Thumbprint <thumbprint>` for an OV/EV certificate.

## License

Code distributed under the **MIT** license — see the `LICENSE` file. You are free to use, modify, and redistribute it, provided you keep the copyright notice.
