# Problem 5: AXI4 Memory Slave Bug Hunt

| 難度 | 題型 | 預估時間 | 原型 |
|---|---|---|---|
| Hard | Bug Hunt | 6 ~ 8 hr | AXI4 memory slave (支援 burst、outstanding、out-of-order) |

## 題型說明

和 Problem 4 一樣，這題要寫的是 **testbench**，不用寫 DUT。

`dut/AXI4_MEM.sv` 是一個 AXI4 memory slave，裡面用 `+define+BUG_x` 埋了 **13 個 bug**，每個 bug 至少違反下面一條 SPEC。你的 TB 扮演 AXI4 master，要做到：

- 正確版 DUT：TB 判定通過，印出 `ALL PASS`。
- 每一個 `BUG_x` 版本：TB 都要抓到，印出 `FAIL`。

規則和 Problem 4 相同：

- 把 DUT 當 black box，**不要打開 `dut/AXI4_MEM.sv`**，只能透過 port 觀察。
- TB 裡不能用 `` `ifdef BUG_x ``，也不能用 hierarchical reference (例如 `u_dut.mem`) 偷看內部訊號。

這份文件比較長，建議閱讀順序：

1. 「AXI4 快速入門」：沒碰過 AXI 先讀這段。
2. 「本題 DUT 規格」與「Master 必須遵守的規則」：寫 driver 前一定要讀。
3. 「SPEC」：寫 checker 時對照。

## AXI4 快速入門

這一段只介紹本題會用到的部分。完整定義請看 ARM 官方的 *AMBA AXI and ACE Protocol Specification* (文件編號 IHI 0022)，對應的章節是 Signal Descriptions、Single Interface Requirements (handshake、channel 之間的關係、burst、位址、WSTRB、response) 和 Transaction Identifiers / Ordering Model (ID 與順序)。

### 5 個 channel

AXI4 把一次讀或寫拆成幾個獨立的 channel，每個 channel 都有自己的 `VALID` / `READY`：

| Channel | 方向 | 用途 |
|---|---|---|
| AW (write address) | master → slave | 送出寫入的起始位址、長度、burst 種類、ID |
| W (write data) | master → slave | 送出寫入資料，一個 burst 有好幾個 beat |
| B (write response) | slave → master | 整個寫入 burst 完成後，回一個 response |
| AR (read address) | master → slave | 送出讀取的起始位址、長度、burst 種類、ID |
| R (read data) | slave → master | 回傳讀取資料，一個 burst 有好幾個 beat，最後一個 beat 的 `RLAST = 1` |

一次寫入 = 1 個 AW + (AWLEN + 1) 個 W beat + 1 個 B。一次讀取 = 1 個 AR + (ARLEN + 1) 個 R beat。

### VALID / READY handshake

每個 channel 都用同一套規則傳資料：

- 送資料的一方 (source) 把資料放好，拉高 `VALID`。
- 收資料的一方 (destination) 準備好時拉高 `READY`。
- **在某個 posedge，`VALID` 和 `READY` 同時為 1，這筆資料就傳送完成**，稱為一次 handshake。

```
ACLK    __/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__
VALID   ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
READY   ______________________/‾‾‾‾‾‾\_________
DATA    ======X     D0 (不能變)       X=========
                                ^
                                這個 posedge VALID = READY = 1，D0 傳送完成
```

handshake 規則 (source 端)：

- `VALID` 一旦拉高，就要**一直維持到 handshake 完成**才能拉低，不能因為 `READY` 一直不來就收回。
- `VALID` 為 1、還沒 handshake 的期間，資料 (payload) **不能改變**。
- `VALID` 不能等 `READY` 才拉高；但 `READY` 可以等 `VALID` 才拉高。

本題的 B、R channel 由 DUT 當 source，所以 DUT 必須遵守上面這些規則 (見 SPEC-2、SPEC-3)。AW、W、AR 由你的 TB 當 source，TB 也必須遵守。

### Burst

一個 AW / AR 描述一整個 burst：

| 訊號 | 意思 |
|---|---|
| `AxADDR` | 第一個 beat 的位址 (byte address) |
| `AxLEN` | beat 數 - 1，也就是 beat 數 = `AxLEN + 1` |
| `AxSIZE` | 每個 beat 的 byte 數 = 2^`AxSIZE`。本題固定 `3'b010` (4 bytes) |
| `AxBURST` | burst 種類：`2'b00` FIXED、`2'b01` INCR、`2'b10` WRAP、`2'b11` reserved |

