# Directed 2: 雙 chain 的 tie 排程

執行順序為 directed 1 (1000 筆)、directed 2 (3004 筆)、directed 3 (1000 筆)、一般 CRV。
directed 3 每筆隨機選一個 register，全部 8 條指令的 rs、rt、rd 都使用它；opcode 與 latency 在原本合法 constraint 下隨機。
每個 seed 在 random 筆數設為 50000 時，預期總數為 55004。
筆數由 generator::DIRECTED_NUM 傳給 driver、monitor、scoreboard、coverage 與 watchdog。

## 固定重播

| Case | 來源 | Inst_seq_I | Inst_latency_I | 最佳 cycle |
|---|---|---|---|---:|
| 0 | 圖片，對稱 4+4 | 124124524324200200400200 | 042186795041 | 26 |
| 1 | 原 pattern 10637，對稱 4+4 | 2490530a4b530bc8441c32a5 | 044249a15041 | 14 |
| 2 | 原 pattern 30002，近似平衡 4+4 | 9008471178a83b914308a133 | 042206c20141 | 16 |
| 3 | 非對稱 3+5 | 124124324324124000c00000 | 043186794081 | 8 |

圖片沒有提供未使用 opcode 的 latency，這些欄位填合法最小值。
固定輸入仍透過 txn.randomize() 建立相依圖等 metadata，維持 coverage 相容性。
最佳 cycle 仍由既有獨立 reference model 計算，沒有繞過 checker。

## 三類變體

每類 1000 筆，log 中的 scenario 為 0、1、2。

- 0: 4+4，前 500 筆固定兩側 (1,L,1,1)，後 500 筆循環掃描長指令的 16 種位置組合。L 使用 MUL、DIV 或 LOAD 的合法 latency，兩側共用 L。
- 1: 4+4，兩側總 latency 差按筆數循環指定為 0、1、2，且 latency 序列不同。
- 2: 2+6 與 3+5 各 500 筆，所有使用到的 latency 限為 1～3。其中 250 筆保留 (1,3,1) 與 (1,2,2,1,1) 的結構。

各類透過 member_a 隨機分配原始指令位置，允許兩條 chain 交錯。
同 chain 每對先後指令都要求 dependency，跨 chain 不允許 dependency。
這是完整合法圖集合的一個子集；一般 CRV 繼續探索其他 hazard 結構。
opcode、register 與合法 latency 由 solver 選擇，同 opcode 在一筆內共用 latency。
這些限制用來提高發生 tie 排程問題的機會，不表示每個變體必然有多次 tie。

## 失敗行為

scoreboard 比對失敗會印出完整輸入、輸出、預期值與原因，累計 failed_num 後繼續下一筆。
全部執行完畢後列出 checked、passed、failed，因此固定重播失敗不會擋住後續變體。
randomize 失敗、mailbox 異常與 watchdog timeout 等環境錯誤仍會停止模擬。
