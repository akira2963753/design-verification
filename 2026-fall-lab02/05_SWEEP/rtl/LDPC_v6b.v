/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    LDPC.v
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       LDPC
* Author:       Marco <harry2963753@gmail.com>, Claude Code Opus 5.5
* Version:      v6b
*
******************************************************************************/

//=============================================================
//                        Architecture
//=============================================================
// QC-LDPC decoder, base graph 4 x 8, Z = 16, normalized min-sum (beta = 0.75),
// mode 0 = flooding, mode 1 = layered, T_MAX = 8.
// One layer (16 CNs) per cycle on 16 x 7-port CNUs, 4 cycles per iteration in both
// modes; the CNUs are shared, the mode only changes the A bank update.
// Registers: B bank (APP) 1024 FF, A bank 1024 FF, C2V FIFO 1216 FF,
// control 17 FF (only the FSM state is reset).

module LDPC (
    // Input Port
    input clk,
    input rst_n,
    input in_mode_valid,
    input in_mode,
    input in_data_valid,
    input signed [5:0] in_data,

    // Output Port
    output out_valid,
    output signed [7:0] out_data,
    output out_warn
);

    //=============================================================
    //                        Interconnect
    //=============================================================
    wire mode, dec, shift_en, pass;
    wire [1:0] layer;

    //=============================================================
    //                         Controller
    //=============================================================
    LDPC_CTRL u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .in_mode_valid(in_mode_valid),
        .in_mode(in_mode),
        .in_data_valid(in_data_valid),
        .pass(pass),
        .mode(mode),
        .layer(layer),
        .dec(dec),
        .shift_en(shift_en),
        .out_valid(out_valid),
        .out_warn(out_warn)
    );

    //=============================================================
    //                          Datapath
    //=============================================================
    LDPC_DP u_dp (
        .clk(clk),
        .mode(mode),
        .layer(layer),
        .dec(dec),
        .shift_en(shift_en),
        .out_valid(out_valid),
        .in_data_valid(in_data_valid),
        .in_data(in_data),
        .pass(pass),
        .out_data(out_data)
    );

endmodule


