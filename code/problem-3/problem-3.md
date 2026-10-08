# Problem 3: LRU Cache (最近最少使用快取)

| 難度 | 題型 | 預估時間 | 原型 |
|---|---|---|---|
| Medium | 演算法 | 60 min | LeetCode 146. LRU Cache |

## 背景

驗證 cache、TLB 或 fully associative buffer 時，reference model 要預測每次存取是 hit 還是 miss，以及 cache 滿了之後要踢掉 (evict) 哪一筆。scoreboard 拿這些預測去比對 DUT 的 hit 訊號和 write-back 的位址。

最常見的替換策略是 **LRU (least recently used)**：踢掉最久沒被用到的那一筆。

## 題目

有一個容量為 `cap` 的 LRU cache，一開始是空的。依序執行 M 個操作，每個操作都回傳一個結果：

| 操作 | 行為 | 回傳 |
|---|---|---|
| `GET key` | key 在 cache 裡就讀出 value，並把 key 標成最近使用 | hit 回傳 value，miss 回傳 `-1` |
| `PUT key val` | key 已經在 cache 裡：更新 value，標成最近使用，**不踢任何東西**。key 不在：cache 滿了就先踢掉 LRU 那筆，再放入新的 key (標成最近使用) | 被踢掉的 **key**，沒踢就回傳 `-1` |

補充規則：

- 「使用」只有兩種：GET hit 和 PUT。
- GET miss 不改變 cache 的任何狀態。

## 介面規格

在 `src/sol.sv` 的 `package sol_pkg` 裡**自己寫出**下面五樣東西。名稱要完全一致，judge 會直接用。

| 名稱 | 種類 | 規格 |
|---|---|---|
| `op_e` | typedef enum | 兩個成員：`OP_GET`、`OP_PUT` |
| `op_t` | typedef struct | 三個欄位：`op` (`op_e`)、`key` (`int`)、`val` (`int`，GET 時用不到) |
| `op_q` | typedef | `op_t` 的 queue |
| `res_q` | typedef | `int` 的 queue |
| `lru_run` | function automatic | 執行全部操作，回傳每個操作的結果 |

Function prototype：

```systemverilog
function automatic res_q lru_run(int cap, op_q ops);
```

Judge (`src/test.sv`) 的呼叫方式：

```systemverilog
op_q oq;
res_q got_q;
op_t o;

o.op = OP_PUT;
o.key = 1;
o.val = 100;
oq.push_back(o);
...
got_q = lru_run(2, oq);
```

回傳的 `res_q` 長度要等於操作數，第 i 個結果對應第 i 個操作。

## 範例

**Example 1** (`cap = 2`)

```
Ops    : P 1 1, P 2 2, G 1, P 3 3, G 2, P 4 4, G 1, G 3, G 4
Output : -1 -1 1 2 -1 1 -1 3 4
```

| # | 操作 | 回傳 | 操作後的 cache (LRU → MRU) | 說明 |
|---|---|---|---|---|
| 0 | `P 1 1` | -1 | 1 | |
| 1 | `P 2 2` | -1 | 1 2 | |
| 2 | `G 1` | 1 | 2 1 | hit，1 變成最近使用 |
| 3 | `P 3 3` | 2 | 1 3 | 滿了，踢掉 LRU 的 2 |
| 4 | `G 2` | -1 | 1 3 | miss，cache 不變 |
| 5 | `P 4 4` | 1 | 3 4 | 踢掉 1 |
| 6 | `G 1` | -1 | 3 4 | |
| 7 | `G 3` | 3 | 4 3 | |
| 8 | `G 4` | 4 | 3 4 | |

**Example 2** (`cap = 2`)

```
Ops    : P 1 10, P 2 20, P 1 11, P 3 30, G 1, G 2
Output : -1 -1 -1 2 11 -1
```

`P 1 11` 是更新已經存在的 key，雖然 cache 是滿的也不踢東西。更新後 1 變成最近使用，所以 `P 3 30` 踢掉的是 2。

**Example 3** (`cap = 3`)

```
Ops    : P 5 0, G 5, G 6, P 0 7, G 0
Output : -1 0 -1 -1 7
```

key 和 value 都可能是 0。`G 5` 是 hit，value 剛好是 0，所以回傳 0，不是 -1。

## 限制

- `1 <= cap <= 100000`
- `0 <= M <= 300000`
- `0 <= key, val <= 2^31 - 1`
- 時間限制 **5 s**，只計算 `simv` 的執行時間，不包含 compile

## 作答流程

1. 照「介面規格」在 `src/sol.sv` 寫 code，**只改這個檔**。
2. 在 server 的 `problem-3/` 底下跑 `make`。
3. 看最後一行的 `Result`。

