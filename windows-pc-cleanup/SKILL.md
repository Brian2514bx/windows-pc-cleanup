---
name: windows-pc-cleanup
description: Safely inspect and tidy up a Windows PC — free disk space by finding temp files, caches, large files, old app versions and duplicate files, review rarely used programs and startup items, and flag possible security concerns (suspicious startup entries, unsigned programs in odd places, risky Minecraft mod .jar files, Defender status). Produces a visual HTML report the user ticks items in. Use this skill whenever the user wants to clean up, organize, speed up, or check their Windows computer, asks what files or programs they can delete, says their disk/C drive is full, asks whether something on their PC is unsafe or a virus, or says things like 整理電腦、清理電腦、電腦變慢、C槽滿了、哪些可以刪、有沒有病毒、開機很慢 — even if they don't name this skill. Scan first, report, and change nothing without the user's per-item approval.
---

# Windows PC Cleanup

Help a non-expert Windows user understand what is taking space and what is running on their PC, then clean up only what they approve. The user is trusting you with their own machine, so the whole skill is built around one idea: **look first, explain clearly, touch nothing without permission, and make every change reversible.**

Talk to the user in their own language (the report and scan dialogs support English and Traditional Chinese; the report follows the Windows display language, and the user can switch it in the top-right corner or open `report.html?lang=en` / `?lang=zh`). Avoid jargon; when you must use a term like "cache" or "startup item", explain it in one short phrase.

## Golden rules

These exist because a cleanup that deletes one wedding photo or breaks Windows is far worse than one that frees no space at all.

1. **Scan is read-only.** The scan scripts only read. Never run a delete, uninstall, or registry change during the scan phase.
2. **Report before acting.** The user picks items in the report (or by number in chat). One approval covers only the items they named.
3. **Recycle Bin, never permanent delete.** Use `scripts/recycle.ps1` (moves to the Recycle Bin). Never empty the Recycle Bin, never use `Remove-Item` / `del` / `rm` on user files. If the user asks to empty the Recycle Bin, tell them the size and that it cannot be undone, then let them do it themselves.
4. **Never touch protected locations.** See `references/windows-locations.md` → "Never touch". This includes `C:\Windows`, `System32`, `WinSxS`, program install folders (uninstall properly instead), game saves, and the user's documents/photos/videos unless the user points at a specific file.
5. **No registry cleaning, no "optimizer" tools, no disabling Windows Defender or Windows Update.**
6. **Security findings are hints, not verdicts.** Say "this looks unusual, here is why, scan it with Defender"; never tell the user a file *is* malware or *is* safe. Real detection belongs to antivirus software.
7. **Programs are uninstalled by the user** through 設定 → 應用程式 → 已安裝的應用程式. Startup items are disabled (reversible) in 工作管理員 → 啟動應用程式, not deleted.
8. **The HTML report never deletes anything.** It only produces a selection that comes back to you. Do not add delete buttons or a local server to it.

## Step 0 — Work out what you can reach

Check whether you can run PowerShell on the Windows host:

```
powershell -NoProfile -Command "$PSVersionTable.PSVersion; $env:USERPROFILE"
```

