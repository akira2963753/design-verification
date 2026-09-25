/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    LDPC.v
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       LDPC
* Author:       Marco <harry2963753@gmail.com>, Claude Code Opus 5.5
* Version:      v11
*
******************************************************************************/

//=============================================================
//                        Architecture
//=============================================================
// QC-LDPC decoder, base graph 4 x 8, Z = 16, normalized min-sum (beta = 0.75),
// mode 0 = flooding, mode 1 = layered, T_MAX = 8.
// One layer (16 CNs) per two cycles on 16 x 7-port CNUs pipelined after the rank stage,
// 8 cycles per iteration in both modes; the CNUs are shared, the mode only changes the
// A bank update.
// Registers: B bank (APP) 1024 FF, A bank 1024 FF, C2V FIFO 912 FF, head 672 FF,
// CNU pipeline 608 FF, control 18 FF (only the FSM state is reset).

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
    wire mode, dec, ph, shift_en, pass;
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
        .ph(ph),
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
        .ph(ph),
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
// IDLE: load mode and 128 LLRs, DEC: one layer per two cycles (ph 0: CNU stage 1,
// ph 1: CNU stage 2 and write-back), OUT: 128 APP outputs. The output starts in the
// syndrome check cycle itself (combinational out_valid), so latency = 8 x iterations.
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
    output reg ph,
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
    reg ph_d, mode_d, warn_q, warn_d;
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
    //      layer 0 of the next one starts speculatively
    // done: syndrome pass or T_MAX (iter[3], iter stops at 8), speculative layer 0 dropped
    assign chk = dec && (layer == 2'd0) && !ph && (iter != 4'd0);
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
        ph <= ph_d;
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

    // Phase / layer / iteration counter: runs in DEC (two cycles per layer), cleared otherwise
    always @(*) begin : ITER_COMB
        if(dec) begin
            ph_d = !ph;
            layer_d = (ph)? layer + 2'd1 : layer;
            iter_d = (ph && layer == 2'd3)? iter + 4'd1 : iter;
        end
        else begin
            ph_d = 1'b0;
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
// Diagonal placement (BG is Toeplitz, BG[k][c] = BG[k-1][c-1]): in layer k logical
// column c sits in group G[(c - k) % 8], G = {3, 1, 4, 2, 7, 5, 6, 0}, so every layer
// the columns slide one step along G and most groups keep the same circulant shift.
// Group 3 (P3) has no CNU port and always holds the masked column (c == k).
//
// Register map (slot s = g*16 + u of group g):
//   b_q[s*8 +: 8]            : B bank, running APP
//   a_q[s*8 +: 8]            : A bank, V2C source (layered: copy of B, flooding: snapshot)
//   f_q[((l-1)*16+u)*19 +:19] : C2V FIFO level l = 1~3 of CNU u
//   h_q[u*42 +: 42]          : head (level 0) of CNU u, -C2V_old of port p at [p*6 +: 6]
// C2V word = {min1n[18:14], min2n[13:9], idx[8:6], sgn[5:0]}, sgn[6] = ^sgn[5:0].
module LDPC_DP (
    input clk,
    input mode,
    input [1:0] layer,
    input dec,
    input ph,
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
                1: fn_g0 = 1;
                2: fn_g0 = 4;
                3: fn_g0 = 2;
                4: fn_g0 = 7;
                5: fn_g0 = 5;
                6: fn_g0 = 6;
                default: fn_g0 = 0;
            endcase
        end
    endfunction

    function integer fn_o0;
        input integer c;
        begin
            case(c)
                0: fn_o0 = 10;
                1: fn_o0 = 14;
                2: fn_o0 = 10;
                3: fn_o0 = 2;
                4: fn_o0 = 13;
                5: fn_o0 = 12;
                6: fn_o0 = 9;
                default: fn_o0 = 3;
            endcase
        end
    endfunction

    // Layer-0 layout: logical column held by group g (inverse of G0)
    function integer fn_c0;
        input integer g;
        begin
            case(g)
                0: fn_c0 = 7;
                1: fn_c0 = 1;
                2: fn_c0 = 3;
                3: fn_c0 = 0;
                4: fn_c0 = 2;
                5: fn_c0 = 5;
                6: fn_c0 = 6;
                default: fn_c0 = 4;
            endcase
        end
    endfunction

    // Write-back source group when leaving layer k: the group that holds, in layer k,
    // the column group g holds in layer k + 1 (source 3 = P3, column leaving its masked layer)
    function integer fn_src;
        input integer k;
        input integer g;
        begin
            case(k*8 + g)
                0: fn_src = 3; 1: fn_src = 4; 2: fn_src = 7; 3: fn_src = 1; 4: fn_src = 2; 5: fn_src = 6; 6: fn_src = 0; 7: fn_src = 5;
                8: fn_src = 3; 9: fn_src = 4; 10: fn_src = 7; 11: fn_src = 1; 12: fn_src = 2; 13: fn_src = 6; 14: fn_src = 0; 15: fn_src = 5;
                16: fn_src = 3; 17: fn_src = 4; 18: fn_src = 7; 19: fn_src = 1; 20: fn_src = 2; 21: fn_src = 6; 22: fn_src = 0; 23: fn_src = 5;
                24: fn_src = 7; 25: fn_src = 6; 26: fn_src = 3; 27: fn_src = 5; 28: fn_src = 0; 29: fn_src = 4; 30: fn_src = 2; 31: fn_src = 1;
                default: fn_src = 0;
            endcase
        end
    endfunction

    // Write-back rotation leaving layer k: new[r] = src[(r + ROT[k][g]) % 16].
    // ROT = slot offset of the column in layer k+1 minus layer k, with slot offset
    // BG + E[k] (E = {0, 8, 0, 8}) or M[k] for the masked column (M = {10, 2, 10, 2});
    // placement, E and M were searched offline for the fewest write-back mux inputs (44).
    function integer fn_rot;
        input integer k;
        input integer g;
        begin
            case(k*8 + g)
                0: fn_rot = 3; 1: fn_rot = 12; 2: fn_rot = 13; 3: fn_rot = 4; 4: fn_rot = 0; 5: fn_rot = 11; 6: fn_rot = 14; 7: fn_rot = 9;
                8: fn_rot = 3; 9: fn_rot = 12; 10: fn_rot = 13; 11: fn_rot = 4; 12: fn_rot = 0; 13: fn_rot = 11; 14: fn_rot = 3; 15: fn_rot = 9;
                16: fn_rot = 3; 17: fn_rot = 12; 18: fn_rot = 13; 19: fn_rot = 4; 20: fn_rot = 0; 21: fn_rot = 15; 22: fn_rot = 3; 23: fn_rot = 9;
                24: fn_rot = 14; 25: fn_rot = 6; 26: fn_rot = 0; 27: fn_rot = 11; 28: fn_rot = 13; 29: fn_rot = 10; 30: fn_rot = 15; 31: fn_rot = 7;
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
    reg [911:0] f_q;
    reg [671:0] h_q;
    wire [1023:0] b_d, a_d;
    wire [911:0] f_d;
    wire [671:0] h_d;

    // No reset: every datapath register is overwritten during the input phase
    always @(posedge clk) begin : DP_SEQ
        b_q <= b_d;
        a_q <= a_d;
        f_q <= f_d;
        h_q <= h_d;
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
                .clk(clk),
                .a_in(cnu_a[gu*56 +: 56]),
                .b_in(cnu_b[gu*56 +: 56]),
                .old_neg(h_q[gu*42 +: 42]),
                .w_new(cnu_wn[gu*19 +: 19]),
                .b_new(cnu_bn[gu*56 +: 56])
            );
        end
    endgenerate

    //=============================================================
    //                          C2V FIFO
    //=============================================================
    // Shift register, one level per layer: level 3 <- new words (zero outside decode,
    // so C2V = 0 in the first iteration), level 2 <- level 3, level 1 <- level 2.
    // In DEC the FIFO and the head move once per layer, at the end of ph 1.
    wire f_shift;

    assign f_shift = !dec || ph;
    assign f_d = (f_shift)? {((dec)? cnu_wn : 304'd0), f_q[911:304]} : f_q;

    // Head <- level 1 decompressed one cycle ahead into -C2V_old per port (6b two's
    // complement, |C2V| <= 23): magnitude min2n on the idx port, else min1n. The idx
    // decode, the sign handling and the negation all stay out of the CNU loop.
    generate
        for(gu = 0; gu < 16; gu = gu + 1) begin : HEAD_GEN
            wire [18:0] w;
            wire [6:0] sgn;

            assign w = f_q[gu*19 +: 19];
            // sgn[6] restored from the even parity of the 7 C2V signs
            assign sgn = {^w[5:0], w[5:0]};
            for(gp = 0; gp < 7; gp = gp + 1) begin : HEAD_PORT
                wire [5:0] mag;

                assign mag = {1'b0, ((w[8:6] == gp)? w[13:9] : w[18:14])};
                // -C2V_old = +mag for a negative C2V, -mag for a positive one
                assign h_d[gu*42 + gp*6 +: 6] = (!f_shift)? h_q[gu*42 + gp*6 +: 6] : ((sgn[gp])? mag : (6'd0 - mag));
            end
        end
    endgenerate

    //=============================================================
    //                        B Next State
    //=============================================================
    // Per slot: shift chain (IO), hold (DEC ph 0) or the write-back rotation of the
    // current layer (DEC ph 1)
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
                    if(fn_src(gk, gg) == 3) begin : FROM_P3
                        assign wb[gk*8 +: 8] = b_q[(3*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                    end
                    else begin : FROM_CNU
                        assign wb[gk*8 +: 8] = cnu_bn[((gr + fn_rot(gk, gg)) % 16)*56 + fn_port(fn_src(gk, gg))*8 +: 8];
                    end
                end

                assign b_d[(gg*16 + gr)*8 +: 8] = (shift_en)? chain : ((ph)? wb[layer*8 +: 8] : b_q[(gg*16 + gr)*8 +: 8]);
            end
        end
    endgenerate

    //=============================================================
    //                        A Next State
    //=============================================================
    // DEC ph 0: hold; flooding layer 0~2: keep the snapshot, only move it with the layout;
    // otherwise (layered, flooding layer 3, IO) A follows B_next
    wire a_hold, a_stall;

    assign a_hold = !mode && dec && (layer != 2'd3);
    assign a_stall = dec && !ph;

    generate
        for(gg = 0; gg < 8; gg = gg + 1) begin : A_GRP
            for(gr = 0; gr < 16; gr = gr + 1) begin : A_SLOT
                wire [31:0] mv;

                for(gk = 0; gk < 3; gk = gk + 1) begin : MV_GEN
                    assign mv[gk*8 +: 8] = a_q[(fn_src(gk, gg)*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                end
                // layer 3 is never held (don't care)
                assign mv[31:24] = b_d[(gg*16 + gr)*8 +: 8];

                assign a_d[(gg*16 + gr)*8 +: 8] = (a_stall)? a_q[(gg*16 + gr)*8 +: 8] : ((a_hold)? mv[layer*8 +: 8] : b_d[(gg*16 + gr)*8 +: 8]);
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
//            CNU: 7-port NMS check node, 2 stages
//=============================================================
// Per port p (-C2V_old comes from the head as 6b two's complement, x - c2v = x + sext(neg)):
//   V2C  = clip(A - C2V_old, +-31) -> magnitude key {y, s}, |V2C| = y + s
//          (ones' complement magnitude, no incrementer)
//   B_new = (B - C2V_old) + C2V_new, full precision (no clip)
// Stage 1 (ph 0): V2C keys and signs, rank of ports 0~3 and 4~6
// Pipeline register (38b): the 4 rank outputs, one-hot min1 position of each half,
//                          C2V signs
// Stage 2 (ph 1): final merge, normalization, C2V select, B - C2V_old, APP update
// A, B and the head do not change during the two cycles of a layer.
module LDPC_CNU (
    input clk,
    input [55:0] a_in,
    input [55:0] b_in,
    input [41:0] old_neg,
    output [18:0] w_new,
    output [55:0] b_new
);

    wire [41:0] key;
    wire [6:0] v2c_s, sgn_s1;
    wire [5:0] m1_a, m2_a, m1_b, m2_b;
    wire [3:0] h_a;
    wire [2:0] h_b;
    wire [37:0] pipe_d;
    reg [37:0] pipe_q;

    //=============================================================
    //                  Stage 1: V2C Key and Rank
    //=============================================================
    genvar gp;
    generate
        for(gp = 0; gp < 7; gp = gp + 1) begin : KEY_GEN
            wire [7:0] neg_o, ta, y;
            wire big;

            // -C2V_old, sign extended to 8b
            assign neg_o = {{2{old_neg[gp*6 + 5]}}, old_neg[gp*6 +: 6]};

            // V2C = A - C2V_old, magnitude key with clip at 31
            assign ta = a_in[gp*8 +: 8] + neg_o;
            assign y = ta ^ {8{ta[7]}};
            assign big = (y[7:5] != 3'b000) || (y[4:0] == 5'd31);
            assign key[gp*6 +: 6] = (big)? 6'b111110 : {y[4:0], ta[7]};
            assign v2c_s[gp] = ta[7];
        end
    endgenerate

    LDPC_MIN4 u_min4 (
        .k0(key[5:0]),
        .k1(key[11:6]),
        .k2(key[17:12]),
        .k3(key[23:18]),
        .m1(m1_a),
        .m2(m2_a),
        .h1(h_a)
    );

    LDPC_MIN3 u_min3 (
        .k0(key[29:24]),
        .k1(key[35:30]),
        .k2(key[41:36]),
        .m1(m1_b),
        .m2(m2_b),
        .h1(h_b)
    );

    // C2V sign of port p = XOR of the other 6 V2C signs
    assign sgn_s1 = {7{^v2c_s}} ^ v2c_s;

    //=============================================================
    //                      Pipeline Register
    //=============================================================
    // No reset, no enable: loaded every cycle, used in ph 1 (the inputs do not change
    // between ph 0 and ph 1 of a layer)
    assign pipe_d = {sgn_s1, h_b, h_a, m2_b, m1_b, m2_a, m1_a};

    always @(posedge clk) begin : PIPE_SEQ
        pipe_q <= pipe_d;
    end

    //=============================================================
    //             Stage 2: Final Merge and APP Update
    //=============================================================
    wire [5:0] p_m1_a, p_m2_a, p_m1_b, p_m2_b, x, y, k1, k2;
    wire [3:0] p_h_a;
    wire [2:0] p_h_b, idx;
    wire [6:0] sgn_new, hot;
    wire [4:0] min1n, min2n;
    wire c_f;

    assign {sgn_new, p_h_b, p_h_a, p_m2_b, p_m1_b, p_m2_a, p_m1_a} = pipe_q;

    // Final merge: both min2 candidates are compared in parallel with c_f
    assign c_f = (p_m1_b < p_m1_a);
    assign x = (p_m2_b < p_m1_a)? p_m2_b : p_m1_a;
    assign y = (p_m2_a < p_m1_b)? p_m2_a : p_m1_b;
    assign k1 = (c_f)? p_m1_b : p_m1_a;
    assign k2 = (c_f)? x : y;
    assign hot = (c_f)? {p_h_b, 4'b0000} : {3'b000, p_h_a};
    assign idx = {hot[4] | hot[5] | hot[6], hot[2] | hot[3] | hot[6], hot[1] | hot[3] | hot[5]};

    // Normalized C2V magnitudes
    LDPC_NORM u_norm1 (
        .key(k1),
        .mag(min1n)
    );

    LDPC_NORM u_norm2 (
        .key(k2),
        .mag(min2n)
    );

    generate
        for(gp = 0; gp < 7; gp = gp + 1) begin : APP_GEN
            wire [7:0] neg_o, tb;
            wire [4:0] mag_n;

            // B_new = (B - C2V_old) + C2V_new, the min1 port gets min2
            assign neg_o = {{2{old_neg[gp*6 + 5]}}, old_neg[gp*6 +: 6]};
            assign tb = b_in[gp*8 +: 8] + neg_o;
            assign mag_n = (hot[gp])? min2n : min1n;
            assign b_new[gp*8 +: 8] = tb + ({3'b000, mag_n} ^ {8{sgn_new[gp]}}) + {7'd0, sgn_new[gp]};
        end
    endgenerate

    // Compressed C2V word; sgn[6] is dropped (even parity of the 7 C2V signs)
    assign w_new = {min1n, min2n, idx, sgn_new[5:0]};

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
    output [3:0] h1
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
    assign h1 = r0;

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
    output [2:0] h1
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
    assign h1 = r0;

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