(`Ax` 代表 `AW` 或 `AR`。)

每個 beat 的位址計算方式 (本題每個 beat 4 bytes)：

| 種類 | 第 i 個 beat 的位址 | 用途 |
|---|---|---|
| FIXED | 每個 beat 都是 `AxADDR` | 反覆存取同一個位址，例如 FIFO 型的周邊 |
| INCR | `AxADDR + 4 * i` | 一般的連續存取 |
| WRAP | 在一個對齊的區塊內遞增，到區塊尾端就繞回區塊開頭 | cache line fill |

WRAP 的計算：

```
total = (AxLEN + 1) * 4                      // 整個 burst 的 byte 數
lower = (AxADDR / total) * total             // 對齊到 total 的區塊起點
每個 beat 加 4，加到 lower + total 時，回到 lower
```

例子：

| 種類 | AxADDR | AxLEN | 各 beat 的位址 |
|---|---|---|---|
| FIXED | `0x200` | 2 | `0x200`、`0x200`、`0x200` |
| INCR | `0x100` | 3 | `0x100`、`0x104`、`0x108`、`0x10C` |
| WRAP | `0x038` | 3 | 區塊 `0x030 ~ 0x03F`：`0x038`、`0x03C`、`0x030`、`0x034` |
| WRAP | `0x0A8` | 15 | 區塊 `0x080 ~ 0x0BF`：`0x0A8`、`0x0AC`、… `0x0BC`、`0x080`、`0x084`、… `0x0A4` |

### WSTRB (byte enable)

`WSTRB[i]` 為 1 時，`WDATA[8*i+7 : 8*i]` 才會寫進 beat 位址 + i 那個 byte；為 0 的 byte 保持原值。

例子：記憶體原本是 `0x11223344`，寫入 `WDATA = 0xAABBCCDD`、`WSTRB = 4'b0101`，結果是 `0x11BB33DD` (byte 0 和 byte 2 被改掉)。`WSTRB = 4'b0000` 的 beat 什麼都不寫。

FIXED burst 的每個 beat 都寫同一個位址，後面的 beat 會蓋掉前面 beat 寫過的 byte。

### Response

| 值 | 名稱 | 意思 |
|---|---|---|
| `2'b00` | OKAY | 正常完成 |
| `2'b10` | SLVERR | slave 回報錯誤 |

(`2'b01` EXOKAY、`2'b11` DECERR 本題不會用到。)

### ID、outstanding 與順序

- **outstanding**：master 不用等上一筆完成，就可以繼續送下一個 AW / AR。同一時間可以有好幾筆「已送出位址、還沒收到 response」的交易。
- 每筆交易帶一個 ID (`AWID` / `ARID`)，slave 回 response 時帶相同的 ID (`BID` / `RID`)，master 用 ID 對應回原本的交易。
- **相同 ID** 的交易，response 必須照送出的順序回來。
- **不同 ID** 的交易，response 可以不照順序回來 (out-of-order)。

例子：master 依序送出 3 個 AR，都還沒收到資料：

| 順序 | ARID | ARADDR | ARLEN |
|---|---|---|---|
| A | 1 | `0x100` | 1 (2 beats) |
| B | 2 | `0x200` | 0 (1 beat) |
| C | 1 | `0x300` | 0 (1 beat) |

