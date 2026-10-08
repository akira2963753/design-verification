/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    F_ATTN.v
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       F_ATTN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

module fp_mul #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    input [31:0] b,
    output [31:0] z
);
    DW_fp_mult #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .b(b),
        .rnd(3'b000),
        .z(z),
        .status()
    );
endmodule

module fp_add #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    input [31:0] b,
    output [31:0] z
);
    DW_fp_add #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .b(b),
        .rnd(3'b000),
        .z(z),
        .status()
    );
endmodule

module fp_sub #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    input [31:0] b,
    output [31:0] z
);
    DW_fp_sub #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .b(b),
        .rnd(3'b000),
        .z(z),
        .status()
    );
endmodule

module fp_div #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    input [31:0] b,
    output [31:0] z
);
    DW_fp_div #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .b(b),
        .rnd(3'b000),
        .z(z),
        .status()
    );
endmodule

module fp_exp #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    output [31:0] z
);
    DW_fp_exp #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .z(z),
        .status()
    );
endmodule

module fp_max #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0
) (
    input [31:0] a,
    input [31:0] b,
    output [31:0] z
);
    wire a_gt_b;

    DW_fp_cmp #(
        .sig_width(inst_sig_width),
        .exp_width(inst_exp_width),
        .ieee_compliance(inst_ieee_compliance)
    ) u_ip (
        .a(a),
        .b(b),
        .zctr(1'b0),
        .aeqb(),
        .altb(),
        .agtb(a_gt_b),
        .unordered(),
        .z0(),
        .z1(),
        .status0(),
        .status1()
    );
    assign z = (a_gt_b)? a : b;
endmodule

module attn_eng #(
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter inst_ieee_compliance = 0,
    parameter sqare_root_2 = 32'h3FB504F3
) (
    input clk,
    input rst_n,
    input in_valid,
    input [31:0] Q,
    input [31:0] K,
    input [31:0] V,
    input [31:0] out_weight,
    output logic out_valid,
    output logic [31:0] out
);

    //=============================================================
    //                       State Encoding
    //=============================================================
    // IDLE -> LOAD 64 beats -> TILE x8 -> NORM, per head then per query.
    // 32 rows x (8 + 1) + 1 = 289 cycles from in_valid falling to out_valid.
    typedef enum logic [2:0] {
        ST_IDLE = 3'd0,
        ST_LOAD = 3'd1,
        ST_TILE = 3'd2,
        ST_NORM = 3'd3,
        ST_OUT  = 3'd4
    } state_t;
    state_t state, state_n;

    //=============================================================
    //                      Control Register
    //=============================================================
    logic [5:0] beat, out_cnt;
    logic [3:0] q_idx;
    logic h_idx;
    logic [2:0] tile_idx;
    wire load_we = ((state == ST_IDLE) && in_valid) || (state == ST_LOAD);

    always_comb begin : STATE_NS
        state_n = state;
        case(state)
            ST_IDLE: if(in_valid) state_n = ST_LOAD;
            ST_LOAD: if(beat == 6'd63) state_n = ST_TILE;
            ST_TILE: if(tile_idx == 3'd7) state_n = ST_NORM;
            ST_NORM: begin
                if((h_idx == 1'b1) && (q_idx == 4'd15)) state_n = ST_OUT;
                else state_n = ST_TILE;
            end
            ST_OUT: if(out_cnt == 6'd63) state_n = ST_IDLE;
            default: state_n = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin : CTRL_FF
        if(!rst_n) begin
            state <= ST_IDLE;
            beat <= 6'd0;
            out_cnt <= 6'd0;
            q_idx <= 4'd0;
            h_idx <= 1'b0;
            tile_idx <= 3'd0;
        end
        else begin
            state <= state_n;
            case(state)
                ST_IDLE: if(in_valid) beat <= 6'd1;
                ST_LOAD: begin
                    if(beat == 6'd63) beat <= 6'd0;
                    else beat <= beat + 6'd1;
                end
                ST_TILE: begin
                    if(tile_idx == 3'd7) tile_idx <= 3'd0;
                    else tile_idx <= tile_idx + 3'd1;
                end
                ST_NORM: begin
                    if(h_idx == 1'b0) h_idx <= 1'b1;
                    else begin
                        h_idx <= 1'b0;
                        if(q_idx == 4'd15) begin
                            q_idx <= 4'd0;
                            out_cnt <= 6'd0;
                        end
                        else q_idx <= q_idx + 4'd1;
                    end
                end
                ST_OUT: begin
                    if(out_cnt == 6'd63) begin
                        out_cnt <= 6'd0;
                        beat <= 6'd0;
                        q_idx <= 4'd0;
                        h_idx <= 1'b0;
                        tile_idx <= 3'd0;
                    end
                    else out_cnt <= out_cnt + 6'd1;
                end
                default: begin
                    beat <= 6'd0;
                    out_cnt <= 6'd0;
                    q_idx <= 4'd0;
                    h_idx <= 1'b0;
                    tile_idx <= 3'd0;
                end
            endcase
        end
    end

    //=============================================================
    //                       Matrix Storage
    //=============================================================
    logic [31:0] q_mem [0:15][0:3];
    logic [31:0] k_mem [0:15][0:3];
    logic [31:0] v_mem [0:15][0:3];
    logic [31:0] w_mem [0:3][0:3];
    logic [31:0] h_mem [0:15][0:3];
    logic [3:0] load_tok;
    logic [1:0] load_dim;

    assign load_tok = beat[5:2];
    assign load_dim = beat[1:0];

    always_ff @(posedge clk or negedge rst_n) begin : MATRIX_FF
        if(!rst_n) begin
            for(int i = 0; i < 16; i++) begin
                for(int j = 0; j < 4; j++) begin
                    q_mem[i][j] <= 32'd0;
                    k_mem[i][j] <= 32'd0;
                    v_mem[i][j] <= 32'd0;
                end
            end
            for(int i = 0; i < 4; i++) begin
                for(int j = 0; j < 4; j++) w_mem[i][j] <= 32'd0;
            end
        end
        else if(load_we) begin
            q_mem[load_tok][load_dim] <= Q;
            k_mem[load_tok][load_dim] <= K;
            v_mem[load_tok][load_dim] <= V;
            if(beat < 6'd16) w_mem[beat[3:2]][beat[1:0]] <= out_weight;
        end
    end

    //=============================================================
    //                        Running State
    //=============================================================
    // One query row of one head. Tile 0 ignores the old state.
    logic [31:0] run_m, run_l, run_o0, run_o1;
    logic [31:0] m_new, l_new, o0_new, o1_new;

    always_ff @(posedge clk or negedge rst_n) begin : RUN_FF
        if(!rst_n) begin
            run_m <= 32'd0;
            run_l <= 32'd0;
            run_o0 <= 32'd0;
            run_o1 <= 32'd0;
        end
        else if(state == ST_TILE) begin
            run_m <= m_new;
            run_l <= l_new;
            run_o0 <= o0_new;
            run_o1 <= o1_new;
        end
        else if(state == ST_NORM) begin
            run_m <= 32'd0;
            run_l <= 32'd0;
            run_o0 <= 32'd0;
            run_o1 <= 32'd0;
        end
    end

    //=============================================================
    //                       Operand Select
    //=============================================================
    // Head 0 uses dims 0,1. Head 1 uses dims 2,3.
    // Tile j uses key/value tokens 2j and 2j+1.
    logic [3:0] tok_a, tok_b;
    logic [1:0] dim_lo, dim_hi;
    logic [31:0] q_lo, q_hi;
    logic [31:0] k_a_lo, k_a_hi, k_b_lo, k_b_hi;
    logic [31:0] v_a_lo, v_a_hi, v_b_lo, v_b_hi;
    wire [31:0] sqrt2_w = sqare_root_2;

    assign tok_a = {tile_idx, 1'b0};
    assign tok_b = {tile_idx, 1'b1};
    assign dim_lo = {h_idx, 1'b0};
    assign dim_hi = {h_idx, 1'b1};
    assign q_lo = q_mem[q_idx][dim_lo];
    assign q_hi = q_mem[q_idx][dim_hi];
    assign k_a_lo = k_mem[tok_a][dim_lo];
    assign k_a_hi = k_mem[tok_a][dim_hi];
    assign k_b_lo = k_mem[tok_b][dim_lo];
    assign k_b_hi = k_mem[tok_b][dim_hi];
    assign v_a_lo = v_mem[tok_a][dim_lo];
    assign v_a_hi = v_mem[tok_a][dim_hi];
    assign v_b_lo = v_mem[tok_b][dim_lo];
    assign v_b_hi = v_mem[tok_b][dim_hi];

    //=============================================================
    //                            Score
    //=============================================================
    logic [31:0] prod_a_lo, prod_a_hi, prod_b_lo, prod_b_hi;
    logic [31:0] sum_a, sum_b;
    logic [31:0] div0_a, div0_b, div1_a, div1_b;
    logic [31:0] div0_z, div1_z;
    logic [31:0] s0, s1;

    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_a_lo (
        .a(q_lo),
        .b(k_a_lo),
        .z(prod_a_lo)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_a_hi (
        .a(q_hi),
        .b(k_a_hi),
        .z(prod_a_hi)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_a (
        .a(prod_a_lo),
        .b(prod_a_hi),
        .z(sum_a)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_b_lo (
        .a(q_lo),
        .b(k_b_lo),
        .z(prod_b_lo)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_b_hi (
        .a(q_hi),
        .b(k_b_hi),
        .z(prod_b_hi)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_b (
        .a(prod_b_lo),
        .b(prod_b_hi),
        .z(sum_b)
    );

    // Same two dividers normalize O/l after the eight tiles.
    assign div0_a = (state == ST_NORM)? run_o0 : sum_a;
    assign div0_b = (state == ST_NORM)? run_l : sqrt2_w;
    assign div1_a = (state == ST_NORM)? run_o1 : sum_b;
    assign div1_b = (state == ST_NORM)? run_l : sqrt2_w;
    assign s0 = div0_z;
    assign s1 = div1_z;

    fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_div0 (
        .a(div0_a),
        .b(div0_b),
        .z(div0_z)
    );
    fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_div1 (
        .a(div1_a),
        .b(div1_b),
        .z(div1_z)
    );

    //=============================================================
    //                       Online Softmax
    //=============================================================
    logic tile_first;
    logic [31:0] max_s, max_ms;
    logic [31:0] sub_m, sub_0, sub_1;
    logic [31:0] exp_c, exp_0, exp_1;
    logic [31:0] alpha, scale_l, sum_p;
    logic [31:0] scale_o0, pv_0a, pv_0b, sum_v0;
    logic [31:0] scale_o1, pv_1a, pv_1b, sum_v1;

    assign tile_first = (tile_idx == 3'd0);

    fp_max #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_max_s (
        .a(s0),
        .b(s1),
        .z(max_s)
    );
    fp_max #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_max_m (
        .a(run_m),
        .b(max_s),
        .z(max_ms)
    );
    assign m_new = (tile_first)? max_s : max_ms;

    fp_sub #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_sub_m (
        .a(run_m),
        .b(m_new),
        .z(sub_m)
    );
    fp_sub #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_sub_0 (
        .a(s0),
        .b(m_new),
        .z(sub_0)
    );
    fp_sub #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_sub_1 (
        .a(s1),
        .b(m_new),
        .z(sub_1)
    );
    fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_exp_c (
        .a(sub_m),
        .z(exp_c)
    );
    fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_exp_0 (
        .a(sub_0),
        .z(exp_0)
    );
    fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_exp_1 (
        .a(sub_1),
        .z(exp_1)
    );

    assign alpha = (tile_first)? 32'h00000000 : exp_c;

    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_l (
        .a(alpha),
        .b(run_l),
        .z(scale_l)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_p (
        .a(exp_0),
        .b(exp_1),
        .z(sum_p)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_l (
        .a(scale_l),
        .b(sum_p),
        .z(l_new)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_o0 (
        .a(alpha),
        .b(run_o0),
        .z(scale_o0)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_v0a (
        .a(exp_0),
        .b(v_a_lo),
        .z(pv_0a)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_v0b (
        .a(exp_1),
        .b(v_b_lo),
        .z(pv_0b)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_v0 (
        .a(pv_0a),
        .b(pv_0b),
        .z(sum_v0)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_o0 (
        .a(scale_o0),
        .b(sum_v0),
        .z(o0_new)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_o1 (
        .a(alpha),
        .b(run_o1),
        .z(scale_o1)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_v1a (
        .a(exp_0),
        .b(v_a_hi),
        .z(pv_1a)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_v1b (
        .a(exp_1),
        .b(v_b_hi),
        .z(pv_1b)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_v1 (
        .a(pv_1a),
        .b(pv_1b),
        .z(sum_v1)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_o1 (
        .a(scale_o1),
        .b(sum_v1),
        .z(o1_new)
    );

    //=============================================================
    //                       Head Normalize
    //=============================================================
    always_ff @(posedge clk or negedge rst_n) begin : HEAD_FF
        if(!rst_n) begin
            for(int i = 0; i < 16; i++) begin
                for(int j = 0; j < 4; j++) h_mem[i][j] <= 32'd0;
            end
        end
        else if(state == ST_NORM) begin
            h_mem[q_idx][dim_lo] <= div0_z;
            h_mem[q_idx][dim_hi] <= div1_z;
        end
    end

    //=============================================================
    //                        Linear Layer
    //=============================================================
    // Final[t][k] = H[t][0]*W[k][0] + H[t][1]*W[k][1] + H[t][2]*W[k][2] + H[t][3]*W[k][3]
    logic [3:0] out_tok;
    logic [1:0] out_col;
    logic [31:0] h0, h1, h2, h3;
    logic [31:0] w0, w1, w2, w3;
    logic [31:0] y0, y1, y2, y3;
    logic [31:0] acc01, acc012, lin_z;

    assign out_tok = out_cnt[5:2];
    assign out_col = out_cnt[1:0];
    assign h0 = h_mem[out_tok][2'd0];
    assign h1 = h_mem[out_tok][2'd1];
    assign h2 = h_mem[out_tok][2'd2];
    assign h3 = h_mem[out_tok][2'd3];
    assign w0 = w_mem[out_col][2'd0];
    assign w1 = w_mem[out_col][2'd1];
    assign w2 = w_mem[out_col][2'd2];
    assign w3 = w_mem[out_col][2'd3];

    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_y0 (
        .a(h0),
        .b(w0),
        .z(y0)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_y1 (
        .a(h1),
        .b(w1),
        .z(y1)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_y2 (
        .a(h2),
        .b(w2),
        .z(y2)
    );
    fp_mul #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_mul_y3 (
        .a(h3),
        .b(w3),
        .z(y3)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_y01 (
        .a(y0),
        .b(y1),
        .z(acc01)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_y2 (
        .a(acc01),
        .b(y2),
        .z(acc012)
    );
    fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) u_add_y3 (
        .a(acc012),
        .b(y3),
        .z(lin_z)
    );

    //=============================================================
    //                       Output Register
    //=============================================================
    always_ff @(posedge clk or negedge rst_n) begin : OUT_FF
        if(!rst_n) begin
            out_valid <= 1'b0;
            out <= 32'd0;
        end
        else if(state == ST_OUT) begin
            out_valid <= 1'b1;
            out <= lin_z;
        end
        else begin
            out_valid <= 1'b0;
            out <= 32'd0;
        end
    end

endmodule

module F_ATTN (
    input clk,
    input rst_n,
    input in_valid,
    input [31:0] Q,
    input [31:0] K,
    input [31:0] V,
    input [31:0] out_weight,
    output logic out_valid,
    output logic [31:0] out
);
    parameter inst_sig_width = 23;
    parameter inst_exp_width = 8;
    parameter inst_ieee_compliance = 0;
    parameter sqare_root_2 = 32'h3FB504F3;

    attn_eng #(
        .inst_sig_width(inst_sig_width),
        .inst_exp_width(inst_exp_width),
        .inst_ieee_compliance(inst_ieee_compliance),
        .sqare_root_2(sqare_root_2)
    ) u_eng (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .Q(Q),
        .K(K),
        .V(V),
        .out_weight(out_weight),
        .out_valid(out_valid),
        .out(out)
    );
endmodule
