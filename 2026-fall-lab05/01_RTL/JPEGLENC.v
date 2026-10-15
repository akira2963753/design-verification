/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    JPEGLENC.v
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       JPEGLENC
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

module JPEGLENC (
    input clk,
    input rst_n,
    input in_valid,
    input [7:0] in_data,
    output logic out_valid,
    output logic [7:0] out_data
);

    JPEGLENC_CORE u_core (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .out_valid(out_valid),
        .out_data(out_data)
    );

endmodule

module JPEGLENC_CORE (
    input clk,
    input rst_n,
    input in_valid,
    input [7:0] in_data,
    output logic out_valid,
    output logic [7:0] out_data
);

    localparam int NPIX = 16384;
    localparam int MAX_EMIT = 128;
    localparam int OUT_DEPTH = 32768;

    //=============================================================
    //                      Datapath Storage
    //=============================================================

    logic [7:0] img [0:NPIX-1];
    logic [7:0] obuf [0:OUT_DEPTH-1];

    logic [13:0] in_cnt;
    logic [7:0] blk_cnt;
    logic [15:0] wr_ptr, rd_ptr;
    logic [7:0] bit_acc;
    logic [3:0] bit_n;
    logic signed [15:0] prev_dc;

    logic signed [15:0] enc_dc;
    logic [7:0] enc_acc;
    logic [3:0] enc_nbit;
    logic [7:0] enc_cnt;
    logic [MAX_EMIT-1:0][7:0] enc_bytes;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD,
        ST_ENC,
        ST_PAD,
        ST_OUT
    } state_t;
    state_t state;

    //=============================================================
    //                    Cosine, Shift, Zigzag
    //=============================================================

    localparam int C_TAB [0:7][0:7] = '{
        '{181, 181, 181, 181, 181, 181, 181, 181},
        '{251, 213, 142, 50, -50, -142, -213, -251},
        '{237, 98, -98, -237, -237, -98, 98, 237},
        '{213, -50, -251, -142, 142, 251, 50, -213},
        '{181, -181, -181, 181, 181, -181, -181, 181},
        '{142, -251, 50, 213, -213, -50, 251, -142},
        '{98, -237, 237, -98, -98, 237, -237, 98},
        '{50, -142, 213, -251, 251, -213, 142, -50}
    };

    localparam int S_TAB [0:7][0:7] = '{
        '{4, 3, 3, 4, 5, 5, 6, 6},
        '{4, 4, 4, 4, 5, 6, 6, 6},
        '{4, 4, 4, 5, 5, 6, 6, 6},
        '{4, 4, 4, 5, 6, 6, 6, 6},
        '{4, 4, 5, 6, 6, 7, 7, 6},
        '{5, 5, 6, 6, 6, 7, 7, 7},
        '{6, 6, 6, 6, 7, 7, 7, 7},
        '{6, 7, 7, 7, 7, 7, 7, 7}
    };

    localparam int ZZ_U [0:63] = '{
        0, 1, 0, 0, 1, 2, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5,
        4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4,
        3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3,
        2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 5, 6, 7, 7, 6, 7
    };

    localparam int ZZ_V [0:63] = '{
        0, 0, 1, 2, 1, 0, 0, 1, 2, 3, 4, 3, 2, 1, 0, 0,
        1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3,
        4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 2, 3, 4, 5, 6,
        7, 7, 6, 5, 4, 3, 4, 5, 6, 7, 7, 6, 5, 6, 7, 7
    };

    //=============================================================
    //                       Huffman Tables
    //=============================================================

    localparam logic [4:0] DC_LEN [0:11] = '{
        5'd2, 5'd3, 5'd3, 5'd3, 5'd3, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9
    };

    localparam logic [15:0] DC_CODE [0:11] = '{
        16'h0000, 16'h0002, 16'h0003, 16'h0004, 16'h0005, 16'h0006,
        16'h000E, 16'h001E, 16'h003E, 16'h007E, 16'h00FE, 16'h01FE
    };

    localparam logic [4:0] AC_LEN [0:255] = '{
        5'd4, 5'd2, 5'd2, 5'd3, 5'd4, 5'd5, 5'd7, 5'd8, 5'd10, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd4, 5'd5, 5'd7, 5'd9, 5'd11, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd5, 5'd8, 5'd10, 5'd12, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd6, 5'd9, 5'd12, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd6, 5'd10, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd7, 5'd11, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd7, 5'd12, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd8, 5'd12, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd9, 5'd15, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd9, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd9, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd10, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd10, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd11, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd0, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0,
        5'd11, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd16, 5'd0, 5'd0, 5'd0, 5'd0, 5'd0
    };

    localparam logic [15:0] AC_CODE [0:255] = '{
        16'h000A, 16'h0000, 16'h0001, 16'h0004, 16'h000B, 16'h001A, 16'h0078, 16'h00F8,
        16'h03F6, 16'hFF82, 16'hFF83, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h000C, 16'h001B, 16'h0079, 16'h01F6, 16'h07F6, 16'hFF84, 16'hFF85,
        16'hFF86, 16'hFF87, 16'hFF88, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h001C, 16'h00F9, 16'h03F7, 16'h0FF4, 16'hFF89, 16'hFF8A, 16'hFF8B,
        16'hFF8C, 16'hFF8D, 16'hFF8E, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h003A, 16'h01F7, 16'h0FF5, 16'hFF8F, 16'hFF90, 16'hFF91, 16'hFF92,
        16'hFF93, 16'hFF94, 16'hFF95, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h003B, 16'h03F8, 16'hFF96, 16'hFF97, 16'hFF98, 16'hFF99, 16'hFF9A,
        16'hFF9B, 16'hFF9C, 16'hFF9D, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h007A, 16'h07F7, 16'hFF9E, 16'hFF9F, 16'hFFA0, 16'hFFA1, 16'hFFA2,
        16'hFFA3, 16'hFFA4, 16'hFFA5, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h007B, 16'h0FF6, 16'hFFA6, 16'hFFA7, 16'hFFA8, 16'hFFA9, 16'hFFAA,
        16'hFFAB, 16'hFFAC, 16'hFFAD, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h00FA, 16'h0FF7, 16'hFFAE, 16'hFFAF, 16'hFFB0, 16'hFFB1, 16'hFFB2,
        16'hFFB3, 16'hFFB4, 16'hFFB5, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h01F8, 16'h7FC0, 16'hFFB6, 16'hFFB7, 16'hFFB8, 16'hFFB9, 16'hFFBA,
        16'hFFBB, 16'hFFBC, 16'hFFBD, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h01F9, 16'hFFBE, 16'hFFBF, 16'hFFC0, 16'hFFC1, 16'hFFC2, 16'hFFC3,
        16'hFFC4, 16'hFFC5, 16'hFFC6, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h01FA, 16'hFFC7, 16'hFFC8, 16'hFFC9, 16'hFFCA, 16'hFFCB, 16'hFFCC,
        16'hFFCD, 16'hFFCE, 16'hFFCF, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h03F9, 16'hFFD0, 16'hFFD1, 16'hFFD2, 16'hFFD3, 16'hFFD4, 16'hFFD5,
        16'hFFD6, 16'hFFD7, 16'hFFD8, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h03FA, 16'hFFD9, 16'hFFDA, 16'hFFDB, 16'hFFDC, 16'hFFDD, 16'hFFDE,
        16'hFFDF, 16'hFFE0, 16'hFFE1, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'h07F8, 16'hFFE2, 16'hFFE3, 16'hFFE4, 16'hFFE5, 16'hFFE6, 16'hFFE7,
        16'hFFE8, 16'hFFE9, 16'hFFEA, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h0000, 16'hFFEB, 16'hFFEC, 16'hFFED, 16'hFFEE, 16'hFFEF, 16'hFFF0, 16'hFFF1,
        16'hFFF2, 16'hFFF3, 16'hFFF4, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000,
        16'h07F9, 16'hFFF5, 16'hFFF6, 16'hFFF7, 16'hFFF8, 16'hFFF9, 16'hFFFA, 16'hFFFB,
        16'hFFFC, 16'hFFFD, 16'hFFFE, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000
    };

    //=============================================================
    //                     Arithmetic Helpers
    //=============================================================

    function automatic int round_s(input int a, input logic [4:0] n);
        logic [31:0] m;
        begin
            m = (a < 0)? -a : a;
            m = (m + (32'd1 << (n - 5'd1))) >> n;
            round_s = (a < 0)? -int'(m) : int'(m);
        end
    endfunction

    function automatic logic [3:0] get_size(input int a);
        logic [31:0] m;
        logic [3:0] n;
        begin
            m = (a < 0)? -a : a;
            n = 4'd0;
            for(int i = 0; i < 16; i++) begin
                if(m != 32'd0) begin
                    n = n + 4'd1;
                    m = m >> 1;
                end
            end
            get_size = n;
        end
    endfunction

    function automatic logic [15:0] get_amp(input int a, input logic [3:0] sz);
        int r;
        begin
            r = (a < 0)? ((32'sd1 << sz) - 1 + a) : a;
            get_amp = r[15:0];
        end
    endfunction

    function automatic void emit(
        input logic [15:0] code,
        input logic [4:0] len,
        inout logic [7:0] acc,
        inout logic [3:0] nbit,
        inout logic [7:0] cnt,
        inout logic [MAX_EMIT-1:0][7:0] obytes
    );
        logic bv;
        logic [4:0] idx;
        begin
            for(int i = 0; i < 16; i++) begin
                if(i < len) begin
                    idx = len - 5'd1 - i[4:0];
                    bv = code[idx];
                    acc = {acc[6:0], bv};
                    if(nbit == 4'd7) begin
                        obytes[cnt] = acc;
                        cnt = cnt + 8'd1;
                        nbit = 4'd0;
                    end
                    else nbit = nbit + 4'd1;
                end
            end
        end
    endfunction

    function automatic void enc_block(
        input logic [63:0][7:0] pix,
        input logic signed [15:0] dc_i,
        input logic [7:0] acc_i,
        input logic [3:0] nbit_i,
        output logic signed [15:0] dc_o,
        output logic [7:0] acc_o,
        output logic [3:0] nbit_o,
        output logic [7:0] cnt_o,
        output logic [MAX_EMIT-1:0][7:0] obytes
    );
        int pmat [0:7][0:7];
        int r [0:7][0:7];
        int aval [0:7][0:7];
        int q [0:7][0:7];
        int z [0:63];
        int acc, diff, run;
        logic [3:0] sz;
        logic [7:0] sym;
        logic [7:0] acc_l;
        logic [3:0] nbit_l;
        logic [7:0] cnt_l;
        logic [MAX_EMIT-1:0][7:0] bytes_l;
        begin
            acc_l = acc_i;
            nbit_l = nbit_i;
            cnt_l = 8'd0;
            dc_o = dc_i;
            for(int i = 0; i < MAX_EMIT; i++) bytes_l[i] = 8'd0;

            for(int ly = 0; ly < 8; ly++) begin
                for(int lx = 0; lx < 8; lx++) pmat[lx][ly] = int'(pix[ly * 8 + lx]) - 128;
            end

            for(int ly = 0; ly < 8; ly++) begin
                for(int u = 0; u < 8; u++) begin
                    acc = 0;
                    for(int lx = 0; lx < 8; lx++) acc = acc + pmat[lx][ly] * C_TAB[u][lx];
                    r[u][ly] = acc;
                end
            end

            for(int u = 0; u < 8; u++) begin
                for(int v = 0; v < 8; v++) begin
                    acc = 0;
                    for(int ly = 0; ly < 8; ly++) acc = acc + r[u][ly] * C_TAB[v][ly];
                    aval[u][v] = round_s(acc, 5'd18);
                    q[u][v] = round_s(aval[u][v], 5'(S_TAB[v][u]));
                end
            end

            for(int k = 0; k < 64; k++) z[k] = q[ZZ_U[k]][ZZ_V[k]];

            diff = z[0] - int'(dc_i);
            dc_o = z[0][15:0];
            sz = get_size(diff);
            emit(DC_CODE[sz], DC_LEN[sz], acc_l, nbit_l, cnt_l, bytes_l);
            emit(get_amp(diff, sz), sz, acc_l, nbit_l, cnt_l, bytes_l);

            run = 0;
            for(int k = 1; k < 64; k++) begin
                if(z[k] == 0) run = run + 1;
                else begin
                    for(int t = 0; t < 4; t++) begin
                        if(run >= 16) begin
                            emit(AC_CODE[8'hF0], AC_LEN[8'hF0], acc_l, nbit_l, cnt_l, bytes_l);
                            run = run - 16;
                        end
                    end
                    sz = get_size(z[k]);
                    sym = {run[3:0], sz};
                    emit(AC_CODE[sym], AC_LEN[sym], acc_l, nbit_l, cnt_l, bytes_l);
                    emit(get_amp(z[k], sz), sz, acc_l, nbit_l, cnt_l, bytes_l);
                    run = 0;
                end
            end
            if(run > 0) emit(AC_CODE[8'h00], AC_LEN[8'h00], acc_l, nbit_l, cnt_l, bytes_l);

            acc_o = acc_l;
            nbit_o = nbit_l;
            cnt_o = cnt_l;
            obytes = bytes_l;
        end
    endfunction

    //=============================================================
    //                        Block Encode
    //=============================================================

    always_comb begin : ENC_COMB
        logic [63:0][7:0] pix;
        logic [3:0] bx, by;

        enc_dc = prev_dc;
        enc_acc = bit_acc;
        enc_nbit = bit_n;
        enc_cnt = 8'd0;
        for(int i = 0; i < MAX_EMIT; i++) enc_bytes[i] = 8'd0;

        if(state == ST_ENC) begin
            bx = blk_cnt[3:0];
            by = blk_cnt[7:4];
            for(int ly = 0; ly < 8; ly++) begin
                for(int lx = 0; lx < 8; lx++) pix[ly * 8 + lx] = img[{by, ly[2:0], bx, lx[2:0]}];
            end
            enc_block(pix, prev_dc, bit_acc, bit_n, enc_dc, enc_acc, enc_nbit, enc_cnt, enc_bytes);
        end
        else if(state == ST_PAD && bit_n != 4'd0) begin
            emit(16'hFFFF, 5'd8 - bit_n, enc_acc, enc_nbit, enc_cnt, enc_bytes);
        end
    end

    //=============================================================
    //                           Control
    //=============================================================

    always_ff @(posedge clk or negedge rst_n) begin : SEQ
        if(!rst_n) begin
            state <= ST_IDLE;
            in_cnt <= 14'd0;
            blk_cnt <= 8'd0;
            wr_ptr <= 16'd0;
            rd_ptr <= 16'd0;
            bit_acc <= 8'd0;
            bit_n <= 4'd0;
            prev_dc <= '0;
            out_valid <= 1'b0;
            out_data <= 8'd0;
        end
        else begin
            out_valid <= 1'b0;
            out_data <= 8'd0;
            case(state)
                ST_IDLE: begin
                    if(in_valid) begin
                        img[0] <= in_data;
                        in_cnt <= 14'd1;
                        state <= ST_LOAD;
                    end
                end
                ST_LOAD: begin
                    img[in_cnt] <= in_data;
                    if(in_cnt == 14'd16383) begin
                        in_cnt <= 14'd0;
                        blk_cnt <= 8'd0;
                        wr_ptr <= 16'd0;
                        rd_ptr <= 16'd0;
                        bit_acc <= 8'd0;
                        bit_n <= 4'd0;
                        prev_dc <= '0;
                        state <= ST_ENC;
                    end
                    else in_cnt <= in_cnt + 14'd1;
                end
                ST_ENC: begin
                    prev_dc <= enc_dc;
                    bit_acc <= enc_acc;
                    bit_n <= enc_nbit;
                    for(int i = 0; i < MAX_EMIT; i++) begin
                        if(i < enc_cnt) obuf[wr_ptr + 16'(i)] <= enc_bytes[i];
                    end
                    wr_ptr <= wr_ptr + enc_cnt;
                    if(blk_cnt == 8'd255) state <= ST_PAD;
                    else blk_cnt <= blk_cnt + 8'd1;
                end
                ST_PAD: begin
                    bit_acc <= enc_acc;
                    bit_n <= enc_nbit;
                    for(int i = 0; i < MAX_EMIT; i++) begin
                        if(i < enc_cnt) obuf[wr_ptr + 16'(i)] <= enc_bytes[i];
                    end
                    wr_ptr <= wr_ptr + enc_cnt;
                    state <= ST_OUT;
                end
                ST_OUT: begin
                    if(rd_ptr != wr_ptr) begin
                        out_valid <= 1'b1;
                        out_data <= obuf[rd_ptr];
                        rd_ptr <= rd_ptr + 16'd1;
                    end
                    else begin
                        state <= ST_IDLE;
                        in_cnt <= 14'd0;
                        blk_cnt <= 8'd0;
                        wr_ptr <= 16'd0;
                        rd_ptr <= 16'd0;
                        bit_acc <= 8'd0;
                        bit_n <= 4'd0;
                        prev_dc <= '0;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