| R channel 回傳順序 | 合法嗎 | 原因 |
|---|---|---|
| A0、A1、B、C | 合法 | 完全照順序 |
| B、A0、A1、C | 合法 | B 的 ID 不同，可以先回 |
| A0、A1、C、B | 合法 | 同一個 ID 的 A、C 照順序，B 可以晚回 |
| C、A0、A1、B | **不合法** | C 和 A 同為 ID 1，C 不能比 A 先回 |

AXI4 本身允許不同 ID 的 read beat 交錯 (interleave)，但**本題的 DUT 保證一個 read burst 的 beat 連續送完**，不會和其他 burst 交錯。

## 本題 DUT 規格

### 介面

```systemverilog
module AXI4_MEM (
    input ACLK,
    input ARESETn,
    // AW channel
    input [3:0] AWID,
    input [31:0] AWADDR,
    input [7:0] AWLEN,
    input [2:0] AWSIZE,
    input [1:0] AWBURST,
    input AWVALID,
    output logic AWREADY,
    // W channel
    input [31:0] WDATA,
    input [3:0] WSTRB,
    input WLAST,
    input WVALID,
    output logic WREADY,
    // B channel
    output logic [3:0] BID,
    output logic [1:0] BRESP,
    output logic BVALID,
    input BREADY,
    // AR channel
    input [3:0] ARID,
    input [31:0] ARADDR,
    input [7:0] ARLEN,
    input [2:0] ARSIZE,
    input [1:0] ARBURST,
    input ARVALID,
    output logic ARREADY,
    // R channel
    output logic [3:0] RID,
    output logic [31:0] RDATA,
    output logic [1:0] RRESP,
    output logic RLAST,
    output logic RVALID,
    input RREADY
);
```

訊號名稱和 ARM 官方規格相同。只實作上面這些訊號，`AxLOCK`、`AxCACHE`、`AxPROT`、`AxQOS`、`AxREGION`、`xUSER` 都沒有。

| 項目 | 設定 |
|---|---|
| Clock / reset | `ACLK` posedge 取樣；`ARESETn` 是 active-low asynchronous reset |
| 記憶體 | 4KB，位址 `0x0000_0000 ~ 0x0000_0FFF`，每個 word 32 bit |
| Data width | 32 bit，`AxSIZE` 必須是 `3'b010` |
| ID width | 4 bit (ID 0 ~ 15) |
| Burst | FIXED、INCR、WRAP 都支援 |

### DUT 的行為

時序與流量控制：

- `AWREADY`、`WREADY`、`ARREADY` **任何一個 cycle 都可能是 0**，延遲不固定。TB 不能假設 DUT 幾個 cycle 之後一定會 ready。
- DUT 最多暫存 4 筆還沒處理完的 AW、4 筆還沒回資料的 AR。滿了就把 `AWREADY` / `ARREADY` 拉低。
- **W beat 要等對應的 AW handshake 之後，DUT 才會接收** (`WREADY` 會維持 0)。W beat 依 AW 的順序歸屬：第一個 AW 的 AWLEN + 1 個 beat，接著是第二個 AW 的，依此類推。
- DUT 用 `AWLEN` 判斷最後一個 W beat，不看 `WLAST`。

Response：

- B response 和 R burst 可能**不照順序**回來 (不同 ID 之間)，延遲也不固定。
- 相同 ID 一定照順序回來。
- 一個 read burst 的 beat 連續送完，不和其他 burst 交錯；beat 之間可能有空的 cycle (`RVALID = 0`)。

記憶體內容：

- reset 之後記憶體全部是 0。
- 寫入在 W beat handshake 時生效，依 AW 的順序執行。
- 讀取在送出 R beat 時讀記憶體。
- **讀和寫之間沒有順序保證**：如果同一個位址同時有 outstanding 的讀和寫，讀到的可能是舊值或新值 (見規則 M8)。

錯誤：

- 位址超出記憶體範圍 (`AxADDR[31:12] != 0`) 的整個 burst 回 SLVERR：寫入的資料全部丟掉，讀取的每個 beat `RDATA = 0`。beat 數、`RLAST`、B response 照常。

