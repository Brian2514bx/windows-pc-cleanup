# Changelog

## v2.0.0 — 2026-11-12
- 新增視覺化 HTML 報告（`report_template.html`）：分級勾選清單、磁碟長條、最大資料夾、程式建議、開機項目、安全性檢查，以及「複製並交給 Claude」和下載 `approved.txt`
- 新增 `Start-Scan.bat`：雙擊掃描、可選額外資料夾或磁碟，掃完自動打開報告
- `scan.ps1`：新增 `-PickFolder`（選擇視窗從「本機」開始）和 `-NoOpen`，自動產生 `report.html`
- 新增舊版本殘留偵測（同一個程式的多個 x.y.z 版本資料夾，會保留最新版）
- 大型個人檔案可以選擇「搬到其他磁碟」
- 新增 `run_cleanup.bat`：先試跑 → 確認 → 移到資源回收筒，並寫入記錄檔
- 中英雙語：報告依照 Windows 語言自動選擇，右上角可以切換（切換時保留勾選）；資料夾選擇視窗也是雙語
- 修正：開機自動啟動清單在 Windows PowerShell 5.1 上會是空的

## v1.0.0
- 初版：唯讀掃描（`scan.ps1`）、移到資源回收筒（`recycle.ps1`）、資料夾工具（`scan_folder.py`）
