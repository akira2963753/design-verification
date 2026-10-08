# Problem 1: Merge Intervals (位址區段合併)

| 難度 | 題型 | 預估時間 | 原型 |
|---|---|---|---|
| Easy | 演算法 | 40 min | LeetCode 56. Merge Intervals |

## 背景

驗證時常常要處理 address range，例如檢查 memory map、合併 DMA descriptor、統計 coverage 打過哪些位址。這些區段可能重疊、沒有排序，常見的需求是把它們整理成**互不重疊、數量最少**的區段。

## 題目

### 名詞定義

- **區段 (range)**：一對 address `[lo, hi]`，代表 `lo`、`lo + 1`、…、`hi` 這些 address 全部都在區段裡。
  - 這是**閉區間**：`lo` 和 `hi` 兩端都算在內。
  - 一定滿足 `lo <= hi`。`lo == hi` 代表只有一個 address，例如 `[0x5, 0x5]`。
  - address 是 **32-bit unsigned**，範圍 `0x0000_0000 ~ 0xFFFF_FFFF`。
- **重疊**：兩個區段至少有一個共同的 address。
  - 例：`[0x10, 0x20]` 和 `[0x18, 0x30]` 共同擁有 `0x18 ~ 0x20`。
  - 例：`[0x10, 0x20]` 和 `[0x20, 0x30]` 共同擁有 `0x20`，也算重疊。
  - 例：`[0x00, 0xFF]` 和 `[0x40, 0x50]`，後者整個被前者包含，也算重疊。
- **相鄰**：兩個區段沒有共同的 address，但中間也**沒有空隙**，也就是前一段的 `hi` 再加 1 剛好是後一段的 `lo`。
  - 例：`[0x1000, 0x1FFF]` 和 `[0x2000, 0x2FFF]`：`0x1FFF + 1 = 0x2000`，相鄰。
- **分開**：兩個區段中間至少有一個 address 不屬於任何一段。
  - 例：`[0x10, 0x20]` 和 `[0x22, 0x30]`：`0x21` 不屬於任何一段，所以分開。

用數線來看 (`#` 代表該 address 在區段內)：

```
address :  10 11 12 13 14 15 16 17
A = [10,12]  #  #  #
B = [13,14]           #  #             A、B 相鄰 (12 + 1 = 13)
C = [16,17]                    #  #    B、C 分開 (15 是空的)
合併結果 :  [10,14]               [16,17]
```

### 要做的事

給你 N 個區段 (順序是亂的)，請把所有**重疊或相鄰**的區段合併成一段，最後回傳合併後的結果。

合併是**連鎖**的：如果 A 和 B 要合併、B 和 C 也要合併，那 A、B、C 最後都在同一段裡，即使 A 和 C 本身不重疊也不相鄰。

```
A = [0x10, 0x1F], B = [0x20, 0x2F], C = [0x30, 0x3F]
A-B 相鄰、B-C 相鄰  ->  結果只有一段 [0x10, 0x3F]
```

### 輸出要求

回傳的結果必須同時滿足下面 4 點，judge 會逐段比對，所以**順序和數值都要完全一樣**：

1. **涵蓋相同的 address**：一個 address 在輸入的某個區段裡，若且唯若它在輸出的某個區段裡。不能多、也不能少。
2. **依 `lo` 由小到大排列**。
3. **任兩段之間都要分開**：對輸出的第 i 段和第 i+1 段，`out[i].hi + 1 < out[i+1].lo` (數學上的加法，不考慮 overflow)。換句話說，輸出裡不能還有可以合併的兩段。
4. **段數最少**：滿足 1 ~ 3 的結果只有一種，所以答案是唯一的。

N = 0 時，回傳**空的 queue**。

## 介面規格

在 `src/sol.sv` 的 `package sol_pkg` 裡**自己寫出**下面三樣東西。名稱要**完全一致** (大小寫也一樣)，judge 會直接引用，名字不對會 Compile Error。

### 1. `range_t`：一個區段

| 項目 | 要求 |
|---|---|
| 種類 | `typedef struct` (packed 或 unpacked 都可以) |
| 欄位 | 恰好兩個：`lo` 和 `hi` |
| 欄位型別 | 32-bit **unsigned**。例如 `bit [31:0]`、`logic [31:0]`、`int unsigned` 都可以 |

