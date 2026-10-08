# Problem 4 Bug List

答案表，通過 `make judge` 之前不要看。

| BUG | 違反的 SPEC | 內容 | 怎麼抓 |
|---|---|---|---|
| BUG_1 | SPEC-2 | read pointer 從 7 wrap 時跳到 1 而不是 0，第一次 wrap 之後資料順序錯 | 總共 pop 超過 8 筆，並比對資料 |
| BUG_2 | SPEC-3 | `full` 在 count = 7 時就拉高 (只有 output 錯，內部行為正確) | count = 7 時檢查 `full` |
| BUG_3 | SPEC-4 | `pop_valid = 0` 時 `pop_data` 保持上一筆資料，沒有清成 0 | `pop_valid = 0` 時也檢查 `pop_data` |
| BUG_4 | SPEC-7 | full 時同時 push 和 pop，push 被丟掉 (count 變 7，overflow 拉高) | 在 full 時同時 push 和 pop |
| BUG_5 | SPEC-1 | 所有 register 用 synchronous reset，`rst_n` 拉低後要等到 posedge 才 reset，開機時是 X | `rst_n` 拉低後、posedge 之前檢查 output |
| BUG_6 | SPEC-5 | full 時被拒絕的 push 仍然寫進記憶體，蓋掉最舊的那筆 (flag 和 count 都正確) | overflow 之後把資料 pop 出來比對 |
| BUG_7 | SPEC-6 | empty 時 pop，`pop_valid` 還是拉高並送出舊資料 (count 和 underflow 正確) | 抽乾後繼續 pop，檢查 `pop_valid` |
| BUG_8 | SPEC-8 | `rst_n` 拉高後的第一個 posedge 忽略 push / pop | reset 放開後立刻 push |
| BUG_9 | SPEC-3 | `count` output 只有 3 bit，滿的時候顯示 0 | 灌滿後檢查 `count` |
| BUG_10 | SPEC-7 | empty 時同時 push 和 pop，push 也被丟掉 | 在 empty 時同時 push 和 pop |
| BUG_11 | SPEC-5 | full 時同時 push 和 pop 也拉高 `overflow` (資料和 count 正確) | 在 full 時同時 push 和 pop，檢查 `overflow` |

## 驗證紀錄 (2026-10-05, VCS 2021.09)

- 參考 TB (每 cycle 比對全部 output、分階段 random、隨機插入中途 reset、reset 時在 posedge 前檢查、reset 後立刻 push)：seed 1~3 都是 11/11。
- 簡單 TB (每 cycle 比對全部 output、3000 cycle 的 50/50 random、開頭 reset 一次且 clock 照跑)：9/11，漏掉 BUG_5、BUG_8。和 full 有關的 bug 大約要跑到第 570 個 cycle 才第一次碰到 full。
