/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    vif.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       verification interface
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

interface vif(input logic clk);

    logic clk_en = 1'b0;    // top holds clk low until driver.reset() finishes
    logic rst_n = 1'b1;

    logic in_valid;
    logic [7:0] ring_len;
    logic [2:0] in_color;
    logic shot_valid;
    logic [2:0] shot_color;
    logic [7:0] shot_pos;

    logic out_valid;
    logic [6:0] chain_num;
    logic [2:0] elim_color;
    logic [8:0] elim_cnt;

    //=============================================================
    //                     Driver Interface
    //=============================================================

    clocking drv_cb @(negedge clk);
        default input #1step output #0;
        input out_valid;
        output in_valid, ring_len, in_color, shot_valid, shot_color, shot_pos;
    endclocking

    // clk_en and rst_n are asynchronous, the inputs are written directly during reset
    modport drv(clocking drv_cb, output clk_en, rst_n, in_valid, ring_len, in_color, shot_valid, shot_color, shot_pos);

    //=============================================================
    //                     Monitor Interface
    //=============================================================

    clocking mon_cb @(negedge clk);
        default input #1step;
        input in_valid, ring_len, in_color, shot_valid, shot_color, shot_pos;
        input out_valid, chain_num, elim_color, elim_cnt;
    endclocking

    modport mon(clocking mon_cb);

    //=============================================================
    //                   SystemVerilog Assertion
    //=============================================================

    // Set by the falling edge of rst_n, the X -> 1 initialization at time 0 is not a reset
    bit rst_fell = 1'b0;

    always @(negedge rst_n) rst_fell = 1'b1;

    // SPEC-4: clk is held low during reset, so only an asynchronous reset clears the outputs
    RESET_CHECK: assert property(
        @(posedge rst_n) rst_fell |-> (out_valid === 1'b0 && chain_num === 'd0 && elim_color === 'd0 && elim_cnt === 'd0)
    ) else $fatal(1, "[SVA FAILED] SPEC-4 all outputs must be 0 after reset");

    OUT_VALID_UNKNOWN_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) !$isunknown(out_valid)
    ) else $fatal(1, "[SVA FAILED] out_valid must be known after reset");

    OUT_UNKNOWN_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) out_valid |-> !$isunknown({chain_num, elim_color, elim_cnt})
    ) else $fatal(1, "[SVA FAILED] All outputs must be known when out_valid is high");

    // SPEC-5
    OUT_ZERO_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) !out_valid |-> (chain_num == 'd0 && elim_color == 'd0 && elim_cnt == 'd0)
    ) else $fatal(1, "[SVA FAILED] SPEC-5 chain_num, elim_color and elim_cnt must be 0 when out_valid is low");

    // SPEC-5
    ELIM_ZERO_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) (out_valid && chain_num == 'd0) |-> (elim_color == 'd0 && elim_cnt == 'd0)
    ) else $fatal(1, "[SVA FAILED] SPEC-5 elim_color and elim_cnt must be 0 when chain_num is 0");

    // SPEC-6
    IN_OUT_POS_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) (in_valid || shot_valid) |-> !out_valid
    ) else $fatal(1, "[SVA FAILED] SPEC-6 out_valid must be low when in_valid or shot_valid is high");

    // SPEC-6: out_valid raised at the posedge taking in_valid / shot_valid overlaps them until this negedge
    IN_OUT_NEG_CHECK: assert property(
        @(negedge clk) disable iff(!rst_n) (in_valid || shot_valid) |-> !out_valid
    ) else $fatal(1, "[SVA FAILED] SPEC-6 out_valid must be low when in_valid or shot_valid is high");

    // SPEC-7: out_valid falls within 1000 cycles after the posedge taking shot_valid, $fell sees it 1 cycle later
    MAX_LAT_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) shot_valid |-> ##[1:1001] $fell(out_valid)
    ) else $fatal(1, "[SVA FAILED] SPEC-7 latency over 1000 cycles");

    // SPEC-9
    CHAIN_STABLE_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) (out_valid && $past(out_valid)) |-> $stable(chain_num)
    ) else $fatal(1, "[SVA FAILED] SPEC-9 chain_num must be stable when out_valid is high");

    // SPEC-9: n cycles when chain_num = n >= 1, 1 cycle when chain_num = 0
    property p_out_len;
        int n;
        @(posedge clk) disable iff(!rst_n)
        ($rose(out_valid), n = (chain_num == 0)? 1 : chain_num) |->
        (out_valid, n = n - 1)[*1:$] ##1 (!out_valid && n == 0);
    endproperty

    OUT_LEN_CHECK: assert property(p_out_len)
    else $fatal(1, "[SVA FAILED] SPEC-9 out_valid length must match chain_num");

    // A shot is waiting for its out_valid burst, set by shot_valid, cleared by the 1st out_valid cycle
    logic shot_pend;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) shot_pend <= 1'b0;
        else if(shot_valid) shot_pend <= 1'b1;
        else if(out_valid) shot_pend <= 1'b0;
    end

    // One out_valid burst per shot, no burst without a shot
    OUT_SHOT_CHECK: assert property(
        @(posedge clk) disable iff(!rst_n) $rose(out_valid) |-> shot_pend
    ) else $fatal(1, "[SVA FAILED] out_valid rises without a pending shot");

endinterface
