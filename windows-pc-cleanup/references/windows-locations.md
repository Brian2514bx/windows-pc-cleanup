# Windows locations: what they are and whether to clean them

Use this to classify anything in the scan. When unsure, put it in "needs confirmation" and explain why — never guess toward deleting.

## 🟢 Safe to clean (rebuilds itself or is pure leftovers)

| Location | What it is | Notes for the user |
|---|---|---|
| `%TEMP%` (`%LOCALAPPDATA%\Temp`) | Temporary files programs forgot to remove | Files in use are skipped automatically; that's normal |
| `C:\Windows\Temp` | System temp files | Needs admin; skipped files are normal. Recycle via `C:\Windows\Temp\*` |
| `%LOCALAPPDATA%\CrashDumps`, `ProgramData\Microsoft\Windows\WER` | Crash dumps and error reports | Only useful when debugging a crash |
| `%LOCALAPPDATA%\D3DSCache`, `NVIDIA\DXCache`, `NVIDIA\GLCache` | Graphics shader caches | Rebuild automatically; the next launch of each game may stutter briefly. Don't clear these as a routine — only when space is tight or a game has graphics glitches |
| Browser `Cache` / `Code Cache` folders (Chrome, Edge) | Cached web pages and images | Close the browser first. Does **not** remove passwords, history, or logins |
| `%APPDATA%\discord\Cache`, `Code Cache` | Discord's media cache | Close Discord first |
| `%LOCALAPPDATA%\Steam\htmlcache` | Steam store page cache | Close Steam first |
| `.minecraft\logs`, `.minecraft\crash-reports` | Old game logs | Keep the newest crash report if the user is troubleshooting a crash |

The cleanest route for system temp files and the Windows Update cache is **設定 → 系統 → 存放裝置 → 暫存檔案** (Settings → System → Storage → Temporary files). Suggest it; it's built into Windows and handles permissions properly. "存放裝置感知" (Storage Sense) can do this automatically.

## 🟡 Needs the user's confirmation

| Location | Why |
|---|---|
| `Downloads` | Mixes installers (usually safe to remove) with documents the user may need. Go item by item, largest first. Old installers (`.exe`, `.msi`, `.zip` of a program already installed) are typical easy wins |
| Large video files (`.mp4`, `.mkv`, `.mov`) — OBS recordings, replay folders | Often the biggest space users. Only the user knows which recordings matter. Suggest moving keepers to another drive or cloud before deleting |
| Duplicate files | Confirm which copy to keep; prefer keeping the one in the more "organized" folder |
| CurseForge `Instances\<modpack>` | Each modpack is self-contained, **including its worlds** in `saves\`. Only remove a whole modpack the user confirms they don't play, and offer to back up `saves` first |
| Old Java runtimes (e.g. `.lunarclient\jre`, old JDKs in Program Files) | Remove only if the launcher/app that uses them is gone. Launchers bundle their own Java; deleting the folder of an app still in use breaks it |
| Android emulators (LDPlayer, BlueStacks, Nox), VMs | Their disk images are huge. Uninstall through Settings if unused; don't delete image files by hand |
| `Windows.old` | Previous Windows version after an upgrade. Safe to remove **only** via Settings → Storage → Temporary files ("先前的 Windows 安裝"), after the user is sure they won't roll back |
| Recycle Bin | Emptying is permanent. Let the user review and empty it themselves |
| `hiberfil.sys` | Hibernation file. Can be shrunk/removed with `powercfg /h off` but that disables hibernation and Fast Startup; only mention if space is critical and the user agrees |

## ⚪ Never touch

- `C:\Windows` and everything inside (`System32`, `SysWOW64`, `WinSxS`, `Installer`, `assembly`, `Prefetch`). Use Disk Cleanup / Storage settings for WinSxS cleanup; never delete by hand.
- `C:\Program Files`, `C:\Program Files (x86)` — program files. Uninstall via Settings → Apps instead.
- `C:\ProgramData\Microsoft`, `C:\Recovery`, `System Volume Information`, `$Recycle.Bin` internals, `pagefile.sys`, `swapfile.sys`, boot files.
- Driver stores (`C:\Windows\System32\DriverStore`), NVIDIA/AMD install folders.
- `%APPDATA%` and `%LOCALAPPDATA%` as a whole. Only the specific cache subfolders listed above.
- Game saves: `.minecraft\saves`, `Instances\*\saves`, `Documents\My Games`, `Saved Games`, Steam `userdata`.
- The user's own Documents, Pictures, Videos, Desktop — unless the user points at specific files.
- Anything inside OneDrive without asking: deleting there deletes it from the cloud and other devices too.

## Programs: what to point out

From `report.programs`, worth raising with the user:
- Several programs doing the same job (multiple Minecraft launchers, several Java versions, two Android emulators, multiple PDF readers).
- Very large programs (`sizeMB`) the user may not use.
- Toolbars, "PC optimizer"/"driver updater"/"registry cleaner" products and bundled adware — these are commonly unwanted.
- Old runtimes (Java 8 updaters, old Visual C++ redistributables): **don't** suggest removing Visual C++ redistributables or .NET — games and apps depend on them silently.

Never tell the user a program is unused — you can't see usage. Ask: "這些你還有在用嗎？"

## Startup items

Things that are usually fine to disable at startup (still work when opened manually): game launchers (Steam, Epic, CurseForge, Lunar), Discord, Spotify, OneDrive (if not syncing), Teams, emulator helpers, updaters.
Keep enabled: antivirus, audio/touchpad/graphics drivers (Realtek, NVIDIA, Synaptics/ELAN), laptop vendor control software for fans/keyboard (e.g. Acer NitroSense / PredatorSense), Windows Security.
Disable via 工作管理員 → 啟動應用程式 → right-click → 停用 (fully reversible).