- **Works (path A):** you run the scan yourself.
- **Fails (path B — e.g. a cloud/Linux sandbox that only sees some of the user's folders):** the user runs the scan by double-clicking `Start-Scan.bat`. Copy the whole `scripts/` folder into a folder the user shared with you (e.g. `Desktop\pc-cleanup`).

Tell the user in one or two sentences which path you're using and why.

## Step 1 — Scan (read-only) and open the visual report

### Path A

```
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "<skill>\scripts\scan.ps1" -OutDir "$env:USERPROFILE\Desktop\pc-scan" -PickFolder
```

Then copy `recycle.ps1` and `run_cleanup.bat` into the same `pc-scan` folder.

### Path B

Give the user these steps in their language:

1. Open the folder you put the scripts in and double-click **`Start-Scan.bat`**.
2. If Windows SmartScreen appears: 其他資訊 → 仍要執行. (The scripts only read; explain that `-ExecutionPolicy Bypass` applies to this one run only.)
3. It asks whether to add more folders/drives (e.g. `D:\`). The picker starts at 本機, so drives are at the top.
4. Wait a few minutes. The report opens in the browser automatically.

### What the scan produces (in `Desktop\pc-scan`)

- `report.html` — the visual report (built from `report_template.html`; opened automatically unless `-NoOpen`)
- `report.json` — full data for you to read
- `report.txt` — short text summary

Options: `-ScanPaths "D:\","E:\"` adds folders without the picker, `-TopN 50` large files to list, `-MinLargeMB 300` size threshold, `-Quick` skips large files and mods, `-NoOpen` doesn't open the browser.

### Folders only (either path)

```
python scripts/scan_folder.py large <folder> --top 50 --min-mb 200
python scripts/scan_folder.py dupes <folder> --min-mb 1
python scripts/scan_folder.py tree <folder> --depth 2
```

`dupes` compares file contents (size first, then SHA-256), so matching names alone never count as duplicates.

## Step 2 — The report and the user's selection

The HTML report already classifies everything; you don't need to write a long report in chat. Read `report.json` yourself as well, and give the user a **short** summary (3–6 lines): drive status, how much is safe to clean, the one or two biggest findings, and any security item worth action. Then tell them:

> 在報告裡勾選要處理的項目，按右下角「複製並交給 Claude」，回到這裡貼上。
> (English: tick the items in the report, press **Copy for Claude**, and paste it here.)

What the report does (in `report_template.html`, all client-side):

- 🟢 safe: known temp/cache folders, crash dumps, leftover updater installers in AppData
- 🟡 check: Adobe render/media caches, **old app versions** (same file under several `x.y.z` version folders — newest is kept automatically), large personal media/archives (each can be set to *delete* or *move to the drive with the most free space*), optional app data like Lunar Client
- ⚪ don't touch: program files, models, website storage, Recycle Bin, Windows Update cache (→ Settings), CurseForge instances (contain saves)
- Programs with hints (duplicate Java/Python/VS Code, second antivirus next to Defender, very large), startup items with keep/disable hints, security checks
- Every actionable item is numbered; the user can also just reply "清 1、3、5"

If the user prefers chat over the HTML, write the report in chat using the same groups, numbered, sorted by size, skipping items under ~50 MB.

Notes for explaining items:

- Caches that rebuild (shader, browser) are safe but the first launch afterwards is slower.
- Old app versions: tell the user to close that app first.
- You can't see when a program was last used — ask rather than guess.
- If another drive has much more free space, suggest **moving** big personal videos instead of deleting them.

## Step 3 — Act only on what the user approved

The pasted text contains the item numbers and a ready `approved.txt` block (one path per line; `folder\*` means "the contents of this folder").

1. Repeat back the item list and total size in one or two lines. If the paste is clear and complete, that counts as approval; otherwise ask for a clear yes.
2. Write `approved.txt` into the `pc-scan` folder (path A: directly; path B: through the shared folder). Do not add paths the user didn't select.
3. Path A: dry run, then execute:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<pc-scan>\recycle.ps1" -ListFile "<pc-scan>\approved.txt"
   powershell -NoProfile -ExecutionPolicy Bypass -File "<pc-scan>\recycle.ps1" -ListFile "<pc-scan>\approved.txt" -Execute -LogFile "<pc-scan>\cleanup-log.txt"
   ```
   Path B: ask the user to close Chrome/Edge/Discord/Steam/games, then double-click **`run_cleanup.bat`** in `pc-scan` — it shows the dry run, waits for a key press, then moves items to the Recycle Bin and writes `cleanup-log.txt`.
4. "Move" items: path A — move with `Move-Item` to a new folder on the target drive (e.g. `D:\從C槽搬來\`), never overwriting; path B — tell the user exactly which files to drag where.
5. Report what was moved, skipped (files in use or protected — normal), and how much space was freed. Remind them that **space is only freed after they empty the Recycle Bin themselves**, and to check it first.
6. Programs and startup items: give click-by-click steps (rule 7).

## Security follow-up

When the scan raises security signals, follow `references/security-checks.md`. Usual order: Windows Security full scan → Microsoft Defender Offline scan → a second-opinion scanner such as Malwarebytes (free). Never suggest disabling Defender or the firewall.

## Privacy

`report.json` and `report.html` contain file names and paths from the user's PC. They stay on the user's computer; only what you read is sent to the model. Mention this if the user asks, and don't copy file names into anything shared or published.

## Files in this skill

- `scripts/Start-Scan.bat` — double-click launcher: folder picker → scan → report opens; copies the cleanup tools into `pc-scan`
- `scripts/scan.ps1` — read-only system scan → `report.json`, `report.txt`, `report.html` (Windows PowerShell 5.1+)
- `scripts/report_template.html` — self-contained visual report; scan.ps1 injects the JSON into it
- `scripts/recycle.ps1` — move approved paths to the Recycle Bin; dry run by default, refuses protected paths
- `scripts/run_cleanup.bat` — double-click wrapper: dry run → confirm → execute
- `scripts/scan_folder.py` — large files, duplicate files and folder-size tree for any folder (Python 3)
- `references/windows-locations.md` — what each common Windows location is and whether it's safe to clean
- `references/security-checks.md` — how to interpret security signals and what to tell the user