//=============================================================
//                         Controller
//=============================================================
// IDLE: load mode and 128 LLRs, DEC: one layer per cycle, OUT: 128 APP outputs.
// The output starts in the syndrome check cycle itself (combinational out_valid),
// so latency = 4 x iterations.
module LDPC_CTRL (
    input clk,
    input rst_n,
    input in_mode_valid,
    input in_mode,
    input in_data_valid,
    input pass,
    output reg mode,
    output reg [1:0] layer,
    output dec,
    output shift_en,
    output out_valid,
    output out_warn
);

    localparam IDLE = 2'd0;
    localparam DEC = 2'd1;
    localparam OUT = 2'd2;

    reg [1:0] state, next_state;
    reg [6:0] io_cnt, io_cnt_d;
    reg [3:0] iter, iter_d;
    reg [1:0] layer_d;
    reg mode_d, warn_q, warn_d;
    wire idle, out_en, io_last, chk, done;

    //=============================================================
    //                        Status Decode
    //=============================================================
    assign idle = (state == IDLE);
    assign dec = (state == DEC);
    assign out_en = (state == OUT);
    // 128th input / output beat
    assign io_last = (io_cnt == 7'd127);
    // chk: first cycle of a new iteration, the finished iteration is checked while
    //      layer 0 of the next one is computed speculatively
    // done: syndrome pass or T_MAX (iter[3], iter stops at 8), speculative layer 0 dropped
    assign chk = dec && (layer == 2'd0) && (iter != 4'd0);
    assign done = chk && (pass || iter[3]);

    assign out_valid = out_en || done;
    assign out_warn = (done)? !pass : (out_en && warn_q);
    // The chain shifts in every IDLE cycle: the 128 input beats are consecutive (spec), so
    // the last 128 shifts are exactly the input LLRs; in_data_valid (input delay 0.5T)
    // stays off the 1024-bit mux select
    assign shift_en = idle || out_valid;

    //=============================================================
    //                             FSM
    //=============================================================
    // The only reset of the design: outputs must be 0 while rst_n is low (clock stopped)
    always @(posedge clk or negedge rst_n) begin : FSM_SEQ
        if(!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin : FSM_COMB
        case(state)
            IDLE: next_state = (in_data_valid && io_last)? DEC : IDLE;
            DEC: next_state = (done)? OUT : DEC;
            OUT: next_state = (io_last)? IDLE : OUT;
            default: next_state = IDLE;
        endcase
    end

    //=============================================================
    //                      Control Registers
    //=============================================================
    // No reset: every register below is initialized in IDLE before it is used
    always @(posedge clk) begin : CTRL_SEQ
        mode <= mode_d;
        warn_q <= warn_d;
        io_cnt <= io_cnt_d;
        layer <= layer_d;
        iter <= iter_d;
    end

    // mode: loaded by in_mode_valid before every decode
    // warn: sampled at done, only visible through out_en
    always @(*) begin : MODE_WARN_COMB
        mode_d = (idle && in_mode_valid)? in_mode : mode;
        warn_d = (done)? !pass : warn_q;
    end

    // IO counter: input beats in IDLE, output beats from done to the end of OUT,
    // cleared in the idle cycles between in_mode_valid and the first input beat
    always @(*) begin : IO_CNT_COMB
        if(done) io_cnt_d = 7'd1;
        else if((idle && in_data_valid) || out_en) io_cnt_d = io_cnt + 7'd1;
        else io_cnt_d = 7'd0;
    end

    // Layer / iteration counter: runs in DEC, cleared otherwise
    always @(*) begin : ITER_COMB
        if(dec) begin
            layer_d = layer + 2'd1;
            iter_d = (layer == 2'd3)? iter + 4'd1 : iter;
        end
        else begin
            layer_d = 2'd0;
            iter_d = 4'd0;
        end
    end

endmodule


//=============================================================
//                          Datapath
//=============================================================
// Rotation storage: every bank is kept in the layout of the current layer, so
// CNU u port p always reads slot u of group (p < 3)? p : p + 1 (no read mux).
// Group 3 (P3) has no CNU port and holds the masked column of the current layer;
// groups 0~3 move by one every layer (P0 <- P1 <- P2 <- P3 <- P0).
//
// Register map (slot s = g*16 + u of group g):
//   b_q[s*8 +: 8]            : B bank, running APP
//   a_q[s*8 +: 8]            : A bank, V2C source (layered: copy of B, flooding: snapshot)
//   f_q[(l*16+u)*19 +: 19]   : C2V FIFO level l = 0~3 of CNU u (level 0 = head)
// C2V word = {min1n[18:14], min2n[13:9], idx[8:6], sgn[5:0]}, sgn[6] = ^sgn[5:0].
module LDPC_DP (
    input clk,
    input mode,
    input [1:0] layer,
    input dec,
    input shift_en,
    input out_valid,
    input in_data_valid,
    input signed [5:0] in_data,
    output pass,
    output signed [7:0] out_data
);

    //=============================================================
    //                        Wiring Tables
    //=============================================================
    // Base graph shift BG[k][c], -1 = zero block (used by the syndrome wiring)
    function integer fn_bg;
        input integer k;
        input integer c;
        begin
            case(k*8 + c)
                0: fn_bg = -1; 1: fn_bg = 14; 2: fn_bg = 10; 3: fn_bg = 2; 4: fn_bg = 13; 5: fn_bg = 12; 6: fn_bg = 9; 7: fn_bg = 3;
                8: fn_bg = 5; 9: fn_bg = -1; 10: fn_bg = 14; 11: fn_bg = 10; 12: fn_bg = 2; 13: fn_bg = 13; 14: fn_bg = 12; 15: fn_bg = 9;
                16: fn_bg = 0; 17: fn_bg = 5; 18: fn_bg = -1; 19: fn_bg = 14; 20: fn_bg = 10; 21: fn_bg = 2; 22: fn_bg = 13; 23: fn_bg = 12;
                24: fn_bg = 7; 25: fn_bg = 0; 26: fn_bg = 5; 27: fn_bg = -1; 28: fn_bg = 14; 29: fn_bg = 10; 30: fn_bg = 2; 31: fn_bg = 13;
                default: fn_bg = -1;
            endcase
        end
    endfunction

    // Layer-0 layout (after the input phase and at the end of every iteration):
    // logical column c is in group G0[c], slot u holds VN 16*c + (u + O0[c]) % 16
    function integer fn_g0;
        input integer c;
        begin
            case(c)
                0: fn_g0 = 3;
                1: fn_g0 = 0;
                2: fn_g0 = 1;
                3: fn_g0 = 2;
                default: fn_g0 = c;
            endcase
        end
    endfunction

    function integer fn_o0;
        input integer c;
        begin
            case(c)
                0: fn_o0 = 6; 1: fn_o0 = 14; 2: fn_o0 = 10; 3: fn_o0 = 2;
                4: fn_o0 = 13; 5: fn_o0 = 12; 6: fn_o0 = 9; default: fn_o0 = 3;
            endcase
        end
    endfunction

    // Layer-0 layout: logical column held by group g (inverse of G0)
    function integer fn_c0;
        input integer g;
        begin
            case(g)
                0: fn_c0 = 1;
                1: fn_c0 = 2;
                2: fn_c0 = 3;
                3: fn_c0 = 0;
                default: fn_c0 = g;
            endcase
        end
    endfunction

    // Write-back source group, same for every layer: groups 0~3 take the next group
    // (group 2 takes P3, the column leaving its masked layer), groups 4~7 keep theirs
    function integer fn_src;
        input integer g;
        begin
            case(g)
                0: fn_src = 1;
                1: fn_src = 2;
                2: fn_src = 3;
                3: fn_src = 0;
                default: fn_src = g;
            endcase
        end
    endfunction

    // Write-back rotation leaving layer k: new[r] = src[(r + ROT[k][g]) % 16].
    // ROT = slot offset of the column in layer k+1 minus layer k, with slot offset
    // BG + E[k] (E = {0, 1, 15, 9}) or M[k] for the masked column (M = {6, 4, 14, 3});
    // E and M were searched offline for the fewest write-back mux inputs (55).
    function integer fn_rot;
        input integer k;
        input integer g;
        begin
            case(k*8 + g)
                0: fn_rot = 5; 1: fn_rot = 9; 2: fn_rot = 0; 3: fn_rot = 6; 4: fn_rot = 6; 5: fn_rot = 2; 6: fn_rot = 4; 7: fn_rot = 7;
                8: fn_rot = 2; 9: fn_rot = 9; 10: fn_rot = 0; 11: fn_rot = 15; 12: fn_rot = 6; 13: fn_rot = 3; 14: fn_rot = 15; 15: fn_rot = 1;
                16: fn_rot = 1; 17: fn_rot = 5; 18: fn_rot = 0; 19: fn_rot = 6; 20: fn_rot = 14; 21: fn_rot = 2; 22: fn_rot = 15; 23: fn_rot = 11;
                24: fn_rot = 5; 25: fn_rot = 12; 26: fn_rot = 15; 27: fn_rot = 6; 28: fn_rot = 6; 29: fn_rot = 9; 30: fn_rot = 14; 31: fn_rot = 13;
                default: fn_rot = 0;
            endcase
        end
    endfunction

    // Physical group read by CNU port p, and CNU port of group g (g != 3)
    function integer fn_pgrp;
        input integer p;
        begin
            fn_pgrp = (p < 3)? p : p + 1;
        end
    endfunction

    function integer fn_port;
        input integer g;
        begin
            fn_port = (g < 3)? g : g - 1;
        end
    endfunction

    // Chain head: VN 0 of column 0, the output position
    localparam integer HEAD = fn_g0(0)*16 + (16 - fn_o0(0)) % 16;

    //=============================================================
    //                          Registers
    //=============================================================
    reg [1023:0] b_q, a_q;
    reg [1215:0] f_q;
    wire [1023:0] b_d, a_d;
    wire [1215:0] f_d;

    // No reset: every datapath register is overwritten during the input phase
    always @(posedge clk) begin : DP_SEQ
        b_q <= b_d;
        a_q <= a_d;
        f_q <= f_d;
    end

    //=============================================================
    //                          CNU Array
    //=============================================================
    // CNU u port p: A / B operands from slot u of group fn_pgrp(p), fixed wiring
    wire [895:0] cnu_a, cnu_b, cnu_bn;
    wire [303:0] cnu_wn;

    genvar gu, gp, gg, gr, gk, gc;
    generate
        for(gu = 0; gu < 16; gu = gu + 1) begin : CNU_GEN
            for(gp = 0; gp < 7; gp = gp + 1) begin : PORT_GEN
                assign cnu_a[gu*56 + gp*8 +: 8] = a_q[(fn_pgrp(gp)*16 + gu)*8 +: 8];
                assign cnu_b[gu*56 + gp*8 +: 8] = b_q[(fn_pgrp(gp)*16 + gu)*8 +: 8];
            end

            LDPC_CNU u_cnu (
                .a_in(cnu_a[gu*56 +: 56]),
                .b_in(cnu_b[gu*56 +: 56]),
                .w_old(f_q[gu*19 +: 19]),
                .w_new(cnu_wn[gu*19 +: 19]),
                .b_new(cnu_bn[gu*56 +: 56])
            );
        end
    endgenerate

    //=============================================================
    //                          C2V FIFO
    //=============================================================
    // Shift register, one level per layer: level 3 <- new words (zero outside decode,
    // so C2V = 0 in the first iteration); level 0 is the old C2V of the current layer
    assign f_d = {((dec)? cnu_wn : 304'd0), f_q[1215:304]};

    //=============================================================
    //                        B Next State
    //=============================================================
    // Per slot 5:1 mux: shift chain (IO) or the write-back rotation of the current layer
    wire [7:0] tail_in;

    assign tail_in = (in_data_valid)? {{2{in_data[5]}}, in_data} : 8'd0;

    generate
        for(gg = 0; gg < 8; gg = gg + 1) begin : B_GRP
            for(gr = 0; gr < 16; gr = gr + 1) begin : B_SLOT
                wire [7:0] chain;
                wire [31:0] wb;

                // Shift chain in layer-0 layout: next VN of the same column; the last VN
                // of a column takes VN 0 of the next column, column 7 takes the input
                if((gr + fn_o0(fn_c0(gg))) % 16 != 15) begin : CH_NEXT
                    assign chain = b_q[(gg*16 + (gr + 1) % 16)*8 +: 8];
                end
                else if(fn_c0(gg) < 7) begin : CH_LINK
                    assign chain = b_q[(fn_g0(fn_c0(gg) + 1)*16 + (16 - fn_o0(fn_c0(gg) + 1)) % 16)*8 +: 8];
                end
                else begin : CH_TAIL
                    assign chain = tail_in;
                end

                // Write-back leaving layer k: rotated CNU output, or rotated P3 content
                for(gk = 0; gk < 4; gk = gk + 1) begin : WB_GEN
                    if(fn_src(gg) == 3) begin : FROM_P3
                        assign wb[gk*8 +: 8] = b_q[(3*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                    end
                    else begin : FROM_CNU
                        assign wb[gk*8 +: 8] = cnu_bn[((gr + fn_rot(gk, gg)) % 16)*56 + fn_port(fn_src(gg))*8 +: 8];
                    end
                end

                assign b_d[(gg*16 + gr)*8 +: 8] = (shift_en)? chain : wb[layer*8 +: 8];
            end
        end
    endgenerate

    //=============================================================
    //                        A Next State
    //=============================================================
    // Flooding layer 0~2: hold the snapshot, only move it with the layout (4:1 mux);
    // otherwise (layered, flooding layer 3, IO) A follows B_next
    wire a_hold;

    assign a_hold = !mode && dec && (layer != 2'd3);

    generate
        for(gg = 0; gg < 8; gg = gg + 1) begin : A_GRP
            for(gr = 0; gr < 16; gr = gr + 1) begin : A_SLOT
                wire [31:0] mv;

                for(gk = 0; gk < 3; gk = gk + 1) begin : MV_GEN
                    assign mv[gk*8 +: 8] = a_q[(fn_src(gg)*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                end
                // layer 3 is never held (don't care)
                assign mv[31:24] = b_d[(gg*16 + gr)*8 +: 8];

                assign a_d[(gg*16 + gr)*8 +: 8] = (a_hold)? mv[layer*8 +: 8] : b_d[(gg*16 + gr)*8 +: 8];
            end
        end
    endgenerate

    //=============================================================
    //                          Syndrome
    //=============================================================
    // B is in layer-0 layout at the end of every iteration: 64 x XOR7 on the sign bits
    // (fixed wiring), pass = NOR64
    wire [63:0] parity;

    generate
        for(gk = 0; gk < 4; gk = gk + 1) begin : SYN_LAYER
            for(gr = 0; gr < 16; gr = gr + 1) begin : SYN_CN
                wire [7:0] hard;

                for(gc = 0; gc < 8; gc = gc + 1) begin : SYN_COL
                    if(fn_bg(gk, gc) < 0) begin : NO_EDGE
                        assign hard[gc] = 1'b0;
                    end
                    else begin : EDGE
                        assign hard[gc] = b_q[(fn_g0(gc)*16 + (gr + fn_bg(gk, gc) - fn_o0(gc) + 16) % 16)*8 + 7];
                    end
                end
                assign parity[gk*16 + gr] = ^hard;
            end
        end
    endgenerate

    assign pass = ~|parity;

    //=============================================================
    //                           Output
    //=============================================================
    assign out_data = (out_valid)? b_q[HEAD*8 +: 8] : 8'd0;

endmodule


//=============================================================
//                 CNU: 7-port NMS check node
//=============================================================
// Per port p (C2V_old in sign-magnitude, x - c2v = x + ({000, mag} ^ {8{~s}}) + ~s):
//   V2C  = clip(A - C2V_old, +-31) -> magnitude key {y, s}, |V2C| = y + s
//          (ones' complement magnitude, no incrementer)
//   B_new = (B - C2V_old) + C2V_new, full precision (no clip)
module LDPC_CNU (
    input [55:0] a_in,
    input [55:0] b_in,
    input [18:0] w_old,
    output [18:0] w_new,
    output [55:0] b_new
);

    wire [41:0] key;
    wire [6:0] v2c_s, sgn_new, sgn_old;
    wire [4:0] min1n, min2n;
    wire [2:0] idx;
    wire total;

    //=============================================================
    //                   V2C Key and B - C2V_old
    //=============================================================
    // Old C2V word: sgn[6] restored from the even parity of the 7 C2V signs
    assign sgn_old = {^w_old[5:0], w_old[5:0]};

    genvar gp;
    generate
        for(gp = 0; gp < 7; gp = gp + 1) begin : PORT_GEN
            wire [4:0] mag_o, mag_n;
            wire s_o, s_n, big;
            wire [7:0] op_o, ta, tb, y;

            // Old C2V operand: decompress (min2n on the idx port), conditional inversion,
            // ~s_o is the carry-in
            assign mag_o = (w_old[8:6] == gp)? w_old[13:9] : w_old[18:14];
            assign s_o = sgn_old[gp];
            assign op_o = {3'b000, mag_o} ^ {8{~s_o}};

            // V2C = A - C2V_old, magnitude key with clip at 31
            assign ta = a_in[gp*8 +: 8] + op_o + {7'd0, ~s_o};
            assign y = ta ^ {8{ta[7]}};
            assign big = (y[7:5] != 3'b000) || (y[4:0] == 5'd31);
            assign key[gp*6 +: 6] = (big)? 6'b111110 : {y[4:0], ta[7]};
            assign v2c_s[gp] = ta[7];

            // B_new = (B - C2V_old) + C2V_new, the min1 port gets min2
            assign tb = b_in[gp*8 +: 8] + op_o + {7'd0, ~s_o};
            assign mag_n = (idx == gp)? min2n : min1n;
            assign s_n = sgn_new[gp];
            assign b_new[gp*8 +: 8] = tb + ({3'b000, mag_n} ^ {8{s_n}}) + {7'd0, s_n};
        end
    endgenerate

    //=============================================================
    //                          CN Update
    //=============================================================
    // min1n / min2n: normalized minimum and second minimum of |V2C|
    LDPC_MIN7 u_min7 (
        .key(key),
        .min1n(min1n),
        .min2n(min2n),
        .idx(idx)
    );

    // C2V sign of port p = XOR of the other 6 V2C signs
    assign total = ^v2c_s;
    assign sgn_new = {7{total}} ^ v2c_s;

    // Compressed C2V word; sgn[6] is dropped (even parity of the 7 C2V signs)
    assign w_new = {min1n, min2n, idx, sgn_new[5:0]};

endmodule


//=============================================================
//    Normalized min1 / min2 / idx finder (12 comparators)
//=============================================================
// Ports 0~3 and 4~6 are ranked with parallel comparators, then one parallel merge.
// Ties: the lower port wins (same result as a compare tree).
// The 4 rank outputs are normalized in parallel with the final compares and the merge
// selects normalized values (normalization is monotonic), so no adder follows the merge.
module LDPC_MIN7 (
    input [41:0] key,
    output [4:0] min1n,
    output [4:0] min2n,
    output [2:0] idx
);

    wire [5:0] m1_a, m2_a, m1_b, m2_b;
    wire [4:0] n1_a, n2_a, n1_b, n2_b;
    wire [1:0] i_a, i_b;
    wire c_f, c_x, c_y;

    LDPC_MIN4 u_min4 (
        .k0(key[5:0]),
        .k1(key[11:6]),
        .k2(key[17:12]),
        .k3(key[23:18]),
        .m1(m1_a),
        .m2(m2_a),
        .i1(i_a)
    );

    LDPC_MIN3 u_min3 (
        .k0(key[29:24]),
        .k1(key[35:30]),
        .k2(key[41:36]),
        .m1(m1_b),
        .m2(m2_b),
        .i1(i_b)
    );

    LDPC_NORM u_n1_a (
        .key(m1_a),
        .mag(n1_a)
    );

    LDPC_NORM u_n2_a (
        .key(m2_a),
        .mag(n2_a)
    );

    LDPC_NORM u_n1_b (
        .key(m1_b),
        .mag(n1_b)
    );

    LDPC_NORM u_n2_b (
        .key(m2_b),
        .mag(n2_b)
    );

    // Final merge, compares in parallel with the normalizers:
    //   min1 = (c_f)? m1_b : m1_a
    //   min2 = (c_f)? min(m2_b, m1_a) : min(m2_a, m1_b)
    assign c_f = (m1_b < m1_a);
    assign c_x = (m2_b < m1_a);
    assign c_y = (m2_a < m1_b);
    assign min1n = (c_f)? n1_b : n1_a;
    assign min2n = (c_f)? ((c_x)? n2_b : n1_a) : ((c_y)? n2_a : n1_b);
    assign idx = (c_f)? {1'b1, i_b} : {1'b0, i_a};

endmodule


//=============================================================
//            Rank 4 keys (6 parallel comparators)
//=============================================================
// w_ij (i < j): port j beats port i when k_j < k_i, otherwise port i beats port j.
// Rank 0 (beaten by nobody) is min1, rank 1 (beaten by exactly one) is min2.
module LDPC_MIN4 (
    input [5:0] k0,
    input [5:0] k1,
    input [5:0] k2,
    input [5:0] k3,
    output [5:0] m1,
    output [5:0] m2,
    output [1:0] i1
);

    wire w01, w02, w03, w12, w13, w23;
    wire [2:0] b0, b1, b2, b3;
    wire [3:0] r0, r1;

    assign w01 = (k1 < k0);
    assign w02 = (k2 < k0);
    assign w03 = (k3 < k0);
    assign w12 = (k2 < k1);
    assign w13 = (k3 < k1);
    assign w23 = (k3 < k2);

    // Ports beating port n
    assign b0 = {w03, w02, w01};
    assign b1 = {w13, w12, !w01};
    assign b2 = {w23, !w12, !w02};
    assign b3 = {!w23, !w13, !w03};

    // One-hot rank 0 and rank 1, AND-OR select
    assign r0 = {~|b3, ~|b2, ~|b1, ~|b0};
    assign r1 = {(^b3) & ~(&b3), (^b2) & ~(&b2), (^b1) & ~(&b1), (^b0) & ~(&b0)};

    assign m1 = ({6{r0[0]}} & k0) | ({6{r0[1]}} & k1) | ({6{r0[2]}} & k2) | ({6{r0[3]}} & k3);
    assign m2 = ({6{r1[0]}} & k0) | ({6{r1[1]}} & k1) | ({6{r1[2]}} & k2) | ({6{r1[3]}} & k3);
    assign i1 = {r0[2] | r0[3], r0[1] | r0[3]};

endmodule


//=============================================================
//            Rank 3 keys (3 parallel comparators)
//=============================================================
module LDPC_MIN3 (
    input [5:0] k0,
    input [5:0] k1,
    input [5:0] k2,
    output [5:0] m1,
    output [5:0] m2,
    output [1:0] i1
);

    wire w01, w02, w12;
    wire [1:0] b0, b1, b2;
    wire [2:0] r0, r1;

    assign w01 = (k1 < k0);
    assign w02 = (k2 < k0);
    assign w12 = (k2 < k1);

    // Ports beating port n
    assign b0 = {w02, w01};
    assign b1 = {w12, !w01};
    assign b2 = {!w12, !w02};

    // One-hot rank 0 and rank 1, AND-OR select
    assign r0 = {~|b2, ~|b1, ~|b0};
    assign r1 = {^b2, ^b1, ^b0};

    assign m1 = ({6{r0[0]}} & k0) | ({6{r0[1]}} & k1) | ({6{r0[2]}} & k2);
    assign m2 = ({6{r1[0]}} & k0) | ({6{r1[1]}} & k1) | ({6{r1[2]}} & k2);
    assign i1 = {r0[2], r0[1]};

endmodule


//=============================================================
//               NMS normalization (beta = 0.75)
//=============================================================
// round_half_up(0.75 * m) = (3m + 2) >> 2 with m = y + s -> (3y + (s ? 5 : 2)) >> 2
module LDPC_NORM (
    input [5:0] key,
    output [4:0] mag
);

    wire [6:0] n;

    assign n = {2'b00, key[5:1]} + {1'b0, key[5:1], 1'b0} + ((key[0])? 7'd5 : 7'd2);
    assign mag = n[6:2];

endmodule
