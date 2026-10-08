/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    FIFO.sv
* Project:      SV Practice, Problem 4
* Module:       FIFO
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

module FIFO (
    input clk,
    input rst_n,
    input push,
    input [7:0] push_data,
    input pop,
    output logic [7:0] pop_data,
    output logic pop_valid,
    output logic full,
    output logic empty,
    output logic [3:0] count,
    output logic overflow,
    output logic underflow
);

    //=============================================================
    //                         Parameter
    //=============================================================

    localparam int DEPTH = 8;

    //=============================================================
    //                           Signal
    //=============================================================

    logic [7:0] mem [0:DEPTH-1];
    logic [2:0] wr_ptr, rd_ptr, rd_ptr_inc;
    logic [3:0] cnt, cnt_nxt;
    logic do_push, do_pop;

    //=============================================================
    //                          Control
    //=============================================================

`ifdef BUG_8
    logic rdy;

    always_ff @(posedge clk or negedge rst_n) begin : READY
        if(!rst_n) rdy <= 0;
        else rdy <= 1;
    end
`endif

    // A pop in the same cycle frees a slot for the push
    always_comb begin : CTRL
        do_pop = pop && (cnt != 0);
        do_push = push && ((cnt != DEPTH) || do_pop);
`ifdef BUG_4
        do_push = push && (cnt != DEPTH);
`endif
`ifdef BUG_10
        if(cnt == 0 && pop) do_push = 0;
`endif
`ifdef BUG_8
        if(!rdy) begin
            do_pop = 0;
            do_push = 0;
        end
`endif
        cnt_nxt = cnt + do_push - do_pop;
    end

    always_comb begin : RD_PTR_INC
        rd_ptr_inc = rd_ptr + 1;
`ifdef BUG_1
        if(rd_ptr == DEPTH - 1) rd_ptr_inc = 1;
`endif
    end

    //=============================================================
    //                           Memory
    //=============================================================

    always_ff @(posedge clk) begin : MEM
`ifdef BUG_6
        if(push) mem[wr_ptr] <= push_data;
`else
        if(do_push) mem[wr_ptr] <= push_data;
`endif
    end

    //=============================================================
    //                       State & Output
    //=============================================================

`ifdef BUG_5
    always_ff @(posedge clk) begin : STATE
`else
    always_ff @(posedge clk or negedge rst_n) begin : STATE
`endif
        if(!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt <= 0;
            count <= 0;
            full <= 0;
            empty <= 1;
            pop_valid <= 0;
            pop_data <= 0;
            overflow <= 0;
            underflow <= 0;
        end
        else begin
            if(do_push) wr_ptr <= wr_ptr + 1;
            if(do_pop) rd_ptr <= rd_ptr_inc;
            cnt <= cnt_nxt;
`ifdef BUG_9
            count <= {1'b0, cnt_nxt[2:0]};
`else
            count <= cnt_nxt;
`endif
`ifdef BUG_2
            full <= (cnt_nxt >= DEPTH - 1);
`else
            full <= (cnt_nxt == DEPTH);
`endif
            empty <= (cnt_nxt == 0);
`ifdef BUG_7
            pop_valid <= pop;
            pop_data <= (pop)? mem[rd_ptr] : 0;
`elsif BUG_3
            pop_valid <= do_pop;
            if(do_pop) pop_data <= mem[rd_ptr];
`else
            pop_valid <= do_pop;
            pop_data <= (do_pop)? mem[rd_ptr] : 0;
`endif
`ifdef BUG_11
            overflow <= push && (cnt == DEPTH);
`else
            overflow <= push && !do_push;
`endif
            underflow <= pop && !do_pop;
        end
    end

endmodule
