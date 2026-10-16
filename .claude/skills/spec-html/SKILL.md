---
name: spec-html
description: 把 ICLAB lab 的題目 PDF (docs/LabXX_*.pdf) 整理成規格書風格的 docs/spec.html：編號章節、booktabs 表格、JS 繪製的 SVG 圖、Fig/Table 自動編號、左側固定目錄，淺色、Source Serif + Inter/Noto Sans TC 字體。Use when the user asks to 整理題目 / 寫 spec / 做 spec.html / 用規格書的方式講解題目 / 把 PDF 做成 html，或要在既有的 spec.html 新增章節、補圖、重新編號、調整樣式，即使沒有明講 "spec-html"。Not for writing RTL, PATTERN, or DV code.
---

# spec-html

把 lab 題目整理成一份「規格書」：讀者打開就知道 DUT 要做什麼、每一步怎麼算、哪些規定要驗證。樣式、繪圖 helper、目錄與編號的 JS 都在 `assets/template.html`，從它開始寫，不要重新設計。

## 檔案

| 檔案 | 用途 |
|---|---|
| `assets/template.html` | 完整的 CSS、封面、目錄、繪圖 helper (`COL` / `T` / `MK` / `AR`)、章節編號與目錄 JS、窄螢幕目錄按鈕。複製到 `docs/spec.html` 後填內容 |
| `scripts/renumber.py` | 依文件順序重新編 `Fig N.` / `Table N.`，並更新文中引用。新增、刪除圖表後一定要跑 |
| `scripts/figcheck.py` | 用 Edge headless 把每張圖單獨以 2 倍解析度截成 PNG，超出 viewBox 的文字會框紅 |

## 流程

1. **讀 PDF**：用 pypdf 抽文字，中間檔放 `C:\tmp`。同時看 `00_TESTBED/src/` 等 TA 給的表格檔 (txt)，表格內容一律從檔案產生，不手抄。
2. **建檔**：`cp assets/template.html docs/spec.html`，替換封面的 `{{...}}` (lab、top module、input、clock 上限、latency 上限)。
3. **分段寫**：先寫 Overview / Interface / Input 與前段演算法，給使用者看過再往下。使用者常會在中途提出理解上的問題，回答後把答案整理進對應章節。
4. **畫圖** (見下方「圖」)，每加一張圖就跑 `figcheck.py`，讀 PNG 確認沒有文字超出或重疊再交付。
5. **編號**：跑 `renumber.py docs/spec.html`，確認輸出的 Fig / Table 範圍連續，沒有 WARNING。
6. **截圖確認版面**：`msedge --headless=new --screenshot` 全頁截圖，切段讀取。
7. 用 `SendUserFile` (display: render) 交付，回報改了哪些章節、新增/刪除了哪些圖表。

## 內容原則 (使用者的要求)

- **規格書，不是教學文章**：正文只寫規定與定義。不要放「建議」、「提示」、DV 的檢查方法、程式寫法這類內容；`.rule` 框只放 spec 原文就有的硬性規定。
- **背景要淺顯**：每個大段落 (例如 entropy coding) 先用一節白話說明「這一步在做什麼、為什麼」，假設讀者沒學過；接著才是演算法細節。不要用讀者看不懂的總表取代說明。
- **演算法寫成可照做的流程**：每個計算步驟都要有「流程圖 + 編號步驟 + pseudo code + 一個逐步範例表」，範例優先用 spec 或 TA trace 檔裡的數字。
- **例子不要重複**：同一個範例 block 只在最適合的地方完整展開一次，其他地方引用它。spec 原文就有的例子保留。
- **索引與符號要說清楚**：同一張表被不同變數名查詢 (例如 C(u,x) 與 C(v,y))、陣列的列/欄代表什麼，要在表格旁明講。
- **驗證章節**：最後放 Specification Rules，分兩張表：
  - DUT Checklist：`ID | DUT 必須滿足 | Spec No.`，**不寫檢查時機與檢查方式** (使用者自己決定)
  - Stimulus Rules：`ID | PATTERN 必須遵守 | Spec No.`
- 不放 Verification Notes、評分、繳交方式，除非使用者要求。
- 回覆與文件一律繁體中文、半形符號。

## 版面與樣式 (已在 template 中)

改樣式前先想清楚理由，以下都是使用者確認過的：

- 淺色背景，不跟著系統切深色。
- 字體：標題 Source Serif 4 (中文 fallback Noto Sans TC)；內文 Inter + Noto Sans TC，17.5px、行高 1.85；程式與數值 JetBrains Mono。
- 內容寬 980px。≥ 1100px 時左側固定目錄並 highlight 目前章節；較窄時右下角「☰ 目錄」按鈕開抽屜。
- h2 以 `N. Title` 撰寫，JS 會轉成藍色 `01` 編號；h3 以 `N.M Title` 撰寫。
- 表格為 booktabs (上下粗線、無直線)，`th` 與第一欄不換行；需要靠左的欄位加 `class="l"`，數值欄加 `class="mono"`。
- 每張表、每張圖都要有 `<p class="cap">Table N. ...</p>` / `Fig N. ...`；新增時可先寫 `Table @T_name.` / `Fig @F_name.`，文中引用寫 `Table @T_name`，交給 `renumber.py` 換成數字。
- 長表格 (例如完整 Huffman 表) 放在 `<details><summary>Table N. ...</summary>` 裡。

## 圖

- 一律是 `<figure><svg id="..." viewBox="..."></svg><p class="cap">...</p></figure>`，內容由 `<script>` 裡的 IIFE 用 `T()` (文字)、`MK()` + `AR()` (箭頭) 組字串後填入 `innerHTML`。
- 配色只用 `COL`：藍 (`acc` / `accBg`) 表主要資料或 Huffman code，橘 (`org` / `orgBg`) 表強調或 amplitude，灰為框線與說明。
- **SVG 文字顏色**：`T()` 用 `fill` 屬性上色。CSS 不可以對 `svg text` 設 `fill`，否則所有顏色都會被蓋掉 (template 只設定字體)。
- **縱軸標籤不要旋轉**：用不旋轉的 `y↓`、`v↓`，旋轉後箭頭方向容易看錯。
- **超出檢查是必要步驟**：常見問題是方塊太窄 (中文說明比預期寬)、波形 bus 的 label 超出六角形、圖例文字黏到下一個色塊、標籤壓到斷線記號或箭頭。寬的圖 (viewBox 寬 > 900) 縮放後字會變小，必要時加寬方塊或減少字數，而不是縮小字。
- 常用圖型與寫法可參考 lab05 的 `docs/spec.html`：algorithm flow、I/O 時序波形 (含斷線與 X 斜線)、block 切分 + 放大、矩陣色階、zigzag 路徑、流程圖 (菱形判斷)、bit 串接與 byte 切分、latency 計數波形。

## 驗證內容正確性

數值範例 (例如 DCT 結果、編碼後的 byte) 寫進 spec 前，用 Python 照演算法算一次，並與 spec 或 TA trace 檔對照。推導出的結論 (例如數值範圍、bit 寬上界) 要標明是推導值。
