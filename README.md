# Quick File Search

A small Windows desktop tool to search for files anywhere on the computer, filtered by basic file types.
Built with PowerShell + WinForms, so it needs nothing installed beyond Windows itself.

## Download

Grab `QuickFileSearch.exe` from the [latest release](https://github.com/lakshithalk/QuickFileSearch/releases/latest) and run it. No installation required.

The exe is not code-signed, so Windows SmartScreen may show "Windows protected your PC" the first time. Click **More info**, then **Run anyway**.

## Run from source

Double-click `QuickFileSearch.cmd`.

Or from a PowerShell prompt:

```powershell
powershell -ExecutionPolicy Bypass -STA -File .\QuickFileSearch.ps1
```

## Build the exe yourself

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

This installs the `ps2exe` module for the current user if needed and writes `dist\QuickFileSearch.exe`. Pushing a tag such as `v1.0.1` to GitHub runs the same build in GitHub Actions and attaches the exe to a release.

## Use

1. **Look in**: pick `All drives`, a single drive, a common folder, or click `Browse...` for any folder. You can also type a path.
2. **Name**: part of the file name (`report`), or a wildcard pattern (`*.pdf`, `inv??ce*`). Leave it empty to list every file of the chosen types.
3. **File types**: tick `All types`, or untick it and pick categories: Documents, Images, Videos, Audio, Archives, Code, Executables.
4. Press **Search** (or Enter). Results stream in while the scan runs. Press **Stop** at any time.
5. Double-click a result (or press Enter) to open it. Right-click for `Open containing folder` and `Copy full path`.

`Skip Windows / Program Files / hidden folders` is on by default to keep whole-drive searches fast. Untick it if you need to search inside those locations.

## Add your own file types

Edit the `$script:Categories` table at the top of `QuickFileSearch.ps1`. Add extensions to an existing category or add a new category line. The checkboxes are generated from that table.

## Optional: run it from anywhere

Create a shortcut to `QuickFileSearch.exe` (or `QuickFileSearch.cmd`) on the Desktop or pin it to the taskbar / Start menu.

## Developer

[lakshithalk](https://github.com/lakshithalk)

## License

MIT. See [LICENSE](LICENSE).
