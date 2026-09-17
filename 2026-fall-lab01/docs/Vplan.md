# Verificaiton Plan

### Constraints 

## 1. Input Constraints

### Opcode Latency

`Inst_latency_I` 是 per-opcode latency table。同一個 test pattern 內，相同 opcode 共用 latency；不同 test pattern 可以重新 randomize。

| Opcode | Instruction | Legal latency |
|---:|---|---:|
| 0 | ADD | 1-5 |
| 1 | SUB | 1-5 |
| 2 | MUL | 20-40 |
| 3 | DIV | 30-50 |
| 4 | LOAD | 6-10 |
| 5 | STORE | 6-10 |
| 6 | BRANCH | 2-4 |
| 7 | JUMP | 1 |

```systemverilog
constraint latency_c {
    add_latency    inside {[1:5]};
    sub_latency    inside {[1:5]};
    mul_latency    inside {[20:40]};
    div_latency    inside {[30:50]};
    load_latency   inside {[6:10]};
    store_latency  inside {[6:10]};
    branch_latency inside {[2:4]};
    jump_latency   == 1;
}
```

Latency coverage 應包含每種 opcode 的 minimum、middle 與 maximum。

## 2. Memory Address Constraints

DUT 不考慮 memory dependency，因此 stimulus 必須避免會因 reordering 改變結果的 address conflict。

| Same-address pair | CRV rule |
|---|---|
| LOAD -> LOAD | 允許 |
| STORE -> LOAD | 避免 |
| LOAD -> STORE | 避免 |
| STORE -> STORE | 避免 |

因此我們應該要避免掉上述三個情況使用相同的 Address。


## 3. Dependency Graph Constraints

每個 test pattern 只能屬於以下一種 graph type：

| Graph type | Rule |
|---|---|
| No chain | 8 條 instruction 全部 independent |
| One chain | 一條長度 2-8 的 chain，其餘 instruction independent |
| Two chains | 兩條 vertex-disjoint chain，合計包含全部 8 條 instruction |

額外限制：

- 同一條 chain 必須維持原始 dependency order。
- Chain 與 independent instruction 之間不可有 dependency。
- 兩條 chain 之間不可有 dependency。
- 不產生 branch、merge、cross-chain edge 或 cycle。

CRV 應先 randomize graph type 與 chain length，再產生 register fields，最後重新 decode dependency graph，排除 accidental dependency。


本題 latency 是 per-opcode，不是 lat[i] 對應第 i 條 instruction。

## Verification Architecture

```
00_TESTBED/
├── TESTBED.v
├── PATTERN.sv
├── if.sv
├── generator.sv
├── driver.sv
├── monitor.sv
├── scoreboard.sv
├── pkg.sv
└── cmodel/
    └── oiss_golden.c
```