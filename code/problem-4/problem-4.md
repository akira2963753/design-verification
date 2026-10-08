# Problem 4: FIFO Bug Hunt

| 難度 | 題型 | 預估時間 | 原型 |
|---|---|---|---|
| Medium-Hard | Bug Hunt | 3 hr | 同步 FIFO (DV 面試經典題) |

## 題型說明

這題不用寫 DUT，要寫的是 **testbench**。

`dut/FIFO.sv` 是一個深度 8 的同步 FIFO，裡面用 `+define+BUG_x` 埋了 **11 個 bug**，每個 bug 至少違反下面一條 SPEC。你要照 SPEC 寫一個 TB，達到：

- 正確版 DUT：TB 判定通過，印出 `ALL PASS`。
- 每一個 `BUG_x` 版本：TB 都要抓到，印出 `FAIL`。

規則：

- 把 DUT 當 black box，**不要打開 `dut/FIFO.sv`**，只能透過 port 觀察。
- TB 裡不能用 `` `ifdef BUG_x ``，也不能用 hierarchical reference (例如 `u_dut.cnt`) 偷看內部訊號。

## DUT 介面

```systemverilog
module FIFO (
    input clk,
    input rst_n,
    input push,
    input [7:0] push_data,
    input pop,
    output logic [7:0] pop_data,
    output logic pop_valid,
    output logic full,
    output logic empty,
    output logic [3:0] count,
    output logic overflow,
    output logic underflow
);
```

| Port | 方向 | 說明 |
|---|---|---|
| `clk` | in | clock |
| `rst_n` | in | asynchronous active-low reset |
| `push` | in | 寫入要求 |
| `push_data` | in | 寫入的資料 |
| `pop` | in | 讀出要求 |
| `pop_data` | out | 讀出的資料 |
| `pop_valid` | out | `pop_data` 有效 |
| `full` | out | FIFO 滿了 (8 筆) |
| `empty` | out | FIFO 是空的 |
| `count` | out | FIFO 裡的資料筆數 (0 ~ 8) |
| `overflow` | out | 上一個 posedge 的 push 被拒絕 |
| `underflow` | out | 上一個 posedge 的 pop 被拒絕 |

## 時序

- 所有 input 在 `clk` 的 **posedge** 被取樣。
- 所有 output 都是 register，在同一個 posedge 更新，反映這個 posedge 取樣到的操作。
- `rst_n` 是 asynchronous reset：拉低時 output **立刻**變成 reset 值，不需要等 clock。
- 建議 TB 在 negedge 改 input、在 negedge 檢查 output，或是用 clocking block。

下表每一列是「這個 posedge 取樣到的 input」和「這個 posedge 之後的 output」：

| posedge | push | push_data | pop | count | empty | full | pop_valid | pop_data | overflow | underflow |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | `A1` | 0 | 1 | 0 | 0 | 0 | `00` | 0 | 0 |
| 2 | 1 | `B2` | 0 | 2 | 0 | 0 | 0 | `00` | 0 | 0 |
| 3 | 0 | | 1 | 1 | 0 | 0 | 1 | `A1` | 0 | 0 |
| 4 | 1 | `C3` | 1 | 1 | 0 | 0 | 1 | `B2` | 0 | 0 |
| 5 | 0 | | 1 | 0 | 1 | 0 | 1 | `C3` | 0 | 0 |
| 6 | 0 | | 1 | 0 | 1 | 0 | 0 | `00` | 0 | 1 |
| 7 | 1 | `D4` | 1 | 1 | 0 | 0 | 0 | `00` | 0 | 1 |
| 8 | 0 | | 0 | 1 | 0 | 0 | 0 | `00` | 0 | 0 |

posedge 6 是在空的時候 pop。posedge 7 是在空的時候同時 push 和 pop (見 SPEC-7)。

## SPEC

| SPEC | 名稱 | 要求 |
|---|---|---|
| SPEC-1 | Reset | `rst_n` 為 0 的期間 (不需要等 clock edge)，所有 output 必須是：`count = 0`、`empty = 1`、`full = 0`、`pop_valid = 0`、`pop_data = 0`、`overflow = 0`、`underflow = 0` |
| SPEC-2 | 資料順序 | pop 出來的資料順序和 push 進去的順序相同 (只算成功的 push / pop)，資料不能遺失、重複或被改寫 |
| SPEC-3 | count / empty / full | `count` 等於 FIFO 裡的資料筆數；`empty = (count == 0)`；`full = (count == 8)` |
| SPEC-4 | pop 輸出 | 成功的 pop 之後，`pop_valid = 1` 且 `pop_data` 是被 pop 的資料；`pop_valid = 0` 時 `pop_data` 必須是 0 |
| SPEC-5 | Overflow | full 時只 push 不 pop：這次 push 被忽略 (資料不寫入、count 不變)，`overflow = 1` 維持 1 個 cycle；其他情況 `overflow = 0` |
| SPEC-6 | Underflow | empty 時 pop：這次 pop 被忽略 (`pop_valid` 維持 0)，`underflow = 1` 維持 1 個 cycle；其他情況 `underflow = 0` |
| SPEC-7 | 同時 push & pop | FIFO 不是空的 (包含 full)：push 和 pop 都成功，count 不變，不算 overflow。FIFO 是空的：push 成功，pop 被忽略並且 `underflow = 1` |
| SPEC-8 | Reset 之後 | `rst_n` 可以在任何時間拉低，包含模擬中途。reset 之後 FIFO 是空的，之前的資料全部丟掉。`rst_n` 拉高後的**第一個 posedge** 就要能正常 push / pop |

## TB 規則

Judge 用下面的規則判斷 TB 的結果：

1. TB 自己 instantiate `FIFO`。DUT 由 makefile 編譯，**不要**放進 `src/file.f`。
2. `src/file.f` 依編譯順序列出你所有的 TB 檔案。可以自由新增檔案 (interface、class、program 都可以)。
3. 沒發現錯誤：印出 `ALL PASS`，然後 `$finish`。
4. 發現錯誤：印出一行以 `FAIL` 開頭的訊息，然後 `$finish`。建議寫成 `FAIL SPEC-n: 原因`，方便對照。
5. 模擬要在 10 s 內結束。超時、或沒印出 `ALL PASS`，都算 FAIL。

正確版 DUT 必須是 PASS。BUG 版本只要 TB 判 FAIL 就算抓到，不檢查你印的 SPEC 編號對不對。

## 作答流程

1. 在 `src/` 寫 TB，並把檔案列進 `src/file.f`。
2. 在 server 的 `problem-4/` 底下先跑 `make`，確認正確版 DUT 是 PASS。
3. 跑 `make judge`，看抓到幾個 bug。

| 指令 | 用途 |
|---|---|
| `make` | 用正確版 DUT 跑一次，顯示 TB 的輸出 |
| `make bug=3` | 注入 `BUG_3` 跑一次，顯示 TB 的輸出 |
| `make seed=7` | 換 random seed (傳給 `+ntb_random_seed`)，可以和 `bug=` 一起用 |
| `make judge` | 正確版 + `BUG_1` ~ `BUG_11` 全部跑一次，只印總表，約 15 s |
| `make opt="..."` | 額外的 VCS option，例如 `opt="-debug_access+all +define+FSDB"` 用來 dump 波形 |
| `make clean` | 清掉 VCS 產生的檔案和 `log/` |

每次執行的完整輸出存在 `log/correct.log`、`log/bug_<n>.log`。

| 判定結果 | 意思 |
|---|---|
| `Accepted` | 正確版 PASS，11/11 個 bug 都抓到 |
| `Wrong Answer` | 正確版 PASS，但有 bug 沒抓到，`Replay` 會告訴你第一個漏掉的 bug |
| `False Alarm` | TB 在正確版 DUT 上就 FAIL 了，先修 TB (通常是 ref model 或檢查時間點錯了) |
| `Compile Error` | 印出 VCS 的 error 訊息 |

## 本題練到的語法

這些是建議用法，不強制。也可以直接用 Lab03 那種 class-based 架構。

Textbook 頁碼是書上印的頁碼，PDF 頁碼 = 書頁 + 43。

| 語法 | Textbook | ChipVerify |
|---|---|---|
| interface、modport | 4.2 (p.90、p.94) | [interface](https://www.chipverify.com/systemverilog/systemverilog-interface)、[modport](https://www.chipverify.com/systemverilog/systemverilog-modport) |
| clocking block 的驅動與取樣 | 4.3.1 (p.98)、4.4.4 (p.106) | [clocking blocks](https://www.chipverify.com/systemverilog/systemverilog-clocking-blocks) |
| program block 與 TB / DUT race | 4.3.3 ~ 4.3.4 (p.100 ~ 101) | [program block](https://www.chipverify.com/systemverilog/systemverilog-program-block) |
| immediate assertion | 4.9.1 (p.116) | [immediate assertions](https://www.chipverify.com/systemverilog/systemverilog-immediate-assertions) |
| queue 當 reference model | 2.4 (p.37) | [queue](https://www.chipverify.com/systemverilog/systemverilog-queue) |
| `randcase`、`$urandom_range` | 6.15.1 (p.215)、6.10 (p.195) | [randcase](https://www.chipverify.com/systemverilog/systemverilog-randcase) |

## 提示

卡住再展開。

<details>
<summary>Hint 1: TB 架構</summary>

用一個 queue 當 reference model。每個 posedge 照 SPEC-7 的規則，先決定這次 push / pop 是否成功，再更新 queue，同時算出 7 個 output 的期望值。

**每個 cycle 都比對全部 7 個 output**，不要只在 `pop_valid = 1` 時比資料。

</details>

<details>
<summary>Hint 2: 刺激</summary>

push / pop 各 50% 的純 random，FIFO 很少會滿，邊界情況打不太到。可以分階段調整 push / pop 的機率：灌滿、抽乾、兩個機率都很高 (常常同時 push 和 pop)。

reset 也是刺激的一部分。

</details>

<details>
<summary>Hint 3: 抓到 9 個之後卡住</summary>

我用「每個 cycle 檢查全部 output、3000 個 cycle 的 50/50 random、只在開頭 reset 一次」的 TB 試過，只抓到 9/11。剩下兩個都跟 reset 有關，請逐字重讀 SPEC-1 和 SPEC-8：

- reset 是 asynchronous，拉低之後、還沒遇到 posedge 之前，output 應該是什麼？
- reset 放開後，你的 TB 是不是先等了幾個 cycle 才開始送資料？

</details>

## Follow-up

通過之後再想：

1. 把部分 checker 改寫成 concurrent SVA，例如 `full` 和 `count` 的關係、`overflow` 只維持 1 個 cycle。和 procedural 的檢查比，哪些用 SVA 比較好寫？
2. 改寫成 class-based 架構 (transaction、driver、monitor、scoreboard)，和 Lab03 一樣。
3. 加上 functional coverage：在 full / empty 時 push、pop 的各種組合做 cross，證明 corner case 真的有打到。

全部通過後，`code/.judge/problem-4/bugs.md` 有每個 bug 的說明。
