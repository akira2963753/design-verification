# Problem 2: Sliding Window Maximum (滑動視窗最大值)

| 難度 | 題型 | 預估時間 | 原型 |
|---|---|---|---|
| Medium | 演算法 | 60 min | LeetCode 239. Sliding Window Maximum |

## 背景

驗證 ADC 或 DSP 類的設計時，monitor 會收集一長串 sample，再檢查「最近 W 個 sample 裡的峰值在哪裡」，例如確認 AGC (automatic gain control) 有沒有在峰值出現後正確調整增益，或抓出 clipping 發生的位置。sample 是 16-bit 2's complement，會有負數。

## 題目

給定 N 個 sample `x[0] ~ x[N-1]` 和視窗大小 W。視窗從最左邊開始，每次往右移一格，對每個視窗 `x[i : i+W-1]` (`i = 0 ~ N-W`) 輸出**最大值的 index**。

- 視窗內有好幾個一樣大的最大值時，輸出**最小 (最早)** 的 index。
- 輸出共 `N - W + 1` 個 index。`N < W` 時一個視窗都沒有，回傳空的 queue。

## 介面規格

在 `src/sol.sv` 的 `package sol_pkg` 裡**自己寫出**下面四樣東西。名稱要完全一致，judge 會直接用。

| 名稱 | 種類 | 規格 |
|---|---|---|
| `sample_t` | typedef | 16-bit signed (2's complement) |
| `sample_q` | typedef | `sample_t` 的 queue |
| `idx_q` | typedef | `int` 的 queue |
| `window_max` | function automatic | 輸入 sample queue 和 W，回傳每個視窗最大值的 index |

Function prototype：

```systemverilog
function automatic idx_q window_max(sample_q x, int w);
```

Judge (`src/test.sv`) 的呼叫方式：

```systemverilog
sample_q xq;
idx_q got_q;
sample_t s;

s = -3;
xq.push_back(s);
...
got_q = window_max(xq, 3);
```

## 範例

**Example 1**

```
Input  : x = 1 3 -1 -3 5 3 6 7, W = 3
Output : 1 1 4 4 6 7
```

| 視窗 | 內容 | 最大值 | index |
|---|---|---|---|
| `x[0:2]` | 1 3 -1 | 3 | 1 |
| `x[1:3]` | 3 -1 -3 | 3 | 1 |
| `x[2:4]` | -1 -3 5 | 5 | 4 |
| `x[3:5]` | -3 5 3 | 5 | 4 |
| `x[4:6]` | 5 3 6 | 6 | 6 |
| `x[5:7]` | 3 6 7 | 7 | 7 |

**Example 2**

```
Input  : x = 4 2 4 1 4, W = 3
Output : 0 2 2
```

第一個視窗 `4 2 4` 有兩個 4，取比較早的 index 0。第三個視窗 `4 1 4` 也一樣，取 index 2 而不是 4。

**Example 3**

```
Input  : x = -5 -2 -8 -1, W = 2
Output : 1 1 3
```

全部都是負數，最大值是最接近 0 的那個。

## 限制

- `0 <= N <= 200000`
- `1 <= W <= 200000` (W 可能比 N 大)
- `-32768 <= x[i] <= 32767`
- 時間限制 **5 s**，只計算 `simv` 的執行時間，不包含 compile

## 作答流程

1. 照「介面規格」在 `src/sol.sv` 寫 code，**只改這個檔**。
2. 在 server 的 `problem-2/` 底下跑 `make`。
3. 看最後一行的 `Result`。

| 指令 | 用途 |
|---|---|
| `make` | 跑全部 22 組測資 |
| `make case=2` | 只跑第 2 組，不管有沒有過都印出 input、expected、got |
| `make time_limit=30` | 放寬時間限制，debug 用 |
| `make clean` | 清掉 VCS 產生的檔案 |

| 判定結果 | 意思 |
|---|---|
| `Accepted (22/22)` | 全部通過 |
| `Wrong Answer` | 第一個 FAIL 的組別會印出 input、expected、got，以及第一個不同的視窗 |
| `Time Limit Exceeded` | 超過時間限制，最後那行沒印出 PASS/FAIL 的組別就是超時的那組 |
| `Compile Error` | 印出 VCS 的 error 訊息 |

測資共 22 組：範例 3 組、edge case 10 組、random 7 組、效能 2 組 (N = 200000 / 150000，W = 50000)。

## 測資格式

想直接看 `testcase/` 時參考。`input.txt`：

```
<case 數>
<N> <W> <tag>
<x>             (N 行, 有號十進位)
...
```

`output.txt`：

```
<case 數>
<M> <tag>
<idx>           (M 行, M = max(0, N - W + 1))
...
```

## 本題練到的語法

Textbook 頁碼是書上印的頁碼，PDF 頁碼 = 書頁 + 43。

| 語法 | Textbook | ChipVerify |
|---|---|---|
| signed 型別：`logic signed [15:0]`、`shortint` | 2.1.2 (p.26) | [integer & byte](https://www.chipverify.com/systemverilog/systemverilog-data-types-integer-byte) |
| queue 當 deque：`push_back`、`pop_back`、`pop_front`、`q[0]`、`q[$]` | 2.4 (p.37, Sample 2.22) | [queue methods](https://www.chipverify.com/systemverilog/systemverilog-queue#systemverilog-queue-methods) |
| typedef 出 queue 型別 | 2.8 (p.48) | [typedef](https://www.chipverify.com/systemverilog/systemverilog-typedef-alias) |
| `while`、`for` 迴圈 | 3.1 (p.69) | [while loop](https://www.chipverify.com/systemverilog/systemverilog-while-do-while-loop) |
| function 回傳 queue | 3.5.2 (p.78) | [functions](https://www.chipverify.com/systemverilog/systemverilog-functions) |

## 注意

- **VCS 讀空的 queue 不會報錯**：對空 queue 讀 `q[0]`、`q[$]` 或呼叫 `pop_front()`，VCS 不會印任何 warning，直接回傳 0。這題的答案是 index，0 看起來完全合理，所以這種 bug 很難發現。存取前要自己確認 `size()`。
- `pop_back()`、`pop_front()` 有回傳值。不需要回傳值時，寫成 `void'(q.pop_back());` 可以明確表示「故意丟掉」。

## 提示

卡住再展開。

<details>
<summary>Hint 1: 解題思路</summary>

暴力解每個視窗掃一次是 O(N·W)，效能測資會 TLE。

用一個 deque 存 **index**，並維持「這些 index 對應的值，由前到後遞減」：

1. 新的 sample 進來前，從尾端丟掉比它小的 index，因為它們以後不可能再當最大值。
2. 前端的 index 已經滑出視窗的話，從前端丟掉。
3. 前端就是目前視窗的答案。

每個 index 最多進出 deque 各一次，所以是 O(N)。

</details>

<details>
<summary>Hint 2: 語法</summary>

queue 兩端的新增、刪除都很快，`q[0]` 是前端，`q[$]` 是尾端。

`while(q.size() > 0 && ...)` 這種寫法是安全的：`&&` 會 short-circuit，左邊是 false 時不會去讀右邊的空 queue。

</details>

<details>
<summary>Hint 3: Wrong Answer 或 TLE 卡住</summary>

- `sample_t` 有沒有宣告成 signed？`-1` 存成 unsigned 16-bit 是多少？
- 一樣大的值要保留最早的 index，從尾端丟的條件該用 `<` 還是 `<=`？
- 如果寫法是「只有最大值離開視窗時才重掃整個視窗」，遇到一直遞減的輸入會變多慢？

</details>

## Follow-up

通過之後再想：

1. 如果要同時輸出每個視窗的最大值和最小值 (算 peak-to-peak 振幅)，需要幾個 deque？
2. 如果只要回傳最大值、不需要 index，deque 只存「值」也做得到。這時前端什麼時候該 `pop_front()`？
3. 如果 sample 是一個一個進來的 (monitor 每個 cycle 收到一個 sample，就要更新目前視窗的最大值)，deque 要放在哪裡才能跨 call 保留狀態？(Ch5 class 會用到)