judge 會用 `r.lo = ...`、`r.hi = ...` 讀寫欄位，所以欄位名稱一定要是 `lo`、`hi`。

### 2. `range_q`：區段的 queue

| 項目 | 要求 |
|---|---|
| 種類 | `typedef`，型別是「元素為 `range_t` 的 queue」 |
| 用途 | 當 function 的參數和回傳型別。SV 的 function 不能直接寫 `range_t [$]` 當回傳型別，要先 typedef |

### 3. `merge_ranges`：要實作的 function

```systemverilog
function automatic range_q merge_ranges(range_q in);
```

| 項目 | 說明 |
|---|---|
| 參數 `in` | 輸入的 N 個區段，順序任意，可能有重複、重疊、包含 |
| 回傳值 | 合併後的區段，必須符合上面「輸出要求」的 4 點 |
| `automatic` | 必須加，讓 function 的 local 變數每次呼叫都是新的 (judge 會連續呼叫 23 次) |
| 修改 `in` | 可以。`in` 是 pass by value，function 裡改它 (例如排序) 不會影響 judge 手上的資料 |
| 不需要做的事 | 不需要 `$display`、不需要讀檔、不需要處理 `lo > hi` 的輸入 (保證不會出現) |

### Judge 怎麼呼叫你

`src/test.sv` 對每一組測資做下面的事，你不需要改它，但了解流程對 debug 有幫助：

```systemverilog
import sol_pkg::*;

range_q in_q, got_q;
range_t r;

// 1. 從 testcase/input.txt 讀出 N 個區段，一個一個放進 in_q
r.lo = 32'h0000_1000;
r.hi = 32'h0000_1FFF;
in_q.push_back(r);
...

// 2. 呼叫你的 function
got_q = merge_ranges(in_q);

// 3. 把 got_q 和 testcase/output.txt 的答案逐段比對：
//    段數要一樣，第 i 段的 lo、hi 都要一樣 (用 !== 比，所以 X / Z 也算錯)
```

## 範例

**Example 1：一般情況**

```
Input  : [0x01, 0x03] [0x02, 0x06] [0x08, 0x0A] [0x0F, 0x12]
Output : [0x01, 0x06] [0x08, 0x0A] [0x0F, 0x12]
```

- `[0x01, 0x03]` 和 `[0x02, 0x06]` 重疊 (共同擁有 `0x02 ~ 0x03`)，合併成 `[0x01, 0x06]`。
- `[0x01, 0x06]` 和 `[0x08, 0x0A]` 中間的 `0x07` 是空的，分開。
- `[0x08, 0x0A]` 和 `[0x0F, 0x12]` 中間的 `0x0B ~ 0x0E` 是空的，分開。

**Example 2：相鄰也要合併**

```
Input  : [0x1000, 0x1FFF] [0x2000, 0x2FFF]
Output : [0x1000, 0x2FFF]
```

兩段沒有共同的 address，但 `0x1FFF + 1 = 0x2000`，中間沒有空隙，所以合併。

**Example 3：沒排序、有包含**

```
Input  : [0x22, 0x30] [0x10, 0x20] [0x12, 0x18]
Output : [0x10, 0x20] [0x22, 0x30]
```

- 輸入沒有依 `lo` 排序，輸出要排好。
- `[0x12, 0x18]` 整個在 `[0x10, 0x20]` 裡面，合併後還是 `[0x10, 0x20]` (注意 `hi` 不能被改小成 `0x18`)。
- `0x21` 不屬於任何一段，所以最後剩兩段。

**Example 4：其他邊界情況** (測資裡也有類似的組別)

| Input | Output | 說明 |
|---|---|---|
| (空的) | (空的) | N = 0，回傳空 queue |
| `[0x5, 0x5]` | `[0x5, 0x5]` | 只有一個 address 的區段 |
| `[0x3, 0x3] [0x1, 0x1] [0x2, 0x2]` | `[0x1, 0x3]` | 三個單點連在一起 |
| `[0x40, 0x4F] [0x40, 0x4F]` | `[0x40, 0x4F]` | 完全重複的區段只留一段 |
| `[0x8000_0000, 0xFFFF_FFFF] [0x0, 0x7FFF_FFFF]` | `[0x0, 0xFFFF_FFFF]` | 兩段相鄰，剛好蓋滿整個 32-bit address space |

