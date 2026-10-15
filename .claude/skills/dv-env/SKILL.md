---
name: dv-env
description: "Sets up or aligns an ICLAB lab's simulation / DV environment in this repo: 00_TESTBED makefile, 01_RTL and 03_GATE file.f + 01_run / 03_run, 02_SYN/Netlist + Report, and the 04_DV CRV platform (makefile, file.f, regr.py and the generator / driver / monitor / scoreboard / env / test skeleton from the lab04 reference framework). Use when the user calls /dv-env, starts a new 2026-fall-labXX, asks to align a lab with the lab01~04 layout, or asks to build a new 04_DV CRV platform. Not for writing RTL or TA PATTERN, and not for other ASIC projects (asic-env)."
---

# dv-env

把一個 `2026-fall-labXX/` 整理成跟 lab01~04 一樣的 sim / DV 配置：flow 檔、TESTBED 的 include / SDF 路徑，以及 04_DV 的 CRV 平台。不寫 RTL 和 TA 的 PATTERN。

## 目錄結構

```
labXX/
├── 00_TESTBED/   TESTBED.v, PATTERN.v, makefile        (TA 的 RTL / GATE 流程)
├── 01_RTL/       <TOP>.v, file.f, 01_run
├── 02_SYN/       Netlist/, Report/                      (<TOP>_SYN.v / .sdf 放 Netlist)
├── 03_GATE/      file.f, 03_run
└── 04_DV/        top.sv, test.sv, env.sv, component/, file.f, makefile, regr.py
```

`<TOP>` 是 DUT module 名稱 (例: OISS / LDPC / ZUMA / F_ATTN)，從 01_RTL 的設計檔或 TESTBED 的 instance 讀出來。

## 核心規則

1. **`file.f` 列出所有 source，TESTBED 不 `include DUT / PATTERN**。只有真正的 header (`define.vh`) 才用 `` `include `` + `+incdir+`
2. **`file.f` 不寫 `-sverilog`**，makefile 已經加了
3. **SDF 一律讀 `../02_SYN/Netlist/<TOP>_SYN.sdf`**
4. **所有產生的檔案用 LF 換行**
5. 不確定 `<TOP>`、TB 檔名或 timescale 時先問使用者
6. **不改 01_RTL 的設計檔**，RTL 是使用者自己寫的

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

## 04_DV flow 檔

在 04_DV 直接跑 RTL 和 GATE，不切資料夾。

- `makefile`：複製 `resource/makefile.dv`，填入：
  - `rtl_dut = ../01_RTL/<TOP>.v`、`gate_dut = ../02_SYN/Netlist/<TOP>_SYN.v`
  - `DPI_SOURCE`：有 DPI-C reference model 才填 (例: `./component/oiss.cpp`)，否則留空
  - `TIMESCALE`：對齊 `top.sv` 的 `` `timescale ``
  - 開頭使用說明的 `plusarg=` 範例，改成該 lab test.sv 實際支援的 `+TEST` 名稱
- `file.f`：只列 TB，DUT 由 makefile 依 target 帶入：
  ```
  +incdir+./component
  ./top.sv
  ./test.sv
  ```
  DUT 用到 DesignWare 時，再加上 `-y` / `+incdir+` 指向 `dw/sim_ver` 和 `+libext+.v+` (見 `resource/crv/file.f`)
- 舊 lab 是 `PATTERN.sv` / `TESTBED.v` 時：改名成 `env.sv` / `top.sv`，只改 module 名稱、檔頭和提到舊名稱的註解
- `regr.py`：複製 `resource/crv/regr.py`，`TARGET = vcs_rtl_fast`，log 路徑格式 `report/<target>[_<define>]_seed_<N>.log`

## 04_DV CRV 框架

新 lab 的 CRV 平台一律從 **`resource/crv/`** (lab04 F_ATTN 的 04_DV) 改起：先讀過全部檔案，複製過去，再只改 DUT 相關的部分。

### 架構

```
top (module)       clk (clk_en gate)、vif 實體、DUT u_dut、FSDB / SDF
└─ test (program)  plusarg、選 blueprint、file mode 開關檔、banner、$finish
   └─ env (class)  include 所有 component、建 mailbox、run 流程
      ├─ generator   blueprint.copy() → randomize() → gen2drv
      ├─ driver      reset() / drive / wait_out()，virtual vif.drv
      ├─ monitor     collect_in() / collect_out() → mon2scb，virtual vif.mon
      └─ scoreboard  pack → ref_model() → check()，dump_pattern()、report()
