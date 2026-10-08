---
name: dv-env
description: "Sets up or aligns an ICLAB lab's simulation / DV environment in this repo: 00_TESTBED makefile, 01_RTL and 03_GATE file.f + 01_run / 03_run, 02_SYN/Netlist + Report, and the 04_DV CRV makefile / file.f. Use when the user calls /dv-env, starts a new 2026-fall-labXX, or asks to align a lab with the lab01~03 layout. Not for writing RTL, PATTERN or CRV components, and not for other ASIC projects (asic-env)."
---

# dv-env

把一個 `2026-fall-labXX/` 整理成跟 lab01~03 一樣的 sim / DV 配置。只動 flow 檔和 TESTBED 的 include / SDF 路徑，不寫 RTL、PATTERN、CRV component。

## 目錄結構

```
labXX/
├── 00_TESTBED/   TESTBED.v, PATTERN.v, makefile        (TA 的 RTL / GATE 流程)
├── 01_RTL/       <TOP>.v, file.f, 01_run
├── 02_SYN/       Netlist/, Report/                      (<TOP>_SYN.v / .sdf 放 Netlist)
├── 03_GATE/      file.f, 03_run
└── 04_DV/        top.sv, env.sv (或 test.sv), component/, file.f, makefile, [regr.py]
```

`<TOP>` 是 DUT module 名稱 (例: OISS / LDPC / ZUMA)，從 01_RTL 的設計檔或 TESTBED 的 instance 讀出來。

## 核心規則

1. **`file.f` 列出所有 source，TESTBED 不 `include DUT / PATTERN**。只有真正的 header (`define.vh`) 才用 `` `include `` + `+incdir+`
2. **`file.f` 不寫 `-sverilog`**，makefile 已經加了
3. **SDF 一律讀 `../02_SYN/Netlist/<TOP>_SYN.sdf`**
4. **所有產生的檔案用 LF 換行**
5. 不確定 `<TOP>`、TB 檔名或 timescale 時先問使用者

## 00_TESTBED

- `makefile`：複製 `resource/makefile`，只改 `TIMESCALE` (見下方)
- 刪掉 TA 的 `filelist.f`
- 修改 TA 的 `TESTBED.v` 時只動兩處，其他 (FSDB dump、註解、排版) 一律不動：
  - 刪除 `` `include "PATTERN.v" `` 和 `` `ifdef RTL / GATE `` 裡 include DUT 的整段 (含註解掉的 include)
  - `$sdf_annotate("<TOP>_SYN.sdf", ...)` 改成 `"../02_SYN/Netlist/<TOP>_SYN.sdf"`

## 01_RTL / 03_GATE

`01_RTL/file.f`：
```
./<TOP>.v
../00_TESTBED/PATTERN.v
../00_TESTBED/TESTBED.v
```

`03_GATE/file.f`：
```
../02_SYN/Netlist/<TOP>_SYN.v
../00_TESTBED/PATTERN.v
../00_TESTBED/TESTBED.v
```

`01_RTL/01_run`：`make -f ../00_TESTBED/makefile vcs_rtl`
`03_GATE/03_run`：`make -f ../00_TESTBED/makefile vcs_gate`

兩個 run 檔都要建，**不要漏 `03_run`**。PATTERN / TESTBED 檔名以 00_TESTBED 實際檔案為準 (`.v` / `.sv`)。

## 02_SYN

確保有 `Netlist/` 和 `Report/` 兩個資料夾，已有的檔案 (`syn.tcl` 等) 不動。

## 04_DV

在 04_DV 直接跑 RTL 和 GATE，不切資料夾。

- `makefile`：複製 `resource/makefile.dv`，填入：
  - `rtl_dut = ../01_RTL/<TOP>.v`、`gate_dut = ../02_SYN/Netlist/<TOP>_SYN.v`
  - `DPI_SOURCE`：有 DPI-C reference model 才填 (例: `./component/oiss.cpp`)，否則留空
  - `TIMESCALE`：對齊 `top.sv` 的 `` `timescale ``
- `file.f`：只列 TB，DUT 由 makefile 依 target 帶入：
  ```
  +incdir+./component
  ./top.sv
  ./env.sv
  ```
  第二個檔案是 env 或 test，看該 lab 的 top 底下接的是哪個
- TB 命名：top module 叫 `top`，DUT instance `u_dut`；env 為 module 時 instance `u_env`。FSDB 用 `` `ifdef FSDB `` 包起來，`define=FSDB` 才 dump
- 舊 lab 是 `PATTERN.sv` / `TESTBED.v` 時：改名成 `env.sv` / `top.sv`，只改 module 名稱、檔頭和提到舊名稱的註解
- 有 `regr.py` 時：`TARGET` 改成 `vcs_rtl_fast`，log 路徑格式 `report/<target>[_<define>]_seed_<N>.log`

## TIMESCALE

沒寫 `` `timescale `` 的檔案會吃 makefile 的 `-timescale`。檢查 PATTERN / env 的 clock 週期：

- 半週期是整數 ns → `1ns/1ns` 可以
- 半週期有小數 (例: CYCLE 15 → 7.5 ns) → 至少 `1ns/10ps`，否則 clock 會被捨入
- TA 的 00_TESTBED 一律沿用 TESTBED.v 的 `` `timescale `` (通常 `1ns/10ps`)

## makefile 使用方式 (回報給使用者時參考)

| target | 用途 |
|---|---|
| `vcs_rtl` / `vcs_rtl_fast` / `vcs_rtl_cv` | RTL：debug / 最快 / coverage |
| `vcs_gate` / `vcs_gate_fast` / `vcs_gate_cv` | gate-level，同上 |
| `regr_comp` + `regr_sim` | regression：compile 一次，每個 seed 只跑 sim |
| `cov_view` / `cov_merge` | Verdi 看 coverage / 合併成 merged.vdb |

參數：`seed=N`、`define="A B=1"`、`cov=1` (regression 用)。

## 驗證

改完用 WSL 做 dry-run，確認指令展開正確 (本機沒有 VCS)：

```bash
wsl.exe --distribution Ubuntu -- make -n vcs_gate define=FSDB
```

04_DV 檢查 `vcs_rtl_fast`、`vcs_gate`、`regr_comp`、`regr_sim`；01_RTL / 03_GATE 用 `make -n -f ../00_TESTBED/makefile vcs_rtl` / `vcs_gate`。每個 target 分開呼叫 (`wsl.exe` 會吃掉 bash loop 的變數)。`Clock skew detected` 是 WSL 檔案時間差，可忽略。

最後提醒使用者：上 server 後 `chmod +x 01_run 03_run`。
