/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    F_ATTN.v
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       F_ATTN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

/******************************************************************************
* Number formats (all fixed point, FP32 only at the input / output converters)
*   Q' = Q * c   26 fraction bits, c = log2(e) / sqare_root_2 (sqare_root_2 = 32'h3FB504F3)
*   K            17 fraction bits
*   V, W         22 fraction bits
*   t = Q' . K   20 fraction bits, the score already in the exponent of 2: e^(qk/sqrt2) = 2^t
*   weight       2^(t - r), r = integer running max >= t, 24 fraction bits, in (0, 1]
*   D            24 fraction bits, M 25 fraction bits, H = M / D 23 fraction bits
* Conversions, t and the numerator terms round to nearest (unbiased, one bit cheaper than
* truncation). Widths were picked with a bit-exact Python model: max |out - golden| = 3.5e-7
* over 3100 patterns (golden = double precision, demo tolerance = 1e-6).
* Signs: Q' is one's complement (value = Q_fx + sign, only XOR at the input), K / V / W are
* two's complement, so every dot product is one signed sum of products that synthesis can
* merge into a single partial-product tree.
* H = M / D uses a radix-2 carry-save SRT divider (no carry chain per quotient bit).
******************************************************************************/
module F_ATTN #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire [31:0] Q,
    input wire [31:0] K,
    input wire [31:0] V,
    input wire [31:0] out_weight,
    output reg out_valid,
    output reg [31:0] out
);

    localparam [1:0] IDLE = 2'd0, LOAD = 2'd1, CALC = 2'd2;
    reg [1:0] state, next_state;
    reg [5:0] in_cnt, tile_cnt;
    wire issue;
    wire kv_tail_sel, kv_rot, q_adv;
    wire tile_first, tile_last;

    // input conversion
    wire [7:0] q_e, k_e, v_e, w_e;
    wire [23:0] q_m, k_m, v_m, w_m;
    wire [45:0] q_num;
    wire [7:0] q_sa, k_sa, v_sa, w_sa;
    wire [27:0] q_sh;
    wire [25:0] k_sh;
    wire [23:0] v_sh, w_sh;
    wire [28:0] q_rd;
    wire [26:0] k_rd;
    wire [24:0] v_rd, w_rd;
    wire [25:0] q_mag;
    wire [24:0] k_mag;
    wire [21:0] v_mag, w_mag;
    wire [26:0] Q_fx;
    wire [25:0] K_fx;
    wire [22:0] V_fx, W_fx;

    // QKV Buffer 都分成兩個 head，且每個 head 有四條 lanes 每個 lane 裡面有 8 筆資料
    // [data size] name [lane][num]，注意 Q 分成 Cur 跟 Buf 主要是因為我們要固定 Q
    // Q' = one's complement {sign, 26-bit}, K = two's complement 26-bit, V = two's complement 23-bit
    reg [26:0] H1_Q_Cur [0:3];
    reg [26:0] H1_Q_Buf [0:3][0:6];
    reg [26:0] H2_Q_Cur [0:3];
    reg [26:0] H2_Q_Buf [0:3][0:6];
    reg [25:0] H1_K_Buf [0:3][0:7];
    reg [25:0] H2_K_Buf [0:3][0:7];
    reg [22:0] H1_V_Buf [0:3][0:7];
    reg [22:0] H2_V_Buf [0:3][0:7];

    // Weight Buffer [data size] name [lane][num], two's complement 23-bit
    reg [22:0] W_Buf [0:3][0:3];

    // output stage
    reg out_active;                     // 64 output cycles in progress
    reg [5:0] out_cnt;                  // {Q_block, token a / b, dim k} of the output in this cycle
    wire h_a_ready;                     // token a of a Q_block has both H words (from head 1)
    wire [22:0] H1_Ha0, H1_Ha1, H1_Hb0, H1_Hb1;      // {sign, 22-bit magnitude}
    wire [22:0] H2_Ha0, H2_Ha1, H2_Hb0, H2_Hb1;
    wire [22:0] H1_x0, H1_x1, H2_x0, H2_x1;          // H of the token being output
    wire signed [22:0] H1_y0, H1_y1, H2_y0, H2_y1;   // one's complement H (value = y + sign)
    wire signed [22:0] Wk0, Wk1, Wk2, Wk3;           // W[k][0..3]
    wire signed [47:0] wc0, wc1, wc2, wc3;           // + W when H is negative
    wire signed [47:0] facc;                         // Final with 45 fraction bits
    wire f_sign;
    wire [45:0] f_mag;
    wire [45:0] nz0, nz1, nz2, nz3, nz4, nz5;
    wire [5:0] f_lz;
    wire [7:0] f_exp;
    wire [31:0] final_res;

    wire [3:0] H1_wen, H2_wen, W_wen;

    // V is written and rotated 2 cycles after K: when a tile reaches S3 the V lanes look
    // exactly like the K lanes did when the tile was issued, so V needs no pipeline register
    reg [22:0] V_fx_d1, V_fx_d2;
    reg [3:0] H1_wen_d1, H1_wen_d2, H2_wen_d1, H2_wen_d2;
    reg v_rot_d1, v_rot_d2, v_tail_d1, v_tail_d2;

    // read port of the tile issued in this cycle (a = token 2i / 2j, b = token 2i+1 / 2j+1)
    // (V: the tile in S3)
    wire [26:0] H1_Qa0, H1_Qa1, H1_Qb0, H1_Qb1;
    wire [25:0] H1_Ka0, H1_Ka1, H1_Kb0, H1_Kb1;
    wire [22:0] H1_Va0, H1_Va1, H1_Vb0, H1_Vb1;
    wire [26:0] H2_Qa0, H2_Qa1, H2_Qb0, H2_Qb1;
    wire [25:0] H2_Ka0, H2_Ka1, H2_Kb0, H2_Kb1;
    wire [22:0] H2_Va0, H2_Va1, H2_Vb0, H2_Vb1;

    integer i, b;


    //=============================================================
    //                  Finite State Machine (FSM)
    //=============================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        case(state)
            IDLE: next_state = (in_valid)? LOAD : IDLE;
            LOAD: next_state = (in_cnt == 6'd63)? CALC : LOAD;
            CALC: next_state = (tile_cnt == 6'd63)? IDLE : CALC;
            default: next_state = IDLE;
        endcase
    end

    //=============================================================
    //                       Input Counter
    //=============================================================
    // index of the word on the input bus, wraps 63 -> 0 for the next pattern
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) in_cnt <= 6'd0;
        else if(in_valid) in_cnt <= in_cnt + 6'd1;
    end

    //=============================================================
    //                        Tile Counter
    //=============================================================
    // tile_cnt = {Q_block, K/V block} of the tile issued in this cycle
    // LOAD: in_cnt = 8, 16, ..., 56 -> K/V block 0 ~ 6 just completed (Q_block 0 tile 0 ~ 6)
    // CALC: one tile per cycle, Q_block 0 tile 7 then Q_block 1 ~ 7
    assign issue = ((state == LOAD) && (in_cnt[2:0] == 3'd0) && (in_cnt[5:3] != 3'd0)) || (state == CALC);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) tile_cnt <= 6'd0;
        else if(issue) tile_cnt <= tile_cnt + 6'd1;
    end

    // Q_block 0: K/V block j has just arrived at the lane tail, read it there (no rotation)
    // Q_block 1 ~ 7: read the lane head, rotate one block per tile (8 tiles = one full turn)
    assign kv_tail_sel = (tile_cnt[5:3] == 3'd0);
    assign kv_rot = (issue) && (tile_cnt[5:3] != 3'd0);

    // last tile of a Q_block: Cur <- next Q_block (first at cycle 64, when Q_Buf is full)
    assign q_adv = (issue) && (tile_cnt[2:0] == 3'd7);

    // position of the issued tile inside its Q_block (only meaningful with issue)
    assign tile_first = (tile_cnt[2:0] == 3'd0);
    assign tile_last = (tile_cnt[2:0] == 3'd7);

    //=============================================================
    //                      Input Conversion
    //=============================================================
    // fp32 = (-1)^s * m24 * 2^(e - 150), e = 0 is zero (ieee_compliance = 0)
    // each conversion keeps one extra bit then rounds: mag = (x + 1) >> 1 (round half up)
    // Q' (26 fraction bits): x = (m24 * c * 2^21) >> 18 >> (126 - e)   (|Q| <= 0.5 -> e <= 126)
    assign q_e = Q[30:23];
    assign q_m = {(q_e != 8'd0), Q[22:0]};
    assign q_num = q_m * 22'd2139388;
    assign q_sa = 8'd126 - q_e;
    assign q_sh = q_num[45:18] >> q_sa;
    assign q_rd = {1'b0, q_sh} + 29'd1;
    assign q_mag = ((q_e == 8'd0) || (q_e > 8'd126) || (q_sa > 8'd27))? 26'd0 : q_rd[26:1];
    assign Q_fx = {Q[31], q_mag ^ {26{Q[31]}}};    // one's complement, value = Q_fx + sign

    // K (17 fraction bits): x = (m24 << 2) >> (134 - e)   (0.5 <= |K| <= 255 -> 126 <= e <= 134)
    assign k_e = K[30:23];
    assign k_m = {(k_e != 8'd0), K[22:0]};
    assign k_sa = 8'd134 - k_e;
    assign k_sh = {k_m, 2'b00} >> k_sa;
    assign k_rd = {1'b0, k_sh} + 27'd1;
    assign k_mag = ((k_e == 8'd0) || (k_e > 8'd134) || (k_sa > 8'd25))? 25'd0 : k_rd[25:1];
    assign K_fx = (K[31])? (26'd0 - {1'b0, k_mag}) : {1'b0, k_mag};

    // V / W (22 fraction bits): x = m24 >> (127 - e)   (|V|, |W| <= 0.5 -> e <= 126)
    assign v_e = V[30:23];
    assign v_m = {(v_e != 8'd0), V[22:0]};
    assign v_sa = 8'd127 - v_e;
    assign v_sh = v_m >> v_sa;
    assign v_rd = {1'b0, v_sh} + 25'd1;
    assign v_mag = ((v_e == 8'd0) || (v_e > 8'd126) || (v_sa > 8'd23))? 22'd0 : v_rd[22:1];
    assign V_fx = (V[31])? (23'd0 - {1'b0, v_mag}) : {1'b0, v_mag};

    assign w_e = out_weight[30:23];
    assign w_m = {(w_e != 8'd0), out_weight[22:0]};
    assign w_sa = 8'd127 - w_e;
    assign w_sh = w_m >> w_sa;
    assign w_rd = {1'b0, w_sh} + 25'd1;
    assign w_mag = ((w_e == 8'd0) || (w_e > 8'd126) || (w_sa > 8'd23))? 22'd0 : w_rd[22:1];
    assign W_fx = (out_weight[31])? (23'd0 - {1'b0, w_mag}) : {1'b0, w_mag};

    //=============================================================
    //                       Head Switcher
    //=============================================================
    // in_cnt[1] = head, {in_cnt[2], in_cnt[0]} = lane, in_cnt[5:3] = block (filled by shifting)
    assign H1_wen[0] = (in_valid) && (!in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd0);
    assign H1_wen[1] = (in_valid) && (!in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd1);
    assign H1_wen[2] = (in_valid) && (!in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd2);
    assign H1_wen[3] = (in_valid) && (!in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd3);
    assign H2_wen[0] = (in_valid) && (in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd0);
    assign H2_wen[1] = (in_valid) && (in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd1);
    assign H2_wen[2] = (in_valid) && (in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd2);
    assign H2_wen[3] = (in_valid) && (in_cnt[1]) && ({in_cnt[2], in_cnt[0]} == 2'd3);

    // out_weight is valid only in the first 16 cycles, in_cnt[1:0] = column c = lane
    assign W_wen[0] = (in_valid) && (in_cnt[5:4] == 2'd0) && (in_cnt[1:0] == 2'd0);
    assign W_wen[1] = (in_valid) && (in_cnt[5:4] == 2'd0) && (in_cnt[1:0] == 2'd1);
    assign W_wen[2] = (in_valid) && (in_cnt[5:4] == 2'd0) && (in_cnt[1:0] == 2'd2);
    assign W_wen[3] = (in_valid) && (in_cnt[5:4] == 2'd0) && (in_cnt[1:0] == 2'd3);

    //=============================================================
    //                        K Ring Buffer
    //=============================================================
    // loading : the new word enters the lane tail and the lane shifts toward the head
    // rotation: all 4 lanes of both heads shift toward the head, the head block wraps to the tail
    // (never at the same time: kv_rot only in Q_block 1 ~ 7, after in_valid falls)
    always @(posedge clk) begin
        for(i = 0; i < 4; i = i + 1) begin
            if(kv_rot) begin
                for(b = 0; b < 7; b = b + 1) begin
                    H1_K_Buf[i][b] <= H1_K_Buf[i][b+1];
                    H2_K_Buf[i][b] <= H2_K_Buf[i][b+1];
                end
                H1_K_Buf[i][7] <= H1_K_Buf[i][0];
                H2_K_Buf[i][7] <= H2_K_Buf[i][0];
            end
            else if(H1_wen[i]) begin
                for(b = 0; b < 7; b = b + 1) H1_K_Buf[i][b] <= H1_K_Buf[i][b+1];
                H1_K_Buf[i][7] <= K_fx;
            end
            else if(H2_wen[i]) begin
                for(b = 0; b < 7; b = b + 1) H2_K_Buf[i][b] <= H2_K_Buf[i][b+1];
                H2_K_Buf[i][7] <= K_fx;
            end
        end
    end

    //=============================================================
    //                 V Ring Buffer (2 cycles late)
    //=============================================================
    // the same writes, rotations and tail / head select as K, delayed by 2 cycles (S1 -> S3)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            H1_wen_d1 <= 4'd0;
            H1_wen_d2 <= 4'd0;
            H2_wen_d1 <= 4'd0;
            H2_wen_d2 <= 4'd0;
            v_rot_d1 <= 1'b0;
            v_rot_d2 <= 1'b0;
            v_tail_d1 <= 1'b0;
            v_tail_d2 <= 1'b0;
        end
        else begin
            H1_wen_d1 <= H1_wen;
            H1_wen_d2 <= H1_wen_d1;
            H2_wen_d1 <= H2_wen;
            H2_wen_d2 <= H2_wen_d1;
            v_rot_d1 <= kv_rot;
            v_rot_d2 <= v_rot_d1;
            v_tail_d1 <= kv_tail_sel;
            v_tail_d2 <= v_tail_d1;
        end
    end

    always @(posedge clk) begin
        V_fx_d1 <= V_fx;
        V_fx_d2 <= V_fx_d1;
    end

    always @(posedge clk) begin
        for(i = 0; i < 4; i = i + 1) begin
            if(v_rot_d2) begin
                for(b = 0; b < 7; b = b + 1) begin
                    H1_V_Buf[i][b] <= H1_V_Buf[i][b+1];
                    H2_V_Buf[i][b] <= H2_V_Buf[i][b+1];
                end
                H1_V_Buf[i][7] <= H1_V_Buf[i][0];
                H2_V_Buf[i][7] <= H2_V_Buf[i][0];
            end
            else if(H1_wen_d2[i]) begin
                for(b = 0; b < 7; b = b + 1) H1_V_Buf[i][b] <= H1_V_Buf[i][b+1];
                H1_V_Buf[i][7] <= V_fx_d2;
            end
            else if(H2_wen_d2[i]) begin
                for(b = 0; b < 7; b = b + 1) H2_V_Buf[i][b] <= H2_V_Buf[i][b+1];
                H2_V_Buf[i][7] <= V_fx_d2;
            end
        end
    end

    //=============================================================
    //                         Q Buffer
    //=============================================================
    // loading : Q_block 0 (in_cnt[5:3] == 0) goes straight into Cur, Q_block 1 ~ 7 shift into Buf
    // q_adv   : Cur <- Buf head, Buf shifts toward the head (the tail keeps a don't care value)
    always @(posedge clk) begin
        for(i = 0; i < 4; i = i + 1) begin
            if(q_adv) begin
                H1_Q_Cur[i] <= H1_Q_Buf[i][0];
                H2_Q_Cur[i] <= H2_Q_Buf[i][0];
                for(b = 0; b < 6; b = b + 1) begin
                    H1_Q_Buf[i][b] <= H1_Q_Buf[i][b+1];
                    H2_Q_Buf[i][b] <= H2_Q_Buf[i][b+1];
                end
            end
            else if(H1_wen[i]) begin
                if(in_cnt[5:3] == 3'd0) H1_Q_Cur[i] <= Q_fx;
                else begin
                    for(b = 0; b < 6; b = b + 1) H1_Q_Buf[i][b] <= H1_Q_Buf[i][b+1];
                    H1_Q_Buf[i][6] <= Q_fx;
                end
            end
            else if(H2_wen[i]) begin
                if(in_cnt[5:3] == 3'd0) H2_Q_Cur[i] <= Q_fx;
                else begin
                    for(b = 0; b < 6; b = b + 1) H2_Q_Buf[i][b] <= H2_Q_Buf[i][b+1];
                    H2_Q_Buf[i][6] <= Q_fx;
                end
            end
        end
    end

    //=============================================================
    //                         Read Port
    //=============================================================
    // lane 0 ~ 3 = a0, a1, b0, b1 ; K/V tail (entry 7) for Q_block 0, head (entry 0) otherwise
    assign H1_Qa0 = H1_Q_Cur[0];
    assign H1_Qa1 = H1_Q_Cur[1];
    assign H1_Qb0 = H1_Q_Cur[2];
    assign H1_Qb1 = H1_Q_Cur[3];
    assign H2_Qa0 = H2_Q_Cur[0];
    assign H2_Qa1 = H2_Q_Cur[1];
    assign H2_Qb0 = H2_Q_Cur[2];
    assign H2_Qb1 = H2_Q_Cur[3];

    assign H1_Ka0 = (kv_tail_sel)? H1_K_Buf[0][7] : H1_K_Buf[0][0];
    assign H1_Ka1 = (kv_tail_sel)? H1_K_Buf[1][7] : H1_K_Buf[1][0];
    assign H1_Kb0 = (kv_tail_sel)? H1_K_Buf[2][7] : H1_K_Buf[2][0];
    assign H1_Kb1 = (kv_tail_sel)? H1_K_Buf[3][7] : H1_K_Buf[3][0];
    assign H2_Ka0 = (kv_tail_sel)? H2_K_Buf[0][7] : H2_K_Buf[0][0];
    assign H2_Ka1 = (kv_tail_sel)? H2_K_Buf[1][7] : H2_K_Buf[1][0];
    assign H2_Kb0 = (kv_tail_sel)? H2_K_Buf[2][7] : H2_K_Buf[2][0];
    assign H2_Kb1 = (kv_tail_sel)? H2_K_Buf[3][7] : H2_K_Buf[3][0];

    assign H1_Va0 = (v_tail_d2)? H1_V_Buf[0][7] : H1_V_Buf[0][0];
    assign H1_Va1 = (v_tail_d2)? H1_V_Buf[1][7] : H1_V_Buf[1][0];
    assign H1_Vb0 = (v_tail_d2)? H1_V_Buf[2][7] : H1_V_Buf[2][0];
    assign H1_Vb1 = (v_tail_d2)? H1_V_Buf[3][7] : H1_V_Buf[3][0];
    assign H2_Va0 = (v_tail_d2)? H2_V_Buf[0][7] : H2_V_Buf[0][0];
    assign H2_Va1 = (v_tail_d2)? H2_V_Buf[1][7] : H2_V_Buf[1][0];
    assign H2_Vb0 = (v_tail_d2)? H2_V_Buf[2][7] : H2_V_Buf[2][0];
    assign H2_Vb1 = (v_tail_d2)? H2_V_Buf[3][7] : H2_V_Buf[3][0];

    //=============================================================
    //                Processing Engine (one per head)
    //=============================================================
    ATTN_PE u_pe_h1 (
        .clk(clk),
        .rst_n(rst_n),
        .issue(issue),
        .tile_first(tile_first),
        .tile_last(tile_last),
        .Qa0(H1_Qa0),
        .Qa1(H1_Qa1),
        .Qb0(H1_Qb0),
        .Qb1(H1_Qb1),
        .Ka0(H1_Ka0),
        .Ka1(H1_Ka1),
        .Kb0(H1_Kb0),
        .Kb1(H1_Kb1),
        .Va0(H1_Va0),
        .Va1(H1_Va1),
        .Vb0(H1_Vb0),
        .Vb1(H1_Vb1),
        .Ha0(H1_Ha0),
        .Ha1(H1_Ha1),
        .Hb0(H1_Hb0),
        .Hb1(H1_Hb1),
        .h_a_ready(h_a_ready)
    );

    ATTN_PE u_pe_h2 (
        .clk(clk),
        .rst_n(rst_n),
        .issue(issue),
        .tile_first(tile_first),
        .tile_last(tile_last),
        .Qa0(H2_Qa0),
        .Qa1(H2_Qa1),
        .Qb0(H2_Qb0),
        .Qb1(H2_Qb1),
        .Ka0(H2_Ka0),
        .Ka1(H2_Ka1),
        .Kb0(H2_Kb0),
        .Kb1(H2_Kb1),
        .Va0(H2_Va0),
        .Va1(H2_Va1),
        .Vb0(H2_Vb0),
        .Vb1(H2_Vb1),
        .Ha0(H2_Ha0),
        .Ha1(H2_Ha1),
        .Hb0(H2_Hb0),
        .Hb1(H2_Hb1),
        .h_a_ready()
    );

    //=============================================================
    //                         W Buffer
    //=============================================================
    // loading : out_weight enters the lane tail (first 16 cycles only)
    // output  : the 4 lanes rotate one row per output cycle, the head column is W[k][0..3]
    always @(posedge clk) begin
        for(i = 0; i < 4; i = i + 1) begin
            if(out_active) begin
                for(b = 0; b < 3; b = b + 1) W_Buf[i][b] <= W_Buf[i][b+1];
                W_Buf[i][3] <= W_Buf[i][0];
            end
            else if(W_wen[i]) begin
                for(b = 0; b < 3; b = b + 1) W_Buf[i][b] <= W_Buf[i][b+1];
                W_Buf[i][3] <= W_fx;
            end
        end
    end

    //=============================================================
    //                       Output Control
    //=============================================================
    // a Q_block gives 8 outputs every 8 cycles, so once the first token a is ready the 64
    // outputs stream without a gap: out_cnt[2] = token a / b, out_cnt[1:0] = dim k (W row)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) out_active <= 1'b0;
        else if(h_a_ready && !out_active) out_active <= 1'b1;
        else if(out_cnt == 6'd63) out_active <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) out_cnt <= 6'd0;
        else if(out_active) out_cnt <= out_cnt + 6'd1;
    end

    //=============================================================
    //                    Linear : H . W[k]
    //=============================================================
    // Final[t][k] = H1[t][0] * W[k][0] + H1[t][1] * W[k][1] + H2[t][0] * W[k][2] + H2[t][1] * W[k][3]
    assign H1_x0 = (out_cnt[2])? H1_Hb0 : H1_Ha0;
    assign H1_x1 = (out_cnt[2])? H1_Hb1 : H1_Ha1;
    assign H2_x0 = (out_cnt[2])? H2_Hb0 : H2_Ha0;
    assign H2_x1 = (out_cnt[2])? H2_Hb1 : H2_Ha1;

    // H = {sign, magnitude} is used as one's complement y = sign ? ~mag : mag (= -mag - 1),
    // and the missing +1 * W is added back, so the dot product stays one signed sum
    assign H1_y0 = {H1_x0[22], H1_x0[21:0] ^ {22{H1_x0[22]}}};
    assign H1_y1 = {H1_x1[22], H1_x1[21:0] ^ {22{H1_x1[22]}}};
    assign H2_y0 = {H2_x0[22], H2_x0[21:0] ^ {22{H2_x0[22]}}};
    assign H2_y1 = {H2_x1[22], H2_x1[21:0] ^ {22{H2_x1[22]}}};

    assign Wk0 = W_Buf[0][0];
    assign Wk1 = W_Buf[1][0];
    assign Wk2 = W_Buf[2][0];
    assign Wk3 = W_Buf[3][0];

    assign wc0 = (H1_x0[22])? Wk0 : 23'sd0;
    assign wc1 = (H1_x1[22])? Wk1 : 23'sd0;
    assign wc2 = (H2_x0[22])? Wk2 : 23'sd0;
    assign wc3 = (H2_x1[22])? Wk3 : 23'sd0;

    // H (22-bit magnitude, 23 fraction bits) * W (22 fraction bits) -> 45 fraction bits
    assign facc = H1_y0 * Wk0 + H1_y1 * Wk1 + H2_y0 * Wk2 + H2_y1 * Wk3 + wc0 + wc1 + wc2 + wc3;

    //=============================================================
    //                   Fixed -> fp32 (truncate)
    //=============================================================
    // |F| by one's complement (|F| - 1 for a negative F, 2^-45 off) and a truncated mantissa:
    // both keep adders off the output path, the extra error is below 1e-7
    // normalize the magnitude so the leading one sits at bit 45, f_lz = number of left shifts
    assign f_sign = facc[47];
    assign f_mag = (f_sign)? ~facc[45:0] : facc[45:0];

    assign nz0 = (f_mag[45:14] == 32'd0)? {f_mag[13:0], 32'd0} : f_mag;
    assign nz1 = (nz0[45:30] == 16'd0)? {nz0[29:0], 16'd0} : nz0;
    assign nz2 = (nz1[45:38] == 8'd0)? {nz1[37:0], 8'd0} : nz1;
    assign nz3 = (nz2[45:42] == 4'd0)? {nz2[41:0], 4'd0} : nz2;
    assign nz4 = (nz3[45:44] == 2'd0)? {nz3[43:0], 2'd0} : nz3;
    assign nz5 = (!nz4[45])? {nz4[44:0], 1'b0} : nz4;
    assign f_lz = {(f_mag[45:14] == 32'd0), (nz0[45:30] == 16'd0), (nz1[45:38] == 8'd0),
                   (nz2[45:42] == 4'd0), (nz3[45:44] == 2'd0), (!nz4[45])};

    // value = mag * 2^-45, leading one at 45 - f_lz -> exponent field = 127 - f_lz
    assign f_exp = 8'd127 - {2'b00, f_lz};
    assign final_res = (f_mag == 46'd0)? 32'd0 : {f_sign, f_exp, nz5[44:22]};

    //=============================================================
    //                       Output Register
    //=============================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_valid <= 1'b0;
            out <= 32'd0;
        end
        else begin
            out_valid <= out_active;
            out <= (out_active)? final_res : 32'd0;
        end
    end

endmodule


/******************************************************************************
* ATTN_PE : datapath of one head
*   S1 : t = Q' . K (20 fraction bits, = exponent of 2 of the scaled score)
*   S2 : integer running max r = max(ceil t), weight = 2^frac(t) >> (r - floor t)
*   S3 : D = (D >> dl) + w0 + w1, M = (M >> dl) + w0 * Va + w1 * Vb, dl = r_new - r_old
*        (the softmax correction e^(m_old - m_new) becomes a shift because r is an integer)
*   Out: snapshot {sign, |M|} / D -> one SRT divider, 4 divisions -> H registers
* V arrives already aligned with S3 (the V buffer runs 2 cycles behind K)
* Register naming: sN_* is the register feeding stage N
******************************************************************************/
module ATTN_PE (
    input wire clk,
    input wire rst_n,
    input wire issue,
    input wire tile_first,
    input wire tile_last,
    input wire [26:0] Qa0,
    input wire [26:0] Qa1,
    input wire [26:0] Qb0,
    input wire [26:0] Qb1,
    input wire [25:0] Ka0,
    input wire [25:0] Ka1,
    input wire [25:0] Kb0,
    input wire [25:0] Kb1,
    input wire [22:0] Va0,
    input wire [22:0] Va1,
    input wire [22:0] Vb0,
    input wire [22:0] Vb1,
    output wire [22:0] Ha0,
    output wire [22:0] Ha1,
    output wire [22:0] Hb0,
    output wire [22:0] Hb1,
    output wire h_a_ready
);

    // S1 : Sxy = row x of Q against key y of K (y = 0 : key a, y = 1 : key b)
    wire signed [26:0] qa0, qa1, qb0, qb1;
    wire signed [25:0] ka0, ka1, kb0, kb1;
    wire signed [52:0] ta0, ta1, tb0, tb1;

    // S1 -> S2 register
    reg s2_valid, s2_first, s2_last;
    reg [29:0] s2_Sa0, s2_Sa1, s2_Sb0, s2_Sb1;

    // S2
    reg [9:0] r_a, r_b;                         // integer running max of row a / b
    wire [9:0] fla0, fla1, flb0, flb1;          // floor(t)
    wire [9:0] cea0, cea1, ceb0, ceb1;          // ceil(t)
    wire [9:0] cm_a, cm_b;                      // ceil of the tile rowmax
    wire [9:0] r_a_nxt, r_b_nxt;
    wire [10:0] da0, da1, db0, db1, dla, dlb;
    wire [4:0] sa0, sa1, sb0, sb1, dla_s, dlb_s;
    wire [24:0] Pa0, Pa1, Pb0, Pb1;             // 2^frac(t), 24 fraction bits

    // S2 -> S3 register
    reg s3_valid, s3_first, s3_last;
    reg [24:0] s3_wa0, s3_wa1, s3_wb0, s3_wb1;
    reg [4:0] s3_dla, s3_dlb;

    // S3
    reg [28:0] Da, Db;                          // 24 fraction bits, (0.5, 16]
    reg [29:0] Ma0, Ma1, Mb0, Mb1;              // signed, 25 fraction bits
    wire [28:0] Da_nxt, Db_nxt;
    wire signed [25:0] wa0, wa1, wb0, wb1;          // weights as positive signed numbers
    wire signed [22:0] va0s, va1s, vb0s, vb1s;
    wire signed [48:0] va0, va1, vb0, vb1;
    wire [29:0] pva0, pva1, pvb0, pvb1;
    wire signed [29:0] Ma0_sh, Ma1_sh, Mb0_sh, Mb1_sh;  // own signed assignment: >>> stays arithmetic
    wire [29:0] Ma0_nxt, Ma1_nxt, Mb0_nxt, Mb1_nxt;
    wire [28:0] Ma0_abs, Ma1_abs, Mb0_abs, Mb1_abs;
    wire snap_en;

    // snapshot -> divider -> H
    reg [29:0] M_snap0, M_snap1, M_snap2, M_snap3;  // {sign, |M|}, shift toward 0: Ma0, Ma1, Mb0, Mb1
    reg [28:0] D_snap0, D_snap1;                    // shift toward 0: Da, Db
    reg [3:0] div_step;                             // one-hot: division k in progress
    wire [21:0] hmag;                               // saturated to 22 bits (|H| = 0.5 only in theory)
    reg [22:0] H_a0, H_a1, H_b0, H_b1;              // {sign, 22-bit magnitude}


    //=============================================================
    //                       S1 : Q' . K
    //=============================================================
    assign qa0 = Qa0;
    assign qa1 = Qa1;
    assign qb0 = Qb0;
    assign qb1 = Qb1;
    assign ka0 = Ka0;
    assign ka1 = Ka1;
    assign kb0 = Kb0;
    assign kb1 = Kb1;

    // Q' is one's complement: q' * k = q * k + (sign ? k : 0), the whole score is one signed
    // sum of products (43 fraction bits) + 2^22, keep 20 fraction bits (round half up)
    assign ta0 = qa0 * ka0 + qa1 * ka1 + ((Qa0[26])? ka0 : 26'sd0) + ((Qa1[26])? ka1 : 26'sd0) + 53'sd4194304;
    assign ta1 = qa0 * kb0 + qa1 * kb1 + ((Qa0[26])? kb0 : 26'sd0) + ((Qa1[26])? kb1 : 26'sd0) + 53'sd4194304;
    assign tb0 = qb0 * ka0 + qb1 * ka1 + ((Qb0[26])? ka0 : 26'sd0) + ((Qb1[26])? ka1 : 26'sd0) + 53'sd4194304;
    assign tb1 = qb0 * kb0 + qb1 * kb1 + ((Qb0[26])? kb0 : 26'sd0) + ((Qb1[26])? kb1 : 26'sd0) + 53'sd4194304;

    //=============================================================
    //                    S1 -> S2 Register
    //=============================================================
    // valid marks a real tile (Q_block 0 tiles are 8 cycles apart), first / last follow the tile
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            s2_valid <= 1'b0;
            s2_first <= 1'b0;
            s2_last <= 1'b0;
        end
        else begin
            s2_valid <= issue;
            s2_first <= tile_first;
            s2_last <= tile_last;
        end
    end

    always @(posedge clk) begin
        s2_Sa0 <= ta0[52:23];
        s2_Sa1 <= ta1[52:23];
        s2_Sb0 <= tb0[52:23];
        s2_Sb1 <= tb1[52:23];
    end

    //=============================================================
    //                  S2 : Integer Running Max
    //=============================================================
    // t = floor + frac (two's complement), ceil = floor + (frac != 0)
    assign fla0 = s2_Sa0[29:20];
    assign fla1 = s2_Sa1[29:20];
    assign flb0 = s2_Sb0[29:20];
    assign flb1 = s2_Sb1[29:20];
    assign cea0 = fla0 + {9'd0, (s2_Sa0[19:0] != 20'd0)};
    assign cea1 = fla1 + {9'd0, (s2_Sa1[19:0] != 20'd0)};
    assign ceb0 = flb0 + {9'd0, (s2_Sb0[19:0] != 20'd0)};
    assign ceb1 = flb1 + {9'd0, (s2_Sb1[19:0] != 20'd0)};

    assign cm_a = ($signed(cea0) > $signed(cea1))? cea0 : cea1;
    assign cm_b = ($signed(ceb0) > $signed(ceb1))? ceb0 : ceb1;

    // the first tile of a Q_block has no old r
    assign r_a_nxt = (s2_first || ($signed(cm_a) > $signed(r_a)))? cm_a : r_a;
    assign r_b_nxt = (s2_first || ($signed(cm_b) > $signed(r_b)))? cm_b : r_b;

    // r feedback stays inside S2: the next tile in S2 sees the updated r
    always @(posedge clk) begin
        if(s2_valid) begin
            r_a <= r_a_nxt;
            r_b <= r_b_nxt;
        end
    end

    // shift amounts (>= 0), saturated to 31 (a weight shifted by >= 25 is 0 anyway)
    assign da0 = {r_a_nxt[9], r_a_nxt} - {fla0[9], fla0};
    assign da1 = {r_a_nxt[9], r_a_nxt} - {fla1[9], fla1};
    assign db0 = {r_b_nxt[9], r_b_nxt} - {flb0[9], flb0};
    assign db1 = {r_b_nxt[9], r_b_nxt} - {flb1[9], flb1};
    assign dla = {r_a_nxt[9], r_a_nxt} - {r_a[9], r_a};
    assign dlb = {r_b_nxt[9], r_b_nxt} - {r_b[9], r_b};

    assign sa0 = (da0[10:5] != 6'd0)? 5'd31 : da0[4:0];
    assign sa1 = (da1[10:5] != 6'd0)? 5'd31 : da1[4:0];
    assign sb0 = (db0[10:5] != 6'd0)? 5'd31 : db0[4:0];
    assign sb1 = (db1[10:5] != 6'd0)? 5'd31 : db1[4:0];
    assign dla_s = (dla[10:5] != 6'd0)? 5'd31 : dla[4:0];
    assign dlb_s = (dlb[10:5] != 6'd0)? 5'd31 : dlb[4:0];

    //=============================================================
    //                     S2 : Weight = 2^(t - r)
    //=============================================================
    ATTN_POW2 u_s2_pow_a0 (
        .fr(s2_Sa0[19:0]),
        .p(Pa0)
    );

    ATTN_POW2 u_s2_pow_a1 (
        .fr(s2_Sa1[19:0]),
        .p(Pa1)
    );

    ATTN_POW2 u_s2_pow_b0 (
        .fr(s2_Sb0[19:0]),
        .p(Pb0)
    );

    ATTN_POW2 u_s2_pow_b1 (
        .fr(s2_Sb1[19:0]),
        .p(Pb1)
    );

    //=============================================================
    //                    S2 -> S3 Register
    //=============================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            s3_valid <= 1'b0;
            s3_first <= 1'b0;
            s3_last <= 1'b0;
        end
        else begin
            s3_valid <= s2_valid;
            s3_first <= s2_first;
            s3_last <= s2_last;
        end
    end

    always @(posedge clk) begin
        s3_wa0 <= Pa0 >> sa0;
        s3_wa1 <= Pa1 >> sa1;
        s3_wb0 <= Pb0 >> sb0;
        s3_wb1 <= Pb1 >> sb1;
        s3_dla <= dla_s;
        s3_dlb <= dlb_s;
    end

    //=============================================================
    //                  S3 : Denominator (row a / b)
    //=============================================================
    // D = (D >> dl) + w0 + w1 ; first tile: D = w0 + w1
    assign Da_nxt = (s3_first)? ({4'd0, s3_wa0} + {4'd0, s3_wa1}) : ((Da >> s3_dla) + {4'd0, s3_wa0} + {4'd0, s3_wa1});
    assign Db_nxt = (s3_first)? ({4'd0, s3_wb0} + {4'd0, s3_wb1}) : ((Db >> s3_dlb) + {4'd0, s3_wb0} + {4'd0, s3_wb1});

    //=============================================================
    //                     S3 : Numerator
    //=============================================================
    // weight (24 fraction bits) * V (22 fraction bits) -> 46 fraction bits, + 2^20, keep 25 (round)
    assign wa0 = {1'b0, s3_wa0};
    assign wa1 = {1'b0, s3_wa1};
    assign wb0 = {1'b0, s3_wb0};
    assign wb1 = {1'b0, s3_wb1};
    assign va0s = Va0;
    assign va1s = Va1;
    assign vb0s = Vb0;
    assign vb1s = Vb1;

    assign va0 = wa0 * va0s + wa1 * vb0s + 49'sd1048576;
    assign va1 = wa0 * va1s + wa1 * vb1s + 49'sd1048576;
    assign vb0 = wb0 * va0s + wb1 * vb0s + 49'sd1048576;
    assign vb1 = wb0 * va1s + wb1 * vb1s + 49'sd1048576;

    assign pva0 = {{2{va0[48]}}, va0[48:21]};
    assign pva1 = {{2{va1[48]}}, va1[48:21]};
    assign pvb0 = {{2{vb0[48]}}, vb0[48:21]};
    assign pvb1 = {{2{vb1[48]}}, vb1[48:21]};

    // M = (M >>> dl) + pv ; first tile: M = pv
    // the shift has its own signed assignment: inside "... + pva0" (unsigned) the whole
    // expression would be unsigned and >>> would fall back to a logical shift
    assign Ma0_sh = $signed(Ma0) >>> s3_dla;
    assign Ma1_sh = $signed(Ma1) >>> s3_dla;
    assign Mb0_sh = $signed(Mb0) >>> s3_dlb;
    assign Mb1_sh = $signed(Mb1) >>> s3_dlb;

    assign Ma0_nxt = (s3_first)? pva0 : (Ma0_sh + pva0);
    assign Ma1_nxt = (s3_first)? pva1 : (Ma1_sh + pva1);
    assign Mb0_nxt = (s3_first)? pvb0 : (Mb0_sh + pvb0);
    assign Mb1_nxt = (s3_first)? pvb1 : (Mb1_sh + pvb1);

    //=============================================================
    //                    S3 : D / M Register
    //=============================================================
    // D / M feedback stays inside S3: the next tile in S3 sees the updated D / M
    always @(posedge clk) begin
        if(s3_valid) begin
            Da <= Da_nxt;
            Db <= Db_nxt;
            Ma0 <= Ma0_nxt;
            Ma1 <= Ma1_nxt;
            Mb0 <= Mb0_nxt;
            Mb1 <= Mb1_nxt;
        end
    end

    //=============================================================
    //                    Snapshot -> Divider
    //=============================================================
    // the final D / M of a Q_block are taken from the S3 result of its last tile, because
    // the next Q_block overwrites D / M right after. The snapshot shifts toward entry 0
    // so the divider always reads a fixed register (no mux in front of the divider):
    //   step 0: Ma0 / Da   step 1: Ma1 / Da   step 2: Mb0 / Db   step 3: Mb1 / Db
    // |M| is taken here (S3 has slack) instead of in front of the divider
    assign snap_en = (s3_valid) && (s3_last);

    assign Ma0_abs = (Ma0_nxt[29])? (29'd0 - Ma0_nxt[28:0]) : Ma0_nxt[28:0];
    assign Ma1_abs = (Ma1_nxt[29])? (29'd0 - Ma1_nxt[28:0]) : Ma1_nxt[28:0];
    assign Mb0_abs = (Mb0_nxt[29])? (29'd0 - Mb0_nxt[28:0]) : Mb0_nxt[28:0];
    assign Mb1_abs = (Mb1_nxt[29])? (29'd0 - Mb1_nxt[28:0]) : Mb1_nxt[28:0];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) div_step <= 4'd0;
        else if(snap_en) div_step <= 4'b0001;
        else div_step <= {div_step[2:0], 1'b0};
    end

    always @(posedge clk) begin
        if(snap_en) begin
            M_snap0 <= {Ma0_nxt[29], Ma0_abs};
            M_snap1 <= {Ma1_nxt[29], Ma1_abs};
            M_snap2 <= {Mb0_nxt[29], Mb0_abs};
            M_snap3 <= {Mb1_nxt[29], Mb1_abs};
            D_snap0 <= Da_nxt;
            D_snap1 <= Db_nxt;
        end
        else begin
            if(div_step != 4'd0) begin
                M_snap0 <= M_snap1;
                M_snap1 <= M_snap2;
                M_snap2 <= M_snap3;
            end
            if(div_step[1]) D_snap0 <= D_snap1;
        end
    end

    // H = M / D (sign-magnitude), quotient magnitude <= 2^22, saturated to 22 bits
    ATTN_DIV_SRT #(.OVL(0)) u_div (
        .num(M_snap0[28:0]),
        .den(D_snap0),
        .quo(hmag)
    );

    //=============================================================
    //                        H Register
    //=============================================================
    // written by enable instead of shifting: token a is read by the output for 4 cycles
    // while the next Q_block may already start dividing, so its value must not move
    always @(posedge clk) begin
        if(div_step[0]) H_a0 <= {M_snap0[29], hmag};
        if(div_step[1]) H_a1 <= {M_snap0[29], hmag};
        if(div_step[2]) H_b0 <= {M_snap0[29], hmag};
        if(div_step[3]) H_b1 <= {M_snap0[29], hmag};
    end

    assign Ha0 = H_a0;
    assign Ha1 = H_a1;
    assign Hb0 = H_b0;
    assign Hb1 = H_b1;

    // H_a1 is written at the end of step 1, token a can be output from the next cycle
    assign h_a_ready = div_step[1];

endmodule


/******************************************************************************
* ATTN_POW2 : p = 2^f, f = fr / 2^20 in [0, 1), p has 24 fraction bits ([2^24, 2^25))
*   2^f = T[f_hi] * (1 + a1 x + a2 x^2), f_hi = top 6 bits, x = low 14 bits (< 2^-6)
*   a1 / a2 fitted on [0, 2^-6) (absorbs the cubic term), +1 centers the truncation error
*   error within about +-6 LSB of 2^-24 over all 2^20 inputs
******************************************************************************/
module ATTN_POW2 (
    input wire [19:0] fr,
    output wire [24:0] p
);

    reg [24:0] tab;
    wire [13:0] x;
    wire [32:0] lin_full;
    wire [8:0] xq;
    wire [17:0] xq2;
    wire [23:0] quad_full;
    wire [18:0] e;
    wire [35:0] te;

    assign x = fr[13:0];
    assign lin_full = x * 19'd363406;           // a1 * 2^19
    assign xq = x[13:5];
    assign xq2 = xq * xq;
    assign quad_full = xq2 * 6'd62;             // a2 * 2^8
    assign e = lin_full[32:14] + {8'd0, quad_full[23:13]};   // 2^x - 1, 25 fraction bits
    assign te = tab[24:8] * e;
    assign p = tab + {6'd0, te[35:17]} + 25'd1;

    always @(*) begin
        case(fr[19:14])
            6'd0: tab = 25'h1000000;
            6'd1: tab = 25'h102C9A4;
            6'd2: tab = 25'h1059B0D;
            6'd3: tab = 25'h1087452;
            6'd4: tab = 25'h10B5587;
            6'd5: tab = 25'h10E3EC3;
            6'd6: tab = 25'h111301D;
            6'd7: tab = 25'h11429AB;
            6'd8: tab = 25'h1172B84;
            6'd9: tab = 25'h11A35BF;
            6'd10: tab = 25'h11D4873;
            6'd11: tab = 25'h12063B9;
            6'd12: tab = 25'h12387A7;
            6'd13: tab = 25'h126B456;
            6'd14: tab = 25'h129E9DF;
            6'd15: tab = 25'h12D285A;
            6'd16: tab = 25'h1306FE1;
            6'd17: tab = 25'h133C08B;
            6'd18: tab = 25'h1371A73;
            6'd19: tab = 25'h13A7DB3;
            6'd20: tab = 25'h13DEA65;
            6'd21: tab = 25'h14160A2;
            6'd22: tab = 25'h144E086;
            6'd23: tab = 25'h1486A2B;
            6'd24: tab = 25'h14BFDAD;
            6'd25: tab = 25'h14F9B27;
            6'd26: tab = 25'h15342B5;
            6'd27: tab = 25'h156F473;
            6'd28: tab = 25'h15AB07E;
            6'd29: tab = 25'h15E76F1;
            6'd30: tab = 25'h16247EB;
            6'd31: tab = 25'h1662388;
            6'd32: tab = 25'h16A09E6;
            6'd33: tab = 25'h16DFB24;
            6'd34: tab = 25'h171F75F;
            6'd35: tab = 25'h175FEB5;
            6'd36: tab = 25'h17A1147;
            6'd37: tab = 25'h17E2F33;
            6'd38: tab = 25'h182589A;
            6'd39: tab = 25'h1868D9A;
            6'd40: tab = 25'h18ACE54;
            6'd41: tab = 25'h18F1AEA;
            6'd42: tab = 25'h193737B;
            6'd43: tab = 25'h197D82A;
            6'd44: tab = 25'h19C4918;
            6'd45: tab = 25'h1A0C668;
            6'd46: tab = 25'h1A5503B;
            6'd47: tab = 25'h1A9E6B5;
            6'd48: tab = 25'h1AE89FA;
            6'd49: tab = 25'h1B33A2C;
            6'd50: tab = 25'h1B7F76F;
            6'd51: tab = 25'h1BCC1E9;
            6'd52: tab = 25'h1C199BE;
            6'd53: tab = 25'h1C67F13;
            6'd54: tab = 25'h1CB720E;
            6'd55: tab = 25'h1D072D5;
            6'd56: tab = 25'h1D5818E;
            6'd57: tab = 25'h1DA9E60;
            6'd58: tab = 25'h1DFC973;
            6'd59: tab = 25'h1E502EE;
            6'd60: tab = 25'h1EA4AFA;
            6'd61: tab = 25'h1EFA1BF;
            6'd62: tab = 25'h1F50766;
            6'd63: tab = 25'h1FA7C18;
            default: tab = 25'h1000000;
        endcase
    end

endmodule


/******************************************************************************
* ATTN_DIV_SRT : quo = floor((num << 22) / den), saturated to 22 bits (num >= den)
*   radix-2 SRT, partial remainder in carry-save form, digit q in {-1, 0, +1}
*   den in [2^23, 2^29) is normalized to bit 28 (shift 0 ~ 5, num shifted the same)
*   q from a 4-bit estimate of 2W: >= 0 -> +1, -1/2 -> 0, <= -1 -> -1 (|W| < den kept)
*   floor: quo = P - N - (final remainder < 0)
*   OVL = 1: the digit of step g+1 is precomputed for the 3 possible digits of step g
*            and picked by a mux (the digit chain only sees one mux per step)
******************************************************************************/
module ATTN_DIV_SRT #(
    parameter OVL = 1
)(
    input wire [28:0] num,
    input wire [28:0] den,
    output wire [21:0] quo
);

    wire sat;
    wire [5:0] lead;                // one-hot: den[28 - k] is the leading one
    wire [28:0] dn, nn;             // normalized den / num
    wire [31:0] dpos, dneg;         // + dn and ~dn (-dn = ~dn + 1, the +1 enters the carry LSB)
    wire [30:0] ws [0:22];          // partial remainder W_g = ws + wc (mod 2^31)
    wire [30:0] wc [0:22];
    wire [21:0] qp, qz, qn;         // one-hot digit of step g
    wire [21:0] P, N;
    wire [30:0] wsum;
    genvar g;

    assign sat = (num >= den);

    assign lead[0] = den[28];
    assign lead[1] = (den[28] == 1'b0) && den[27];
    assign lead[2] = (den[28:27] == 2'd0) && den[26];
    assign lead[3] = (den[28:26] == 3'd0) && den[25];
    assign lead[4] = (den[28:25] == 4'd0) && den[24];
    assign lead[5] = (den[28:24] == 5'd0);

    assign dn = ({29{lead[0]}} & den) | ({29{lead[1]}} & {den[27:0], 1'd0}) | ({29{lead[2]}} & {den[26:0], 2'd0})
              | ({29{lead[3]}} & {den[25:0], 3'd0}) | ({29{lead[4]}} & {den[24:0], 4'd0}) | ({29{lead[5]}} & {den[23:0], 5'd0});
    assign nn = ({29{lead[0]}} & num) | ({29{lead[1]}} & {num[27:0], 1'd0}) | ({29{lead[2]}} & {num[26:0], 2'd0})
              | ({29{lead[3]}} & {num[25:0], 3'd0}) | ({29{lead[4]}} & {num[24:0], 4'd0}) | ({29{lead[5]}} & {num[23:0], 5'd0});

    assign dpos = {3'b000, dn};
    assign dneg = {3'b111, ~dn};

    // W_0 = nn >= 0, so the first digit is +1
    assign ws[0] = {2'b00, nn};
    assign wc[0] = 31'd0;
    assign qp[0] = 1'b1;
    assign qz[0] = 1'b0;
    assign qn[0] = 1'b0;

    generate
        for(g = 0; g < 22; g = g + 1) begin : SRT_STEP
            wire [31:0] ys, yc, t, sm, mj;
            assign ys = {ws[g], 1'b0};
            assign yc = {wc[g], 1'b0};
            assign t = ({32{qp[g]}} & dneg) | ({32{qn[g]}} & dpos);
            assign sm = ys ^ yc ^ t;
            assign mj = (ys & yc) | (ys & t) | (yc & t);
            assign ws[g+1] = sm[30:0];
            assign wc[g+1] = {mj[29:0], qp[g]};
            assign P[21-g] = qp[g];
            assign N[21-g] = qn[g];

            if(g < 21) begin : SEL
                if(OVL) begin : OV
                    // next estimate for each possible digit of this step: 4-bit sum of
                    // (ys ^ yc ^ t)[30:27] and maj(ys, yc, t)[29:26]
                    wire [3:0] sp, sz, sn, cp, cz, cn;
                    wire [3:0] ep, ez, en;
                    assign sp = ys[30:27] ^ yc[30:27] ^ dneg[30:27];
                    assign cp = (ys[29:26] & yc[29:26]) | (ys[29:26] & dneg[29:26]) | (yc[29:26] & dneg[29:26]);
                    assign sz = ys[30:27] ^ yc[30:27];
                    assign cz = ys[29:26] & yc[29:26];
                    assign sn = ys[30:27] ^ yc[30:27] ^ dpos[30:27];
                    assign cn = (ys[29:26] & yc[29:26]) | (ys[29:26] & dpos[29:26]) | (yc[29:26] & dpos[29:26]);
                    assign ep = sp + cp;
                    assign ez = sz + cz;
                    assign en = sn + cn;
                    assign qp[g+1] = (qp[g] && !ep[3]) || (qz[g] && !ez[3]) || (qn[g] && !en[3]);
                    assign qz[g+1] = (qp[g] && (ep == 4'hF)) || (qz[g] && (ez == 4'hF)) || (qn[g] && (en == 4'hF));
                    assign qn[g+1] = (qp[g] && ep[3] && (ep != 4'hF)) || (qz[g] && ez[3] && (ez != 4'hF))
                                  || (qn[g] && en[3] && (en != 4'hF));
                end
                else begin : BS
                    wire [3:0] e;
                    assign e = ws[g+1][30:27] + wc[g+1][30:27];
                    assign qp[g+1] = !e[3];
                    assign qz[g+1] = (e == 4'hF);
                    assign qn[g+1] = e[3] && (e != 4'hF);
                end
            end
        end
    endgenerate

    // floor: one less when the final remainder is negative
    assign wsum = ws[22] + wc[22];
    assign quo = (sat)? 22'h3FFFFF : (P + ~N + {21'd0, !wsum[30]});

endmodule