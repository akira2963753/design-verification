/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    LDPC.v
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       LDPC
* Author:       Marco <harry2963753@gmail.com>, Claude Code Opus 5.5
* Version:      
*
******************************************************************************/

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
    wire [1:0] k;

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
        .k(k),
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
        .k(k),
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
// Two-segment FSM (state register + next-state logic); mode, warn and the
// IO / layer / iteration counters are separate registers. Only the state
// register is reset: every other register is initialized in IDLE before use.
// Output starts in the syndrome check cycle itself (combinational out_valid),
// so latency = 4 x iterations.
module LDPC_CTRL (
    input clk,
    input rst_n,
    input in_mode_valid,
    input in_mode,
    input in_data_valid,
    input pass,
    output reg mode,
    output reg [1:0] k,
    output dec,
    output shift_en,
    output out_valid,
    output out_warn
);

    localparam IDLE = 2'd0;
    localparam DEC = 2'd1;
    localparam OUT = 2'd2;

    reg [1:0] state, next_state;
    reg [6:0] cnt;
    reg [3:0] iter;
    reg warn_q;
    wire idle, out_en, cnt_last, chk, done;

    //=============================================================
    //                        Status Decode
    //=============================================================
    // chk: first cycle of a new iteration, syndrome of the finished iteration is checked
    // done: stop decoding (syndrome pass or T_max reached), speculative layer 0 is dropped
    assign idle = (state == IDLE);
    assign dec = (state == DEC);
    assign out_en = (state == OUT);
    assign cnt_last = (cnt == 7'd127);
    assign chk = dec && (k == 2'd0) && (iter != 4'd0);
    assign done = chk && (pass || iter[3]);
    assign out_valid = out_en || done;
    // warn_q has no reset: it is only visible in OUT
    assign out_warn = (done)? !pass : (out_en && warn_q);
    assign shift_en = in_data_valid || out_valid;

    //=============================================================
    //                             FSM
    //=============================================================
    // The only reset in the design: outputs must be 0 while rst_n is low (clock stopped)
    always @(posedge clk or negedge rst_n) begin : FSM_SEQ
        if(!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin : FSM_COMB
        case(state)
            IDLE: next_state = (in_data_valid && cnt_last)? DEC : IDLE;
            DEC: next_state = (done)? OUT : DEC;
            OUT: next_state = (cnt_last)? IDLE : OUT;
            default: next_state = IDLE;
        endcase
    end

    //=============================================================
    //                         Mode & Warn
    //=============================================================
    // mode is loaded by in_mode_valid before every decode
    always @(posedge clk) begin : MODE_REG
        if(idle && in_mode_valid) mode <= in_mode;
    end

    // Warn is sampled at done and held through OUT
    always @(posedge clk) begin : WARN_REG
        if(done) warn_q <= !pass;
    end

    //=============================================================
    //                          Counters
    //=============================================================
    // IO counter: input beats in IDLE, output beats from done to the end of OUT;
    // cleared in the idle cycles between in_mode_valid and the first input beat
    always @(posedge clk) begin : CNT_REG
        if(done) cnt <= 7'd1;
        else if((idle && in_data_valid) || out_en) cnt <= cnt + 7'd1;
        else cnt <= 7'd0;
    end

    // Layer / iteration counter, cleared whenever the FSM is not decoding
    always @(posedge clk) begin : ITER_REG
        if(dec) begin
            k <= k + 2'd1;
            if(k == 2'd3) iter <= iter + 4'd1;
        end
        else begin
            k <= 2'd0;
            iter <= 4'd0;
        end
    end

endmodule


//=============================================================
//                          Datapath
//=============================================================
// Rotation storage with physical column placement, 16 x 7-port CNU,
// shift chain, syndrome.
// Physical group g (0~7), slot u (0~15):
//   B[g][u] : running APP, 8b              -> b_q[(g*16+u)*8 +: 8]
//   A[g][u] : snapshot of B, 8b            -> a_q[(g*16+u)*8 +: 8]
//   fifo[l][u] : C2V word, 20b, l = 0 head -> f_q[(l*16+u)*20 +: 20]
// CNU u port p always reads slot u of group (p < 3)? p : p + 1.
// Group 3 (P3) has no CNU port: it holds the masked column of the current layer.
// Groups 0~3 move cyclically every layer (P0 <- P1 <- P2 <- P3 <- P0).
// Layer k: CNU u handles CN (u + E[k]) % 16, E = {0, 1, 15, 9}.
module LDPC_DP (
    input clk,
    input mode,
    input [1:0] k,
    input dec,
    input shift_en,
    input out_valid,
    input in_data_valid,
    input signed [5:0] in_data,
    output pass,
    output signed [7:0] out_data
);

    //=============================================================
    //                       Constant Tables
    //=============================================================
    // Base graph shift of layer kk, column gg (-1: zero matrix)
    function integer fn_bg;
        input integer kk;
        input integer gg;
        begin
            case(kk*8 + gg)
                0: fn_bg = -1; 1: fn_bg = 14; 2: fn_bg = 10; 3: fn_bg = 2;
                4: fn_bg = 13; 5: fn_bg = 12; 6: fn_bg = 9; 7: fn_bg = 3;
                8: fn_bg = 5; 9: fn_bg = -1; 10: fn_bg = 14; 11: fn_bg = 10;
                12: fn_bg = 2; 13: fn_bg = 13; 14: fn_bg = 12; 15: fn_bg = 9;
                16: fn_bg = 0; 17: fn_bg = 5; 18: fn_bg = -1; 19: fn_bg = 14;
                20: fn_bg = 10; 21: fn_bg = 2; 22: fn_bg = 13; 23: fn_bg = 12;
                24: fn_bg = 7; 25: fn_bg = 0; 26: fn_bg = 5; 27: fn_bg = -1;
                28: fn_bg = 14; 29: fn_bg = 10; 30: fn_bg = 2; 31: fn_bg = 13;
                default: fn_bg = 0;
            endcase
        end
    endfunction

    // Write-back source group of physical group gg when leaving layer kk (3: P3, no CNU port)
    function integer fn_src;
        input integer kk;
        input integer gg;
        begin
            case(kk*8 + gg)
                0: fn_src = 1; 1: fn_src = 2; 2: fn_src = 3; 3: fn_src = 0;
                4: fn_src = 4; 5: fn_src = 5; 6: fn_src = 6; 7: fn_src = 7;
                8: fn_src = 1; 9: fn_src = 2; 10: fn_src = 3; 11: fn_src = 0;
                12: fn_src = 4; 13: fn_src = 5; 14: fn_src = 6; 15: fn_src = 7;
                16: fn_src = 1; 17: fn_src = 2; 18: fn_src = 3; 19: fn_src = 0;
                20: fn_src = 4; 21: fn_src = 5; 22: fn_src = 6; 23: fn_src = 7;
                24: fn_src = 1; 25: fn_src = 2; 26: fn_src = 3; 27: fn_src = 0;
                28: fn_src = 4; 29: fn_src = 5; 30: fn_src = 6; 31: fn_src = 7;
                default: fn_src = 0;
            endcase
        end
    endfunction

    // Write-back rotation of physical group gg when leaving layer kk: new[r] = src[(r + D) % 16]
    function integer fn_rot;
        input integer kk;
        input integer gg;
        begin
            case(kk*8 + gg)
                0: fn_rot = 5; 1: fn_rot = 9; 2: fn_rot = 0; 3: fn_rot = 6;
                4: fn_rot = 6; 5: fn_rot = 2; 6: fn_rot = 4; 7: fn_rot = 7;
                8: fn_rot = 2; 9: fn_rot = 9; 10: fn_rot = 0; 11: fn_rot = 15;
                12: fn_rot = 6; 13: fn_rot = 3; 14: fn_rot = 15; 15: fn_rot = 1;
                16: fn_rot = 1; 17: fn_rot = 5; 18: fn_rot = 0; 19: fn_rot = 6;
                20: fn_rot = 14; 21: fn_rot = 2; 22: fn_rot = 15; 23: fn_rot = 11;
                24: fn_rot = 5; 25: fn_rot = 12; 26: fn_rot = 15; 27: fn_rot = 6;
                28: fn_rot = 6; 29: fn_rot = 9; 30: fn_rot = 14; 31: fn_rot = 13;
                default: fn_rot = 0;
            endcase
        end
    endfunction

    // Layer 0 layout: physical group of logical column cc
    function integer fn_g0;
        input integer cc;
        begin
            case(cc)
                0: fn_g0 = 3; 1: fn_g0 = 0; 2: fn_g0 = 1; 3: fn_g0 = 2;
                4: fn_g0 = 4; 5: fn_g0 = 5; 6: fn_g0 = 6; 7: fn_g0 = 7;
                default: fn_g0 = 0;
            endcase
        end
    endfunction

    // Layer 0 layout: offset of logical column cc (slot u holds VN 16*cc + (u + O0) % 16)
    function integer fn_o0;
        input integer cc;
        begin
            case(cc)
                0: fn_o0 = 6; 1: fn_o0 = 14; 2: fn_o0 = 10; 3: fn_o0 = 2;
                4: fn_o0 = 13; 5: fn_o0 = 12; 6: fn_o0 = 9; 7: fn_o0 = 3;
                default: fn_o0 = 0;
            endcase
        end
    endfunction

    // Layer 0 layout: logical column held by physical group cc
    function integer fn_c0;
        input integer cc;
        begin
            case(cc)
                0: fn_c0 = 1; 1: fn_c0 = 2; 2: fn_c0 = 3; 3: fn_c0 = 0;
                4: fn_c0 = 4; 5: fn_c0 = 5; 6: fn_c0 = 6; 7: fn_c0 = 7;
                default: fn_c0 = 0;
            endcase
        end
    endfunction
    // CNU port of physical group gg (group 3 has no port)
    function integer fn_port;
        input integer gg;
        begin
            fn_port = (gg < 3)? gg : gg - 1;
        end
    endfunction

    // Chain head: logical VN 0 (output) position
    localparam integer HEAD = (fn_g0(0)*16 + (16 - fn_o0(0)) % 16)*8;

    //=============================================================
    //                           Storage
    //=============================================================
    reg [1023:0] b_q;
    reg [1023:0] a_q;
    reg [1279:0] f_q;
    wire [1023:0] b_d;
    wire [1023:0] a_d;
    wire [1279:0] f_d;

    // Datapath storage has no reset: fully overwritten during input phase
    always @(posedge clk) begin : STORAGE
        b_q <= b_d;
        a_q <= a_d;
        f_q <= f_d;
    end

    //=============================================================
    //                          CNU Array
    //=============================================================
    wire [895:0] cnu_a;
    wire [895:0] cnu_b;
    wire [319:0] cnu_wn;
    wire [895:0] cnu_bn;

    genvar gu, gp, gg, gr, gk, gc;
    generate
        for(gu = 0; gu < 16; gu = gu + 1) begin : CNU_GEN
            for(gp = 0; gp < 7; gp = gp + 1) begin : PORT_GEN
                assign cnu_a[gu*56 + gp*8 +: 8] = a_q[(((gp < 3)? gp : gp + 1)*16 + gu)*8 +: 8];
                assign cnu_b[gu*56 + gp*8 +: 8] = b_q[(((gp < 3)? gp : gp + 1)*16 + gu)*8 +: 8];
            end
            LDPC_CNU u_cnu (
                .a_in(cnu_a[gu*56 +: 56]),
                .b_in(cnu_b[gu*56 +: 56]),
                .w_old(f_q[gu*20 +: 20]),
                .w_new(cnu_wn[gu*20 +: 20]),
                .b_new(cnu_bn[gu*56 +: 56])
            );
        end
    endgenerate

    //=============================================================
    //                     C2V FIFO (4 levels)
    //=============================================================
    // Shift every cycle; outside decode a zero word is pushed (C2V = 0, no X after reset)
    assign f_d = {((dec)? cnu_wn : 320'd0), f_q[1279:320]};

    //=============================================================
    //                        B Next State
    //=============================================================
    wire [7:0] tail_in;

    assign tail_in = (in_data_valid)? {{2{in_data[5]}}, in_data} : 8'd0;

    generate
        for(gg = 0; gg < 8; gg = gg + 1) begin : B_GRP
            for(gr = 0; gr < 16; gr = gr + 1) begin : B_SLOT
                wire [7:0] chain;
                wire [31:0] rot;

                // Shift chain in layer 0 layout: rotate by 1 inside a logical column,
                // last VN of a column links to the first VN of the next column
                if((gr + fn_o0(fn_c0(gg))) % 16 != 15) begin : CH_IN
                    assign chain = b_q[(gg*16 + (gr + 1) % 16)*8 +: 8];
                end
                else if(fn_c0(gg) < 7) begin : CH_LINK
                    assign chain = b_q[(fn_g0(fn_c0(gg) + 1)*16 + (16 - fn_o0(fn_c0(gg) + 1)) % 16)*8 +: 8];
                end
                else begin : CH_TAIL
                    assign chain = tail_in;
                end

                // Write back: rotated CNU output, or rotated P3 content (column leaving its masked layer)
                for(gk = 0; gk < 4; gk = gk + 1) begin : B_ROT
                    if(fn_src(gk, gg) == 3) begin : FROM_P3
                        assign rot[gk*8 +: 8] = b_q[(3*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                    end
                    else begin : FROM_CNU
                        assign rot[gk*8 +: 8] = cnu_bn[((gr + fn_rot(gk, gg)) % 16)*56 + fn_port(fn_src(gk, gg))*8 +: 8];
                    end
                end

                assign b_d[(gg*16 + gr)*8 +: 8] = (shift_en)? chain : rot[k*8 +: 8];
            end
        end
    endgenerate

    //=============================================================
    //                        A Next State
    //=============================================================
    // Flooding layer 0~2: move / rotate only (snapshot); otherwise A <= B_next
    wire a_rot;

    assign a_rot = !mode && dec && (k != 2'd3);

    generate
        for(gg = 0; gg < 8; gg = gg + 1) begin : A_GRP
            for(gr = 0; gr < 16; gr = gr + 1) begin : A_SLOT
                wire [31:0] rot;

                for(gk = 0; gk < 3; gk = gk + 1) begin : A_ROT
                    assign rot[gk*8 +: 8] = a_q[(fn_src(gk, gg)*16 + (gr + fn_rot(gk, gg)) % 16)*8 +: 8];
                end
                assign rot[31:24] = b_d[(gg*16 + gr)*8 +: 8];

                assign a_d[(gg*16 + gr)*8 +: 8] = (a_rot)? rot[k*8 +: 8] : b_d[(gg*16 + gr)*8 +: 8];
            end
        end
    endgenerate

    //=============================================================
    //                          Syndrome
    //=============================================================
    // B is in layer 0 layout at the end of every iteration -> fixed wiring
    wire [63:0] par;

    generate
        for(gk = 0; gk < 4; gk = gk + 1) begin : SYN_LAYER
            for(gr = 0; gr < 16; gr = gr + 1) begin : SYN_CN
                wire [7:0] hard;
                for(gc = 0; gc < 8; gc = gc + 1) begin : SYN_COL
                    if(fn_bg(gk, gc) < 0) begin : NC
                        assign hard[gc] = 1'b0;
                    end
                    else begin : CONN
                        assign hard[gc] = b_q[(fn_g0(gc)*16 + (gr + fn_bg(gk, gc) - fn_o0(gc) + 16) % 16)*8 + 7];
                    end
                end
                assign par[gk*16 + gr] = ^hard;
            end
        end
    endgenerate

    assign pass = ~|par;

    //=============================================================
    //                           Output
    //=============================================================
    assign out_data = (out_valid)? b_q[HEAD +: 8] : 8'd0;

endmodule


//=============================================================
//                 CNU: 7-port NMS check node
//=============================================================
// C2V word = {min1n[19:15], min2n[14:10], idx[9:7], sgn[6:0]}
// V2C magnitude key = {yc[4:0], sc}: |V2C| = yc + sc (ones' complement magnitude
// plus sign bit); ordering by key is consistent with ordering by |V2C|.
module LDPC_CNU (
    input [55:0] a_in,
    input [55:0] b_in,
    input [19:0] w_old,
    output [19:0] w_new,
    output [55:0] b_new
);

    wire [4:0] min1n_old, min2n_old, min1n, min2n;
    wire [2:0] idx_old, idx;
    wire [6:0] sgn_old, sgn_new, hot_old, hot_new, v2c_s;
    wire [41:0] key;
    wire [5:0] k1, k2;
    wire [6:0] n1, n2;
    wire total;

    assign min1n_old = w_old[19:15];
    assign min2n_old = w_old[14:10];
    assign idx_old = w_old[9:7];
    assign sgn_old = w_old[6:0];

    genvar gp;
    generate
        for(gp = 0; gp < 7; gp = gp + 1) begin : PORT_GEN
            wire [4:0] mag_o, mag_n;
            wire s_o, s_n, big;
            wire [7:0] op_o, ta, tb, y;

            assign hot_old[gp] = (idx_old == gp);
            assign hot_new[gp] = (idx == gp);

            // Decompress old C2V, sign-magnitude operand: x - c2v_old = x + op_o + ~s_o
            assign mag_o = (hot_old[gp])? min2n_old : min1n_old;
            assign s_o = sgn_old[gp];
            assign op_o = {3'b000, mag_o} ^ {8{~s_o}};

            // V2C = clip(A - c2v_old, +-31) as magnitude key + sign
            assign ta = a_in[gp*8 +: 8] + op_o + {7'd0, ~s_o};
            assign y = ta ^ {8{ta[7]}};
            assign big = (y[7:5] != 3'b000) || (y[4:0] == 5'd31);
            assign key[gp*6 +: 6] = (big)? 6'b111110 : {y[4:0], ta[7]};
            assign v2c_s[gp] = ta[7];

            // APP update: B - c2v_old + c2v_new (full precision, no clip)
            assign tb = b_in[gp*8 +: 8] + op_o + {7'd0, ~s_o};
            assign mag_n = (hot_new[gp])? min2n : min1n;
            assign s_n = sgn_new[gp];
            assign b_new[gp*8 +: 8] = tb + ({3'b000, mag_n} ^ {8{s_n}}) + {7'd0, s_n};
        end
    endgenerate

    LDPC_MIN7 u_min7 (
        .key(key),
        .min1(k1),
        .min2(k2),
        .idx(idx)
    );

    // Normalization: round_half_up(0.75 * m), m = yc + sc -> (3*yc + (sc ? 5 : 2)) >> 2
    assign n1 = {2'b00, k1[5:1]} + {1'b0, k1[5:1], 1'b0} + ((k1[0])? 7'd5 : 7'd2);
    assign n2 = {2'b00, k2[5:1]} + {1'b0, k2[5:1], 1'b0} + ((k2[0])? 7'd5 : 7'd2);
    assign min1n = n1[6:2];
    assign min2n = n2[6:2];

    assign total = ^v2c_s;
    assign sgn_new = {7{total}} ^ v2c_s;
    assign w_new = {min1n, min2n, idx, sgn_new};

endmodule


//=============================================================
//      7-input min1 / min2 / idx finder (9 comparators)
//=============================================================
module LDPC_MIN7 (
    input [41:0] key,
    output [5:0] min1,
    output [5:0] min2,
    output [2:0] idx
);

    wire [17:0] lo, hi;
    wire [2:0] sel;
    wire [5:0] m1_a, m2_a, m1_b, m2_b, p, q;
    wire [1:0] i_a;
    wire [2:0] i_b;
    wire c_b, c_f;

    // Level 1: sort pairs (0,1), (2,3), (4,5)
    genvar gi;
    generate
        for(gi = 0; gi < 3; gi = gi + 1) begin : PAIR_GEN
            wire [5:0] x0, x1;
            assign x0 = key[(2*gi)*6 +: 6];
            assign x1 = key[(2*gi + 1)*6 +: 6];
            assign sel[gi] = (x1 < x0);
            assign lo[gi*6 +: 6] = (sel[gi])? x1 : x0;
            assign hi[gi*6 +: 6] = (sel[gi])? x0 : x1;
        end
    endgenerate

    // Level 2a: merge (0,1) with (2,3)
    LDPC_MERGE #(.W(6), .IW(1)) u_merge_a (
        .a1(lo[5:0]),
        .a2(hi[5:0]),
        .ai(sel[0]),
        .b1(lo[11:6]),
        .b2(hi[11:6]),
        .bi(sel[1]),
        .m1(m1_a),
        .m2(m2_a),
        .mi(i_a)
    );

    // Level 2b: merge (4,5) with single 6
    assign c_b = (key[41:36] < lo[17:12]);
    assign m1_b = (c_b)? key[41:36] : lo[17:12];
    assign m2_b = (c_b)? lo[17:12] : ((hi[17:12] < key[41:36])? hi[17:12] : key[41:36]);
    assign i_b = (c_b)? 3'd6 : {2'b10, sel[2]};

    // Level 3: final merge
    assign c_f = (m1_b < m1_a);
    assign p = (c_f)? m1_a : m1_b;
    assign q = (c_f)? m2_b : m2_a;
    assign min1 = (c_f)? m1_b : m1_a;
    assign min2 = (q < p)? q : p;
    assign idx = (c_f)? i_b : {1'b0, i_a};

endmodule


//=============================================================
//                   Merge two sorted pairs
//=============================================================
// Inputs (a1 <= a2), (b1 <= b2); 2 comparators
module LDPC_MERGE #(
    parameter W = 6,
    parameter IW = 1
) (
    input [W-1:0] a1,
    input [W-1:0] a2,
    input [IW-1:0] ai,
    input [W-1:0] b1,
    input [W-1:0] b2,
    input [IW-1:0] bi,
    output [W-1:0] m1,
    output [W-1:0] m2,
    output [IW:0] mi
);

    wire c;
    wire [W-1:0] p, q;

    // min2 = c ? min(a1, b2) : min(a2, b1)
    assign c = (b1 < a1);
    assign p = (c)? a1 : b1;
    assign q = (c)? b2 : a2;
    assign m1 = (c)? b1 : a1;
    assign m2 = (q < p)? q : p;
    assign mi = (c)? {1'b1, bi} : {1'b0, ai};

endmodule