| 指令 | 用途 |
|---|---|
| `make` | 跑全部 20 組測資 |
| `make case=2` | 只跑第 2 組，不管有沒有過都印出前幾個操作的 expected 和 got |
| `make time_limit=30` | 放寬時間限制，debug 用 |
| `make clean` | 清掉 VCS 產生的檔案 |

| 判定結果 | 意思 |
|---|---|
| `Accepted (20/20)` | 全部通過 |
| `Wrong Answer` | 第一個 FAIL 的組別會列出出錯前的最近幾個操作，以及每個操作的 expected 和 got |
| `Time Limit Exceeded` | 超過時間限制，最後那行沒印出 PASS/FAIL 的組別就是超時的那組 |
| `Compile Error` | 印出 VCS 的 error 訊息 |

測資共 20 組：範例 3 組、edge case 10 組、random 6 組、效能 1 組 (`cap = 50000`，M = 300000)。

## 測資格式

想直接看 `testcase/` 時參考。`input.txt`：

```
<case 數>
<cap> <M> <tag>
G <key>  或  P <key> <val>      (M 行)
...
```

`output.txt`：

```
<case 數>
<M> <tag>
<result>                        (M 行)
...
```

## 本題練到的語法

Textbook 頁碼是書上印的頁碼，PDF 頁碼 = 書頁 + 43。

| 語法 | Textbook | ChipVerify |
|---|---|---|
| associative array：`exists`、`delete`、`num`、`first` / `next` | 2.5 (p.38~40, Sample 2.24、2.25) | [associative array](https://www.chipverify.com/systemverilog/systemverilog-associative-array) |
| `typedef enum` | 2.13 (p.57) | [enumeration](https://www.chipverify.com/systemverilog/systemverilog-enumeration) |
| struct 裡放 enum 欄位、struct 的 queue | 2.9 (p.50) | [struct](https://www.chipverify.com/systemverilog/systemverilog-struct) |
| 為什麼 queue 中間的刪除比較慢 | 2.4 (p.38) | [queue](https://www.chipverify.com/systemverilog/systemverilog-queue) |
| array locator：`find_first_index` | 2.6.2 (p.42) | [array manipulation](https://www.chipverify.com/systemverilog/systemverilog-array-manipulation) |

## 注意

- **VCS 讀不存在的 key 不會報錯**：`m[k]` 讀一個沒寫過的 key，會直接回傳預設值 (`int` 是 0，`logic` 是 X)。課本 p.40 說 simulator「可能」會印 warning，但 VCS 2021.09 實測什麼都沒印。要判斷 key 在不在，請用 `exists()`。
- `first(idx)`、`next(idx)` 會**修改**傳進去的 `idx` 變數，回傳值 1 / 0 表示有沒有找到。index 型別是 `int` 時，`first()` 依有號整數由小到大走，負數排在前面。
- queue 中間的 `delete(i)`、`insert(i)` 要搬動後面的元素，是 O(n)，`find_first_index` 也是從頭掃。

## 提示

卡住再展開。

<details>
<summary>Hint 1: 解題思路</summary>

需要兩種查詢都很快：

1. 給一個 key，找到它的 value。
2. 找出「最久沒被使用」的 key。

一個 associative array 只能做到第 1 種。associative array 的 `first()` 會給你**最小的 index**，如果 index 是「時間」呢？

</details>

<details>
<summary>Hint 2: 資料結構</summary>

用一個每次操作都加 1 的計數器當作時間，準備三個 associative array：

- key → value
- key → 最後使用的時間
- 時間 → key

每次「使用」某個 key，就把它舊的時間那筆刪掉，再寫入新的時間。要踢人時，對「時間 → key」呼叫 `first()`，拿到的就是 LRU。

</details>

<details>
<summary>Hint 3: Wrong Answer 卡住</summary>

- GET hit 之後，有沒有更新那個 key 的使用時間？
- PUT 一個已經存在的 key，剛好 cache 是滿的，你有沒有誤踢一筆？
- value 是 0 的 hit，會不會被當成 miss？

</details>

## Follow-up

通過之後再想：

1. 改用 doubly linked list (用 `int prev[int]`、`int next[int]` 兩個 associative array 當指標) 讓每個操作都是 O(1)。和時間戳記的版本比，哪個比較好寫、比較不容易錯？
2. 真正的 cache 大多是 set-associative，每個 set 各自做 LRU。如果 key 的低 4 bit 是 set index、每個 set 有 4 way，資料結構要怎麼改？
3. 這題一次給全部操作，是因為還沒用到 class。如果改成 `get()`、`put()` 分開呼叫，cache 的狀態要存在哪裡？(Ch5 class 會用到)