## Master 必須遵守的規則

你的 TB 是 master。DUT **不會檢查** master 有沒有違規，違規時 DUT 的行為未定義，通常會讓正確版也 FAIL (`False Alarm`)。

handshake 與介面：

| 編號 | 規則 |
|---|---|
| M1 | `AWVALID`、`WVALID`、`ARVALID` 拉高後要維持到 handshake 完成；這段期間 payload 不能變 |
| M2 | `ARESETn = 0` 期間，`AWVALID`、`WVALID`、`ARVALID` 必須是 0 |
| M3 | 不能等 `WREADY` 或 W handshake 才送 AW。本題 DUT 要先收到 AW 才會拉 `WREADY`，所以「先送完 W 再送 AW」會 deadlock |

burst 的合法範圍：

| 編號 | 規則 |
|---|---|
| M4 | `AxSIZE = 3'b010`，`AxADDR[1:0] = 2'b00` |
| M5 | 不能用 `AxBURST = 2'b11` |
| M6 | FIXED：`AxLEN` 0 ~ 15；WRAP：`AxLEN` 只能是 1、3、7、15；INCR：`AxLEN` 0 ~ 255 |
| M7 | INCR burst 不能跨越 4KB 邊界：`(AxADDR % 4096) + (AxLEN + 1) * 4 <= 4096` |

資料與順序：

| 編號 | 規則 |
|---|---|
| M8 | 同一個位址不能同時有 outstanding 的讀和寫。要讀剛寫的位址，先等那筆寫入的 B 回來 |
| M9 | 每個 AW 恰好送 AWLEN + 1 個 W beat，最後一個 beat `WLAST = 1`；W 依 AW 的順序送，不能交錯 |

## SPEC

| SPEC | 名稱 | 要求 |
|---|---|---|
| SPEC-1 | Reset | `ARESETn = 0` 期間 (不需要等 clock edge)，`BVALID = 0`、`RVALID = 0`。reset 之後記憶體全部是 0 |
| SPEC-2 | VALID 維持 | `BVALID` / `RVALID` 拉高後，必須維持到 handshake 完成 (posedge 時 `xVALID = xREADY = 1`) 才能拉低 |
| SPEC-3 | Payload 穩定 | `BVALID = 1` 還沒 handshake 時，`BID`、`BRESP` 不能變；`RVALID = 1` 還沒 handshake 時，`RID`、`RDATA`、`RRESP`、`RLAST` 不能變 |
| SPEC-4 | 寫入位址 | 每個 W beat 寫入的位址照 `AWBURST` 計算 (見「Burst」) |
| SPEC-5 | WSTRB | 只寫 `WSTRB` 為 1 的 byte，其他 byte 保持原值 |
| SPEC-6 | Write response | 每筆寫入恰好回一個 B。`BVALID` 只能在這筆寫入的**最後一個 W beat handshake 之後**才拉高。`BID` = 這筆的 `AWID` |
| SPEC-7 | Read data | 每筆讀取恰好回 ARLEN + 1 個 beat。每個 `RDATA` 是對應位址 (照 `ARBURST` 計算) 的資料；`RID` = 這筆的 `ARID`；只有最後一個 beat `RLAST = 1` |
| SPEC-8 | 錯誤回應 | `AxADDR[31:12] != 0` 的 burst 回 SLVERR (`2'b10`)：寫入不改變記憶體，讀取每個 beat `RDATA = 0`。其餘回 OKAY (`2'b00`) |
| SPEC-9 | 順序 | 相同 ID 的 B 依 AW 的順序回；相同 ID 的 read burst 依 AR 的順序回；一個 read burst 的 beat 連續送完 |
| SPEC-10 | Outstanding | 有多筆 outstanding 時，每一筆的資料、ID、response 都要對應到它自己的 AW / AR |

## TB 規則

和 Problem 4 相同：

