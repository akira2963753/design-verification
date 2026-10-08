# Problem 5 Bug List

答案表，通過 `make judge` 之前不要看。

| BUG | 違反的 SPEC | 內容 | 怎麼抓 |
|---|---|---|---|
| BUG_1 | SPEC-6 | B response 在倒數第二個 W beat handshake 時就排入，`BVALID` 可能比最後一個 W beat 先出現 (資料仍然正確) | 記錄每筆寫入的 W 是否送完；收到 `BVALID` 時檢查那筆的 W 已經全部 handshake。最後一個 W beat 要有延遲才看得到 |
| BUG_2 | SPEC-5 | byte lane 3 用 `WSTRB[2]` 判斷要不要寫 | 隨機 WSTRB，再讀回比對 |
| BUG_3 | SPEC-9 | read 挑選下一個 burst 時沒有檢查「同 ID 是否有更早的 AR」，相同 ID 的 read burst 會亂序 | 多筆 outstanding 且相同 ID 的 read，依 ID 分開的 expected queue |
| BUG_4 | SPEC-7 | read 路徑的 WRAP16 (`ARLEN = 15`) 用 32 bytes 當 wrap 區塊，應該是 64 bytes (寫入路徑正確) | WRAP 長度 16 的 read，起點不在 64 bytes 邊界上 |
| BUG_5 | SPEC-2 | `BREADY` 連續 3 個 cycle 是 0 時，`BVALID` 掉下來 1 個 cycle 再重新拉高 | `BREADY` 連續拉低 3 個 cycle 以上，檢查 `BVALID` 維持 |
| BUG_6 | SPEC-8 | 寫入的範圍檢查用 `AWADDR[31:13]`，`0x1000 ~ 0x1FFF` 被當成合法，回 OKAY 並寫到 `0x000 ~ 0xFFF` | 寫入剛好超出邊界的位址 (`0x1000 ~ 0x1FFF`)，檢查 BRESP |
| BUG_7 | SPEC-7 | `ARLEN = 0` 的單一 beat read 沒有拉 `RLAST` | 單一 beat 的 read，檢查 `RLAST` |
| BUG_8 | SPEC-4 | 寫入路徑的 INCR 位址只有低 10 bit 會遞增，跨過 1KB 邊界時繞回 1KB 區塊開頭 | 跨過 `0x400` / `0x800` / `0xC00` 的 INCR 寫入，再讀回 |
| BUG_9 | SPEC-1 | reset 沒有清記憶體，沒寫過的位址讀出來是 X | 還沒寫過的位址直接讀，期望 0 |
| BUG_10 | SPEC-3 | `RREADY = 0` 時 DUT 還是會送出下一個 beat，蓋掉還沒 handshake 的 beat | `RREADY` 隨機拉低，檢查 R payload 穩定 |
| BUG_11 | SPEC-6、SPEC-10 | `BID` 用「最新收到的 AWID」，而不是完成的那筆的 AWID | 多筆 outstanding 且不同 ID 的寫入 |
| BUG_12 | SPEC-4 | 寫入路徑的 FIXED burst 位址會遞增 (當成 INCR) | FIXED 寫入，再讀回 |
| BUG_13 | SPEC-10、SPEC-4 | 前一個 W burst 的最後一個 beat 之後，下一個 burst 的第一個 beat 緊接著來 (中間沒有空的 cycle) 時，第一個 beat 寫到前一個 burst 的位址 | W burst 一個接一個連續送，再讀回 |

## 驗證紀錄 (2026-10-05, VCS 2021.09)

- 參考 TB (AW / W / AR 各一個 driver thread、隨機 backpressure、依 ID 分開的 expected queue、handshake 穩定性檢查、先讀沒寫過的位址、分 write / read / 混合階段)：seed 1 ~ 5 都是 13/13，`make judge` 約 18 s。
- 簡單 TB (一次只送一筆、INCR 長度 1 ~ 8、WSTRB 全 1、沒有錯誤位址、`BREADY` / `RREADY` 永遠是 1)：3/13，只抓到 BUG_7、BUG_8、BUG_9。
- BUG_3 原本只有在 R engine 閒置時才會觸發，seed 3 漏抓；DUT 改成依 LFSR 隨機決定「最舊優先 / 最新優先」挑選 AR 後，seed 1 ~ 5 都抓得到。
