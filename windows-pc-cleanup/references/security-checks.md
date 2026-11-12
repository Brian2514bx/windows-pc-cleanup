# Security checks: how to interpret and what to tell the user

The scan collects signals, not verdicts. Your job is to turn them into calm, specific next steps. Do not frighten the user, and do not reassure them that something is safe when you can't know.

## Wording

- Good: 「這個開機項目是從『下載』資料夾執行的，而且沒有數位簽章，這不太常見。建議用 Windows 安全性掃描這個檔案。」
- Bad: 「這是病毒。」/「這個絕對安全。」
- If nothing stands out: say so in one line, and still recommend a periodic full scan if `lastFullScan` is old or empty.

## Signals in `report.security`

### `defender`
- `antivirusEnabled` or `realTimeProtection` is false → most important finding. Unless the user has another antivirus installed (check `programs` for Norton/McAfee/ESET/Kaspersky/Avast/Bitdefender etc.), tell them to turn it back on in Windows 安全性 → 病毒與威脅防護.
- `signatureAgeDays` > 7 → suggest checking for updates (Windows Update).
- `lastFullScan` empty or older than ~3 months → suggest a full scan.
- `"unavailable"` → likely a third-party antivirus; tell the user to run a full scan with whatever they use.

### `recentThreats`
Defender already found something. Report what and when, and whether `actionSuccess` is true. If false, or the same threat repeats, recommend a **Microsoft Defender 離線掃描** (Windows 安全性 → 病毒與威脅防護 → 掃描選項 → Microsoft Defender 離線掃描; the PC restarts and scans before Windows loads).

### `flaggedStartup`
Flags and how much they matter:
- `runs-from-temp-or-downloads` — **high attention**. Legit software almost never auto-starts from Temp or Downloads.
- `exe-directly-in-appdata` (an .exe sitting right in `AppData\Roaming\` or `AppData\Local\`, not in its own subfolder) — **high attention**, common malware pattern.
- `script-or-unusual-type` (.vbs, .js, .bat, .ps1, .jar autostarting) — **medium**; some tools do this legitimately, many malware families too.
- `not-validly-signed` — **low on its own**. Lots of small/indie/open-source programs aren't signed. Only meaningful combined with another flag or an unknown name.
- `file-missing` — leftover entry from an uninstalled program. Harmless; can be disabled in Task Manager.

For anything high-attention: give the user the full path, suggest scanning that file with Defender (right-click → 使用 Microsoft Defender 掃描), and disabling it in Task Manager → 啟動應用程式 until checked.

### `recentExecutablesInTempOrDownloads`
Mostly installers the user downloaded. Point out unsigned ones with odd names, and ones the user doesn't recognize. Old installers are also an easy space win.

### `fractureiserIndicators`
The 2023 "fractureiser" malware spread through compromised Minecraft mods on CurseForge and Bukkit. Its Windows stage left files in `%LOCALAPPDATA%\Microsoft Edge\` (note the **space** — the real Edge folder is `Microsoft\Edge`) such as `libWebGL64.jar`, plus a startup entry pointing there.
- If anything is listed: take it seriously. Tell the user not to log in to important accounts from this PC until cleaned, run Defender full + offline scans, then a second scanner, and change passwords (Microsoft/Minecraft, Discord, browser-saved passwords, email) **from a different, clean device**. Suggest they look up the official fractureiser cleanup guide.
- If empty: say this specific known threat wasn't found. That doesn't prove mods are safe in general.

### `minecraftModJars`
You can't judge a jar's safety from its name. Useful advice:
- Mods should come only from CurseForge or Modrinth (official sites/launchers). Jars the user got from Discord, YouTube links or random sites are the real risk.
- Jars with very recent `modified` dates that the user didn't knowingly add deserve a look.
- The `sha256` lets the user (or you, with web access) look a file up on Modrinth or VirusTotal. Uploading a hash reveals nothing private; uploading a file shares it with the VirusTotal community, so suggest searching by hash first.

## Recommended scan order to give the user

1. Windows 安全性 → 病毒與威脅防護 → 掃描選項 → **完整掃描**
2. If anything was found, or signals above are high-attention → **Microsoft Defender 離線掃描**
3. Second opinion: **Malwarebytes** free version (on-demand scan; it doesn't need to stay installed)

Never suggest: disabling Defender, Firewall, UAC or SmartScreen; "cracked" tools; registry cleaners; downloading random "virus removal" tools from ads.