1. TB 自己 instantiate `AXI4_MEM`。DUT 由 makefile 編譯，**不要**放進 `src/file.f`。
2. `src/file.f` 依編譯順序列出你所有的 TB 檔案，可以自由新增檔案。
3. 沒發現錯誤：印出 `ALL PASS`，然後 `$finish`。
4. 發現錯誤：印出一行以 `FAIL` 開頭的訊息，然後 `$finish`。建議寫成 `FAIL SPEC-n: 原因`。
5. 模擬要在 **20 s** 內結束。超時、或沒印出 `ALL PASS`，都算 FAIL。建議自己加 watchdog：等太久沒有 response 就印 `FAIL`，比較好 debug。

正確版 DUT 必須是 PASS。BUG 版本只要 TB 判 FAIL 就算抓到，不檢查 SPEC 編號。

## 作答流程

建議分階段做，每一步都先確認正確版 PASS：

1. 寫 AW、W、B 的 driver，做一筆 INCR 寫入、等 B 回來。
2. 寫 AR、R，把剛寫的資料讀回來比對。這時候 `make` 應該要 PASS。
3. 加上 reference model (記憶體模型) 和完整的 checker，對照 SPEC 一條一條補。
4. 加上 random：三種 burst、各種長度、WSTRB、錯誤位址、outstanding、`BREADY` / `RREADY` 的 backpressure。
5. 跑 `make judge`。

| 指令 | 用途 |
|---|---|
| `make` | 用正確版 DUT 跑一次，顯示 TB 的輸出 |
| `make bug=3` | 注入 `BUG_3` 跑一次，顯示 TB 的輸出 |
| `make seed=7` | 換 random seed (傳給 `+ntb_random_seed`)，可以和 `bug=` 一起用 |
| `make judge` | 正確版 + `BUG_1` ~ `BUG_13` 全部跑一次，只印總表，約 20 s |
| `make opt="..."` | 額外的 VCS option，例如 `opt="-debug_access+all +define+FSDB"` 用來 dump 波形 |
| `make clean` | 清掉 VCS 產生的檔案和 `log/` |

每次執行的完整輸出存在 `log/correct.log`、`log/bug_<n>.log`。

| 判定結果 | 意思 |
|---|---|
| `Accepted` | 正確版 PASS，13/13 個 bug 都抓到 |
| `Wrong Answer` | 正確版 PASS，但有 bug 沒抓到，`Replay` 會告訴你第一個漏掉的 bug |
| `False Alarm` | TB 在正確版 DUT 上就 FAIL 了。先修 TB，常見原因是違反了 Master 規則、或 reference model 錯 |
| `Compile Error` | 印出 VCS 的 error 訊息 |

建議換幾個 seed 都跑過 `make judge`，確認不是剛好運氣好。

## 本題練到的語法

這些是建議用法，不強制。

Textbook 頁碼是書上印的頁碼，PDF 頁碼 = 書頁 + 43。