## 限制

- `0 <= N <= 100000`
- `0 <= lo <= hi <= 0xFFFF_FFFF`
- 時間限制 **5 s**，只計算 `simv` 的執行時間，不包含 compile

## 作答流程

1. 照「介面規格」在 `src/sol.sv` 寫 code，**只改這個檔**。
2. 在 server 的 `problem-1/` 底下跑 `make`。
3. 看最後一行的 `Result`。

| 指令 | 用途 |
|---|---|
| `make` | 跑全部 23 組測資 |
| `make case=12` | 只跑第 12 組，不管有沒有過都印出 input、expected、got |
| `make time_limit=30` | 放寬時間限制，debug 用 |
| `make clean` | 清掉 VCS 產生的檔案 |

| 判定結果 | 意思 |
|---|---|
| `Accepted (23/23)` | 全部通過 |
| `Wrong Answer` | 第一個 FAIL 的組別會印出 input、expected、got，以及第一個不同的 index |
| `Time Limit Exceeded` | 超過時間限制，最後那行沒印出 PASS/FAIL 的組別就是超時的那組 |
| `Compile Error` | 印出 VCS 的 error 訊息 |

測資共 23 組：範例 3 組、edge case 11 組、random 8 組、效能 1 組 (N = 100000)。

## 測資格式

想直接看 `testcase/` 時參考。`input.txt`：

```
<case 數>
<N> <tag>
<lo> <hi>       (N 行, 8 位 hex)
...
```

`output.txt` 格式一樣，`N` 換成答案的區段數。

## 本題練到的語法

Textbook 頁碼是書上印的頁碼，PDF 頁碼 = 書頁 + 43。

| 語法 | Textbook | ChipVerify |
|---|---|---|
| `typedef struct`、packed struct | 2.8 (p.48)、2.9 (p.50) | [struct](https://www.chipverify.com/systemverilog/systemverilog-struct)、[typedef](https://www.chipverify.com/systemverilog/systemverilog-typedef-alias) |
| queue `[$]`：`push_back`、`size()`、`q[$]` | 2.4 (p.36) | [queue](https://www.chipverify.com/systemverilog/systemverilog-queue) |
| `sort() with (...)` 依 struct 欄位排序 | 2.6.3 (p.44, Sample 2.35) | [array manipulation](https://www.chipverify.com/systemverilog/systemverilog-array-manipulation) |
| function 回傳 queue (要先 typedef) | 3.5.2 (p.78) | [functions](https://www.chipverify.com/systemverilog/systemverilog-functions) |
| `package`、`import` | 2.10 (p.53) | [package](https://www.chipverify.com/systemverilog/systemverilog-package) |
| signed / unsigned、expression width | 2.1.2 (p.26)、2.16 (p.62) | |

## 注意

- VCS 對空的 queue 呼叫 `sort()` 會印 `Warning-[DT-MCEQ]`，不影響判題。想消掉的話，在 sort 之前先處理 N = 0 的情況。

## 提示

卡住再展開。

<details>
<summary>Hint 1: 解題思路</summary>

先依 `lo` 排序，再由左到右掃一次。每一段要嘛併進結果的最後一段，要嘛自己開新的一段。

</details>

<details>
<summary>Hint 2: 語法</summary>

struct 的 queue 可以用 `q.sort() with (item.lo)` 依欄位排序。結果的最後一段可以用 `res[$]` 存取，也可以直接改它的欄位。

</details>

<details>
<summary>Hint 3: Wrong Answer 卡在 edge case</summary>

`hi + 1` 在 `hi = 32'hFFFF_FFFF` 時會是多少？`int` 是 signed 還是 unsigned？

</details>

## Follow-up

通過之後再想：

1. `range_q in` 是 pass by value，N = 100000 時會整個複製一份。改成 `const ref` 有什麼差別？這樣還能直接對 `in` 做 `sort()` 嗎？
2. 如果 `range_t` 是 packed struct，而且 `lo` 宣告在 `hi` 前面，`q.sort()` 不加 `with` 會依什麼排序？
3. 如果 range 是一筆一筆進來的 (monitor 每收到一筆就要更新結果)，每次都重新排序太慢，資料結構要怎麼改？