```

- `env.sv` 依相依順序 `` `include ``：`dv_pkg.sv` (一定第一個) → `vif.sv` → `trans.sv` → generator → driver → monitor → scoreboard。component 不再列進 file.f
- `env.run()`：`drv.reset()` → `fork mon.run(); scb.run(); join_none` → `fork gen.run(); drv.run(); join` → `disable fork`。driver 每筆最後還會等 1~3 個 negedge，所以 `join` 時 scoreboard 已經檢查完最後一筆，不需要 drain

### 每個檔案的固定寫法 (照抄) 與要改的地方

| 檔案 | 照抄 | 依 DUT 修改 |
|---|---|---|
| `dv_pkg.sv` | `typedef int unsigned uint`、`TIMEOUT`、`ERR_TOL` 的位置 | 資料型別 (fp32_t 等)、範圍常數、pack function |
| `vif.sv` | `drv_cb` / `mon_cb` 都在 `@(negedge clk)`，`default input #1step output #0`；`modport drv` 另外開 `output clk_en, rst_n` 和所有 input (reset 期間直接寫)；`modport mon` 只有 `mon_cb` | port 清單、SPEC 的 SVA (從 TA PATTERN 搬，訊息格式 `[SPEC-x FAILED]` / `[IO-x FAILED]`) |
| `trans.sv` | `txn` 的 `virtual create()` + `copy()`；directed 子類別覆寫 `create()`；`file_txn` (`static fd`、`rand_mode(0)` + `constraint_mode(0)`、`post_randomize()` 讀檔並檢查 `$fscanf` 回傳值)；`mon_txn` 用 `logic` 的 fixed array | 欄位、constraint、檔案格式 |
| `generator.sv` | `txn blueprint`，`new()` 建預設 txn，`run()` 每筆 `blueprint.copy()` | 通常不用改 |
| `driver.sv` | `reset()`：clk_en=0、input 清 0、rst_n 1→0 (#10)→1 (#100)、再 #10 才 clk_en=1；drive 用 `vif.drv_cb.x <=` 後 `@(vif.drv_cb)`；don't care 送 `'dx` (參數用 `logic`，不用 2-state 型別)；`wait_out()` 檢查 latency timeout 和 out_valid 長度 | 協定時序、拍數、gap |
| `monitor.sv` | `@(vif.mon_cb iff in_valid === 1)` 開始一筆；`lat` 從 1 起算 (對齊 PATTERN 的計算方式) | 收集的拍數與欄位 |
| `scoreboard.sv` | `run()` = get → pack → `ref_model()` → `check()`；fail 時印 PATTERN 格式訊息並 `dump_pattern()` 寫 `fail_input.txt` (TA input.txt 格式)；`report()` 印 `Pass patterns` / `Latency: total = , max =` / `Max error` | ref model (從 TA PATTERN 搬)、比對方式、統計項目 |
| `test.sv` | `+PAT_NUM`、`+TEST=<rand \| file \| ...>`、`+IN_FILE`；file mode 在 `new env` 前開檔讀筆數並設 `file_txn::fd`，`e.run()` 後關檔；`set_blueprint()` 在 `new env` 與 `e.run()` 之間 | banner 名稱、directed test 分支 |
| `top.sv` | `always #(CLK_PERIOD / 2.0) clk = (tb_if.clk_en)? ~clk : 1'b0` (reset 期間 clk 停住，抓 sync reset)；`` `ifdef FSDB / GATE `` | `CLK_PERIOD` (對齊 syn.tcl)、DUT port、FSDB / SDF 檔名 |
| `regr.py` | consecutive seed (`-n` / `--start` / `-s`)、`-d` define、`All Pass` 判斷、`FAIL_KEYS` 優先順序、summary 的 regex | summary regex 對齊 scoreboard 的 `report()` |

### 寫新 lab 時的流程

1. 讀 TA 的 PATTERN：port、reset 方式、輸入拍數與 gap、latency 上限、輸出拍數、SPEC 編號與訊息、ref model、input.txt 格式
2. 從 `resource/crv/` 複製，依上表改 DUT 相關部分，檔頭的 Project / 註解改成該 lab
3. TA PATTERN 的 concurrent assertion 搬進 `vif.sv`；reset 期間的 immediate 檢查 (SPEC-4) 用 `rst_fell` + `@(posedge rst_n)` 改寫成 SVA
4. 先用 `+TEST=file +IN_FILE=../00_TESTBED/input.txt` 跑 TA 的 pattern，latency 要跟 TA PATTERN 一致，再跑 random 和 `regr.py`

### 已知的坑

- `` `include `` 的 package 一定要在使用它的 class 之前；pkg 裡的 function 不能吃 trans.sv 的 class (會反向相依)，只吃 array / 基本型別
- clockvar 只能用 `<=` drive；reset 期間 clk 停住，透過 clocking block 的 drive 不會生效，要直接寫 `vif.x =`
- `rand_mode(0)` 之後 constraint 仍會檢查目前的值，讀檔的 txn 要連 `constraint_mode(0)` 一起關，否則 `randomize()` 失敗、`post_randomize()` 不會被呼叫
- 2-state 型別 (`bit` / 由 bit 組成的 struct) 會把 X 變 0：要送 `'dx` 或要檢查 X 的地方用 `logic`
- 每個繼承 txn 的子類別都要覆寫 `create()`，漏了不會報錯，constraint 會悄悄失效

## TIMESCALE

沒寫 `` `timescale `` 的檔案會吃 makefile 的 `-timescale`。檢查 PATTERN / env 的 clock 週期：

- 半週期是整數 ns → `1ns/1ns` 可以
- 半週期有小數 (例: CYCLE 15 → 7.5 ns) → 至少 `1ns/10ps`，否則 clock 會被捨入
- TA 的 00_TESTBED 一律沿用 TESTBED.v 的 `` `timescale `` (通常 `1ns/10ps`)
- 04_DV 的 `top.sv` 參考框架用 `1ns/1ps`，makefile `TIMESCALE` 跟著設 `-timescale=1ns/1ps`

## makefile 使用方式 (回報給使用者時參考)

| target | 用途 |
|---|---|
| `vcs_rtl` / `vcs_rtl_fast` / `vcs_rtl_cv` | RTL：debug / 最快 / coverage |
| `vcs_gate` / `vcs_gate_fast` / `vcs_gate_cv` | gate-level，同上 |
| `regr_comp` + `regr_sim` | regression：compile 一次，每個 seed 只跑 sim |
| `cov_view` / `cov_merge` | Verdi 看 coverage / 合併成 merged.vdb |

參數：`seed=N`、`define="A B=1"` (compile time)、`plusarg="+TEST=file +PAT_NUM=100"` (runtime，不用重新 compile)、`cov=1` (regression 用)。

## 驗證

改完用 WSL 做 dry-run，確認指令展開正確 (本機沒有 VCS)：

```bash
wsl.exe --distribution Ubuntu -- make -n vcs_gate define=FSDB
```

04_DV 檢查 `vcs_rtl_fast`、`vcs_gate`、`regr_comp`、`regr_sim plusarg="+TEST=file"`；01_RTL / 03_GATE 用 `make -n -f ../00_TESTBED/makefile vcs_rtl` / `vcs_gate`。每個 target 分開呼叫 (`wsl.exe` 會吃掉 bash loop 的變數)。`Clock skew detected` 是 WSL 檔案時間差，可忽略。regr.py 用 `python3 regr.py -h` 確認可以執行。

SV 檔本機無法 compile，回報時要明講「未 compile」，請使用者在 server 跑 `make vcs_rtl` 確認。

最後提醒使用者：上 server 後 `chmod +x 01_run 03_run regr.py`，並確認檔案不是 CRLF。