| 語法 | 用在哪裡 | Textbook | ChipVerify |
|---|---|---|---|
| class | 包裝一筆 AXI 交易 (ID、位址、長度、資料…) | Ch5 (p.131) | [class](https://www.chipverify.com/systemverilog/systemverilog-class) |
| `fork ... join_none` | AW、W、AR、B、R 各自一個 thread 平行跑 | 7.1.2 (p.232) | [fork join_none](https://www.chipverify.com/systemverilog/systemverilog-fork-join-none) |
| mailbox | generator 把交易交給 driver | 7.6 (p.252) | [mailbox](https://www.chipverify.com/systemverilog/systemverilog-mailbox) |
| associative array、queue | 記憶體模型、依 ID 分開的 expected queue | 2.4 (p.37)、2.5 (p.38) | [associative array](https://www.chipverify.com/systemverilog/systemverilog-associative-array) |
| constraint：`inside`、`dist`、implication | 產生合法的 burst (M4 ~ M7) | 6.4.4 (p.177)、6.4.5 (p.179)、6.4.8 (p.184) | [inside](https://www.chipverify.com/systemverilog/systemverilog-constraint-inside)、[implication](https://www.chipverify.com/systemverilog/systemverilog-implication-constraint) |
| concurrent SVA：`\|=>`、`$stable`、`disable iff` | 檢查 handshake 規則 (SPEC-2、SPEC-3) | 4.9.3 (p.118) | [concurrent assertions](https://www.chipverify.com/systemverilog/systemverilog-concurrent-assertions)、[implication](https://www.chipverify.com/systemverilog/systemverilog-assertions-property-implication) |

## 提示

卡住再展開。

<details>
<summary>Hint 1: TB 架構</summary>

一種常見的切法：

- **Generator**：產生一筆交易 (class)，同時更新記憶體模型，算出這筆交易的期望結果。
- **Driver**：AW、W、AR 各一個 thread，從 queue 或 mailbox 拿交易出來送。W 的順序要和 AW 一致，但兩個 thread 不要互相等待 (規則 M3)。
- **Monitor + checker**：一個在每個 posedge 執行的 block，同時看 B、R、W 三個 channel。
- **Expected queue**：依 ID 分開，例如 `txn exp_b[16][$]`。收到 BID / RID 時，從那個 ID 的 queue 最前面拿出來比對，這樣同時檢查了「資料對不對」和「相同 ID 的順序」。

記憶體模型在「產生」寫入交易時就可以更新，因為 DUT 依 AW 的順序執行寫入。讀取的期望值在「產生」讀取交易時算好，前提是遵守規則 M8。

</details>

<details>
<summary>Hint 2: handshake 的檢查</summary>

SPEC-2、SPEC-3 很適合用 concurrent assertion：上一個 posedge `BVALID = 1` 但沒有 handshake，這個 posedge `BVALID` 必須還是 1，而且 `BID`、`BRESP` 沒變。

```systemverilog
property p_b_hold;
    @(posedge ACLK) disable iff(!ARESETn)
    (BVALID && !BREADY) |=> (BVALID && $stable({BID, BRESP}));
endproperty

a_b_hold : assert property(p_b_hold) else begin
    $display("FAIL SPEC-2/3: B channel changed before the handshake");
    $finish;
end
```

要讓這個檢查有機會觸發，TB 的 `BREADY` / `RREADY` 不能永遠是 1，要隨機拉低，而且有時候要連續拉低好幾個 cycle。

</details>

<details>
<summary>Hint 3: 刺激的 checklist</summary>

我寫了一個「一次只送一筆、只用 INCR 且長度 1 ~ 8、WSTRB 全 1、沒有錯誤位址、`BREADY` / `RREADY` 永遠是 1」的簡單 TB，只抓到 3/13。下面這些情況你的 TB 都有打到嗎？

- 三種 burst 都有，包含 4 種長度的 WRAP
- 很長的 INCR burst (幾百個 beat)
- 隨機的 WSTRB
- 單一 beat 的 burst (`AxLEN = 0`)
- 超出範圍的位址，特別是剛好超出邊界的那一段
- 還沒寫過的位址直接讀
- 多筆 outstanding，包含相同 ID 和不同 ID
- W burst 一個接一個、中間沒有空檔
- `BREADY` / `RREADY` 連續好幾個 cycle 是 0

</details>

## Follow-up

通過之後再想：

1. 把 TB 改寫成 class-based 的 layered 架構 (transaction、generator、driver、monitor、scoreboard、environment)，和 Lab03 一樣。哪些部分可以在 AW / AR 之間共用？
2. 加上 functional coverage：burst 種類 × 長度、RESP、相同 ID 的 outstanding 數量、backpressure 長度。用 coverage 證明 Hint 3 的每一項都有打到。
3. 如果 DUT 改成支援 read data interleaving (不同 ID 的 beat 可以交錯)，你的 checker 要改哪裡？

全部通過後，`code/.judge/problem-5/bugs.md` 有每個 bug 的說明。
