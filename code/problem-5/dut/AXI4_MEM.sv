/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    AXI4_MEM.sv
* Project:      SV Practice, Problem 5
* Module:       AXI4_MEM
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

module AXI4_MEM (
    input ACLK,
    input ARESETn,
    // AW channel
    input [3:0] AWID,
    input [31:0] AWADDR,
    input [7:0] AWLEN,
    input [2:0] AWSIZE,
    input [1:0] AWBURST,
    input AWVALID,
    output logic AWREADY,
    // W channel
    input [31:0] WDATA,
    input [3:0] WSTRB,
    input WLAST,
    input WVALID,
    output logic WREADY,
    // B channel
    output logic [3:0] BID,
    output logic [1:0] BRESP,
    output logic BVALID,
    input BREADY,
    // AR channel
    input [3:0] ARID,
    input [31:0] ARADDR,
    input [7:0] ARLEN,
    input [2:0] ARSIZE,
    input [1:0] ARBURST,
    input ARVALID,
    output logic ARREADY,
    // R channel
    output logic [3:0] RID,
    output logic [31:0] RDATA,
    output logic [1:0] RRESP,
    output logic RLAST,
    output logic RVALID,
    input RREADY
);

    //=============================================================
    //                         Parameter
    //=============================================================

    localparam int QD = 4;                  // AW queue, B pool and AR pool depth
    localparam int WORDS = 1024;            // 4KB memory
    localparam logic [1:0] FIXED = 2'b00;
    localparam logic [1:0] INCR = 2'b01;
    localparam logic [1:0] WRAP = 2'b10;
    localparam logic [1:0] OKAY = 2'b00;
    localparam logic [1:0] SLVERR = 2'b10;

    //=============================================================
    //                           Signal
    //=============================================================

    logic [15:0] lfsr;
    logic stall_aw, stall_w, stall_ar, r_gap;

    logic [31:0] mem [0:WORDS-1];

    // AW queue, circular
    logic [3:0] aw_id_q [0:QD-1];
    logic [31:0] aw_addr_q [0:QD-1];
    logic [7:0] aw_len_q [0:QD-1];
    logic [1:0] aw_burst_q [0:QD-1];
    logic [1:0] aw_wp, aw_rp, aw_last;
    logic [2:0] aw_cnt;
    logic aw_hs;

    // W
    logic [7:0] w_beat;
    logic [31:0] w_addr, w_addr_cur;
    logic [3:0] w_strb;
    logic w_hs, w_last_beat, w_err, w_b2b;

    // B pool, oldest first
    logic [3:0] b_id_q [0:QD-1];
    logic [1:0] b_resp_q [0:QD-1];
    logic [2:0] b_dly_q [0:QD-1];
    logic [3:0] b_id_n [0:QD-1];
    logic [1:0] b_resp_n [0:QD-1];
    logic [2:0] b_dly_n [0:QD-1];
    logic [2:0] b_cnt, b_cnt_n;
    logic [1:0] b_pick;
    logic b_pick_ok, b_take, b_push, b_older;
    logic b_retry;
    logic [1:0] b_wait;

    // AR pool, oldest first
    logic [3:0] ar_id_q [0:QD-1];
    logic [31:0] ar_addr_q [0:QD-1];
    logic [7:0] ar_len_q [0:QD-1];
    logic [1:0] ar_burst_q [0:QD-1];
    logic [2:0] ar_dly_q [0:QD-1];
    logic [3:0] ar_id_n [0:QD-1];
    logic [31:0] ar_addr_n [0:QD-1];
    logic [7:0] ar_len_n [0:QD-1];
    logic [1:0] ar_burst_n [0:QD-1];
    logic [2:0] ar_dly_n [0:QD-1];
    logic [2:0] ar_cnt, ar_cnt_n;
    logic [1:0] ar_pick;
    logic ar_pick_ok, ar_take, ar_hs, ar_older;

    // R engine
    logic [8:0] r_left;
    logic [31:0] r_addr;
    logic [7:0] r_len;
    logic [1:0] r_burst;
    logic [3:0] r_id;
    logic r_err, r_launch;

    //=============================================================
    //                          Function
    //=============================================================

    // Address of the next beat
    function automatic logic [31:0] next_addr(
        input logic [31:0] addr,
        input logic [1:0] burst,
        input logic [7:0] len,
        input logic is_rd
    );
        logic [31:0] mask;
        mask = ({24'd0, len} + 32'd1) * 32'd4 - 32'd1;
`ifdef BUG_4
        if(is_rd && len == 8'd15) mask = 32'd31;
`endif
        case(burst)
            FIXED: begin
`ifdef BUG_12
                if(!is_rd) return addr + 32'd4;
`endif
                return addr;
            end
            WRAP: return (addr & ~mask) | ((addr + 32'd4) & mask);
            default: begin
`ifdef BUG_8
                if(!is_rd) return {addr[31:10], addr[9:0] + 10'd4};
`endif
                return addr + 32'd4;
            end
        endcase
    endfunction

    //=============================================================
    //                   Ready Stall & Delay Source
    //=============================================================

    always_ff @(posedge ACLK or negedge ARESETn) begin : LFSR
        if(!ARESETn) lfsr <= 16'hACE1;
        else lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    assign stall_aw = lfsr[0] & lfsr[1];
    assign stall_w = lfsr[2] & lfsr[3];
    assign stall_ar = lfsr[4] & lfsr[5];
    assign r_gap = lfsr[13] & lfsr[14];

    //=============================================================
    //                          AW Queue
    //=============================================================

    assign AWREADY = (aw_cnt != QD) && !stall_aw;
    assign aw_hs = AWVALID && AWREADY;

    always_ff @(posedge ACLK or negedge ARESETn) begin : AW_QUEUE
        if(!ARESETn) begin
            aw_wp <= 0;
            aw_rp <= 0;
            aw_last <= 0;
            aw_cnt <= 0;
            for(int i = 0; i < QD; i++) begin
                aw_id_q[i] <= 0;
                aw_addr_q[i] <= 0;
                aw_len_q[i] <= 0;
                aw_burst_q[i] <= 0;
            end
        end
        else begin
            if(aw_hs) begin
                aw_id_q[aw_wp] <= AWID;
                aw_addr_q[aw_wp] <= AWADDR;
                aw_len_q[aw_wp] <= AWLEN;
                aw_burst_q[aw_wp] <= AWBURST;
                aw_wp <= aw_wp + 2'd1;
                aw_last <= aw_wp;
            end
            if(w_hs && w_last_beat) aw_rp <= aw_rp + 2'd1;
            aw_cnt <= aw_cnt + aw_hs - (w_hs && w_last_beat);
        end
    end

    //=============================================================
    //                          W Channel
    //=============================================================

    // W beats belong to the oldest AW, WREADY waits for its AW
    assign WREADY = (aw_cnt != 0) && !stall_w && (b_cnt != QD);
    assign w_hs = WVALID && WREADY;

    always_comb begin : W_BEAT
        w_addr = (w_beat == 0)? aw_addr_q[aw_rp] : w_addr_cur;
`ifdef BUG_13
        if(w_beat == 0 && w_b2b) w_addr = w_addr_cur;
`endif
        w_last_beat = (w_beat == aw_len_q[aw_rp]);
`ifdef BUG_6
        w_err = (aw_addr_q[aw_rp][31:13] != 0);
`else
        w_err = (aw_addr_q[aw_rp][31:12] != 0);
`endif
        w_strb = WSTRB;
`ifdef BUG_2
        w_strb[3] = WSTRB[2];
`endif
        b_push = w_hs && w_last_beat;
`ifdef BUG_1
        b_push = w_hs && ((aw_len_q[aw_rp] == 0)? 1'b1 : (w_beat == aw_len_q[aw_rp] - 8'd1));
`endif
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin : W_CTRL
        if(!ARESETn) begin
            w_beat <= 0;
            w_addr_cur <= 0;
            w_b2b <= 0;
        end
        else begin
            w_b2b <= w_hs && w_last_beat;
            if(w_hs) begin
                if(w_last_beat) w_beat <= 0;
                else begin
                    w_beat <= w_beat + 8'd1;
                    w_addr_cur <= next_addr(w_addr, aw_burst_q[aw_rp], aw_len_q[aw_rp], 1'b0);
                end
            end
        end
    end

    //=============================================================
    //                           Memory
    //=============================================================

`ifdef BUG_9
    always_ff @(posedge ACLK) begin : MEM
        if(w_hs && !w_err) begin
            for(int b = 0; b < 4; b++) if(w_strb[b]) mem[w_addr[11:2]][b*8 +: 8] <= WDATA[b*8 +: 8];
        end
    end
`else
    always_ff @(posedge ACLK or negedge ARESETn) begin : MEM
        if(!ARESETn) begin
            for(int i = 0; i < WORDS; i++) mem[i] <= 0;
        end
        else if(w_hs && !w_err) begin
            for(int b = 0; b < 4; b++) if(w_strb[b]) mem[w_addr[11:2]][b*8 +: 8] <= WDATA[b*8 +: 8];
        end
    end
`endif

    //=============================================================
    //                          B Channel
    //=============================================================

    // Oldest ready entry whose ID has no older entry in the pool
    always_comb begin : B_PICK
        b_pick_ok = 0;
        b_pick = 0;
        b_older = 0;
        for(int i = 0; i < QD; i++) begin
            if(!b_pick_ok && i < b_cnt && b_dly_q[i] == 0) begin
                b_older = 0;
                for(int j = 0; j < i; j++) if(b_id_q[j] == b_id_q[i]) b_older = 1;
                if(!b_older) begin
                    b_pick_ok = 1;
                    b_pick = i;
                end
            end
        end
        b_take = b_pick_ok && !BVALID && !b_retry;
    end

    always_comb begin : B_POOL_NXT
        int k;
        b_cnt_n = b_cnt - b_take;
        for(int i = 0; i < QD; i++) begin
            k = (b_take && i >= b_pick)? i + 1 : i;
            if(k < QD) begin
                b_id_n[i] = b_id_q[k];
                b_resp_n[i] = b_resp_q[k];
                b_dly_n[i] = (b_dly_q[k] != 0)? b_dly_q[k] - 3'd1 : 3'd0;
            end
            else begin
                b_id_n[i] = 0;
                b_resp_n[i] = 0;
                b_dly_n[i] = 0;
            end
        end
        if(b_push) begin
            b_id_n[b_cnt_n] = aw_id_q[aw_rp];
            b_resp_n[b_cnt_n] = (w_err)? SLVERR : OKAY;
            b_dly_n[b_cnt_n] = lfsr[8:6];
            b_cnt_n = b_cnt_n + 3'd1;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin : B_POOL
        if(!ARESETn) begin
            b_cnt <= 0;
            for(int i = 0; i < QD; i++) begin
                b_id_q[i] <= 0;
                b_resp_q[i] <= 0;
                b_dly_q[i] <= 0;
            end
        end
        else begin
            b_cnt <= b_cnt_n;
            for(int i = 0; i < QD; i++) begin
                b_id_q[i] <= b_id_n[i];
                b_resp_q[i] <= b_resp_n[i];
                b_dly_q[i] <= b_dly_n[i];
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin : B_OUT
        if(!ARESETn) begin
            BVALID <= 0;
            BID <= 0;
            BRESP <= 0;
            b_retry <= 0;
            b_wait <= 0;
        end
        else begin
            if(b_take) begin
                BVALID <= 1;
`ifdef BUG_11
                BID <= aw_id_q[aw_last];
`else
                BID <= b_id_q[b_pick];
`endif
                BRESP <= b_resp_q[b_pick];
            end
            else if(BVALID && BREADY) BVALID <= 0;
`ifdef BUG_5
            else if(BVALID && b_wait == 2'd2) begin
                BVALID <= 0;
                b_retry <= 1;
            end
            else if(b_retry) begin
                BVALID <= 1;
                b_retry <= 0;
            end
            b_wait <= (BVALID && !BREADY && b_wait != 2'd2)? b_wait + 2'd1 : 2'd0;
`endif
        end
    end

    //=============================================================
    //                          AR Pool
    //=============================================================

    assign ARREADY = (ar_cnt != QD) && !stall_ar;
    assign ar_hs = ARVALID && ARREADY;

    // Scan oldest first or newest first by an LFSR bit, so bursts of different IDs come back out of order
    always_comb begin : AR_PICK
        int i;
        ar_pick_ok = 0;
        ar_pick = 0;
        ar_older = 0;
        for(int n = 0; n < QD; n++) begin
            i = (lfsr[15])? QD - 1 - n : n;
            if(!ar_pick_ok && i < ar_cnt && ar_dly_q[i] == 0) begin
                ar_older = 0;
`ifndef BUG_3
                for(int j = 0; j < i; j++) if(ar_id_q[j] == ar_id_q[i]) ar_older = 1;
`endif
                if(!ar_older) begin
                    ar_pick_ok = 1;
                    ar_pick = i;
                end
            end
        end
        ar_take = ar_pick_ok && (r_left == 0) && !RVALID;
    end

    always_comb begin : AR_POOL_NXT
        int k;
        ar_cnt_n = ar_cnt - ar_take;
        for(int i = 0; i < QD; i++) begin
            k = (ar_take && i >= ar_pick)? i + 1 : i;
            if(k < QD) begin
                ar_id_n[i] = ar_id_q[k];
                ar_addr_n[i] = ar_addr_q[k];
                ar_len_n[i] = ar_len_q[k];
                ar_burst_n[i] = ar_burst_q[k];
                ar_dly_n[i] = (ar_dly_q[k] != 0)? ar_dly_q[k] - 3'd1 : 3'd0;
            end
            else begin
                ar_id_n[i] = 0;
                ar_addr_n[i] = 0;
                ar_len_n[i] = 0;
                ar_burst_n[i] = 0;
                ar_dly_n[i] = 0;
            end
        end
        if(ar_hs) begin
            ar_id_n[ar_cnt_n] = ARID;
            ar_addr_n[ar_cnt_n] = ARADDR;
            ar_len_n[ar_cnt_n] = ARLEN;
            ar_burst_n[ar_cnt_n] = ARBURST;
            ar_dly_n[ar_cnt_n] = lfsr[11:9];
            ar_cnt_n = ar_cnt_n + 3'd1;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin : AR_POOL
        if(!ARESETn) begin
            ar_cnt <= 0;
            for(int i = 0; i < QD; i++) begin
                ar_id_q[i] <= 0;
                ar_addr_q[i] <= 0;
                ar_len_q[i] <= 0;
                ar_burst_q[i] <= 0;
                ar_dly_q[i] <= 0;
            end
        end
        else begin
            ar_cnt <= ar_cnt_n;
            for(int i = 0; i < QD; i++) begin
                ar_id_q[i] <= ar_id_n[i];
                ar_addr_q[i] <= ar_addr_n[i];
                ar_len_q[i] <= ar_len_n[i];
                ar_burst_q[i] <= ar_burst_n[i];
                ar_dly_q[i] <= ar_dly_n[i];
            end
        end
    end

    //=============================================================
    //                          R Channel
    //=============================================================

    // One burst at a time, beats are never interleaved with another burst
`ifdef BUG_10
    assign r_launch = (r_left != 0) && !r_gap;
`else
    assign r_launch = (r_left != 0) && (!RVALID || RREADY) && !r_gap;
`endif

    always_ff @(posedge ACLK or negedge ARESETn) begin : R_ENGINE
        if(!ARESETn) begin
            r_left <= 0;
            r_addr <= 0;
            r_len <= 0;
            r_burst <= 0;
            r_id <= 0;
            r_err <= 0;
        end
        else if(ar_take) begin
            r_left <= {1'b0, ar_len_q[ar_pick]} + 9'd1;
            r_addr <= ar_addr_q[ar_pick];
            r_len <= ar_len_q[ar_pick];
            r_burst <= ar_burst_q[ar_pick];
            r_id <= ar_id_q[ar_pick];
            r_err <= (ar_addr_q[ar_pick][31:12] != 0);
        end
        else if(r_launch) begin
            r_left <= r_left - 9'd1;
            r_addr <= next_addr(r_addr, r_burst, r_len, 1'b1);
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin : R_OUT
        if(!ARESETn) begin
            RVALID <= 0;
            RID <= 0;
            RDATA <= 0;
            RRESP <= 0;
            RLAST <= 0;
        end
        else if(r_launch) begin
            RVALID <= 1;
            RID <= r_id;
            RDATA <= (r_err)? 32'd0 : mem[r_addr[11:2]];
            RRESP <= (r_err)? SLVERR : OKAY;
`ifdef BUG_7
            RLAST <= (r_left == 9'd1) && (r_len != 0);
`else
            RLAST <= (r_left == 9'd1);
`endif
        end
        else if(RVALID && RREADY) RVALID <= 0;
    end

endmodule
