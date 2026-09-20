# Directed 4: 長 latency 的雙 chain 排程

- 4+4、3+5、2+6 各 1000 筆，共 3000 筆，不追加固定重播。
- 每條 chain 至少一條 latency >= 20 的指令。
- 每種長度的兩側總 latency 差依序輪流指定為 0、1、2，分別 334、333、333 筆。
- 4+4 的兩侧 latency 序列必須不同。
- opcode、register、長指令位置與輸入交錯方式，均在原有合法性限制內隨機。

directed_4_txn 繼承 directed_2_txn 的 structure_c，並以同名 profile_c
覆寫 directed 2 的 latency 限制。long_op 是父類別的輔助欄位，固定為 ADD
只為消除無用的隨機選擇，並不限制實際指令使用 ADD。
未使用的 latency 序列位置由 structure_c 固定為 0，不會被計入長指令。

沿用同 chain 每對指令有 dependency、跨 chain 沒有 dependency 的結構。
此條件提高測試長指令排程選擇的密度，不保證每筆都發生多次 tie。

執行順序: directed 1 → directed 2 → directed 3 → directed 4 → CRV。
Directed 合計 8004 筆，總筆數為 PATTERN_NUM + 8004。
scoreboard 發現比對錯誤仍繼續下一筆；randomization 或環境錯誤仍會停止。
