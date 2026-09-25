/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through PATTERN.sv only, not again in file.f.
`include "vif.sv"
`include "trans.sv"
// class trans [constraint-random LLR], class mon_txn [pin-level snapshot]

`include "generator.sv"
// input mailbox #(trans) gen2drv [generate constraint-random input to driver]
// input uint pattern_num, string g_path

`include "driver.sv"
// input virtual vif.DRV vif [driver interface]
// input mailbox #(trans) gen2drv [transactions from generator]
// input uint pattern_num

`include "ref_model.sv"
// spec-level decoder, used by scoreboard

`include "monitor.sv"
// input virtual vif.MON mon_if [monitor interface]
// input mailbox #(mon_txn) mon2scb [sampled i/o for scoreboard]
// input uint pattern_num

`include "scoreboard.sv"
// input mailbox #(mon_txn) mon2scb [receive the i/o data from monitor]
// input uint pattern_num

module PATTERN (
    output logic clk,
    output logic rst_n,
    output wire in_mode_valid,
    output wire in_mode,
    output wire in_data_valid,
    output wire signed [5:0] in_data,
    input wire out_valid,
    input wire signed [7:0] out_data,
    input wire out_warn
);

    //=============================================================
    //                       Configuration
    //=============================================================

    localparam uint PATTERN_NUM = 1000;
    localparam realtime CLK_PERIOD = 15.0;
    localparam string G_PATH = "../00_TESTBED/G_128_64.txt";
    // mode 1 + gap 4 + data 128 + latency 100 + output 128 + gap 4 < 400 cycles
    localparam realtime TIMEOUT = (PATTERN_NUM + 10.0) * 400.0 * CLK_PERIOD;

    //=============================================================
    //                    Interface Connections
    //=============================================================

    vif tb_if(.clk(clk));

    // Driver owns the inputs through drv_cb, PATTERN owns rst_n
    assign in_mode_valid = tb_if.in_mode_valid;
    assign in_mode = tb_if.in_mode;
    assign in_data_valid = tb_if.in_data_valid;
    assign in_data = tb_if.in_data;
    assign tb_if.rst_n = rst_n;
    assign tb_if.out_valid = out_valid;
    assign tb_if.out_data = out_data;
    assign tb_if.out_warn = out_warn;

    //=============================================================
    //                     Environment Objects
    //=============================================================

    // Instance 4 components and 2 mailboxes
    mailbox #(trans) gen2drv;    // generator to driver
    mailbox #(mon_txn) mon2scb;  // monitor to scoreboard

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    //=============================================================
    //                            Clock
    //=============================================================

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    //=============================================================
    //                            Reset
    //=============================================================

    task automatic drive_reset();
        tb_if.in_mode_valid = 1'b0;
        tb_if.in_mode = 1'b0;
        tb_if.in_data_valid = 1'b0;
        tb_if.in_data = '0;

        rst_n = 1'b1;
        force clk = 1'b0;
        #20 rst_n = 1'b0;
        #20 rst_n = 1'b1;
        release clk;
        @(negedge clk);
    endtask

    //=============================================================
    //                           Main Flow
    //=============================================================

    initial begin : MAIN_FLOW
        clk = 1'b0;
        gen2drv = new(1);
        mon2scb = new();
        gen = new(gen2drv, PATTERN_NUM, G_PATH);
        drv = new(tb_if.DRV, gen2drv, PATTERN_NUM);
        mon = new(tb_if.MON, mon2scb, PATTERN_NUM);
        scb = new(mon2scb, PATTERN_NUM);

        $display("================================================================");
        $display("                  LDPC Environment Started");
        $display("Patterns = %0d, clock period = %0.1f ns", PATTERN_NUM, CLK_PERIOD);
        $display("================================================================");

        drive_reset();

        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join

        @(negedge clk);

        scb.report();
        $display("================================================================");
        $display("                  LDPC Environment Completed");
        $display("                  Congratulations! All Pass");
        $display("================================================================");
        $finish;
    end

    //=============================================================
    //                           Watchdog
    //=============================================================

    initial begin : WATCHDOG
        #(TIMEOUT);
        $display("Simulation timeout at %0t; expected patterns = %0d", $time, PATTERN_NUM);
        if(mon != null) $display("Sampled patterns = %0d", mon.sampled_num);
        if(scb != null) $display("Checked patterns = %0d", scb.checked_num);
        if(gen2drv != null) $display("gen2drv pending = %0d", gen2drv.num());
        if(mon2scb != null) $display("mon2scb pending = %0d", mon2scb.num());
        $fatal(1,
            {"================================================================\n",
            "                 Environment Timeout ! ! !\n",
            "================================================================"});
    end

    //=============================================================
    //                   SystemVerilog Assertion
    //=============================================================
    // Property Name: assert property(condition) <pass event> else <fail event>

    // DUT output rules

    // clk is forced during drive_reset, so spec 3 is sampled at the rst_n rising edge
    RESET_OUT_ZERO: assert property(
        @(posedge rst_n)
        $time > 0 |-> (!out_valid && !out_warn && out_data == 0)
    )
    else $fatal(1, "[ERROR]: All outputs must be 0 after reset is asserted (spec 3).");

    OUT_VALID_KNOWN: assert property(
        @(posedge clk) disable iff(!rst_n)
        !$isunknown(out_valid)
    )
    else $fatal(1, "[ERROR]: out_valid is X/Z after reset.");

    OUT_ZERO_WHEN_INVALID: assert property(
        @(posedge clk) disable iff(!rst_n)
        !out_valid |-> (out_data == 0 && !out_warn)
    )
    else $fatal(1, "[ERROR]: out_data and out_warn must be 0 while out_valid is low (spec 4).");

    OUT_KNOWN_WHEN_VALID: assert property(
        @(posedge clk) disable iff(!rst_n)
        out_valid |-> !$isunknown({out_data, out_warn})
    )
    else $fatal(1, "[ERROR]: out_data / out_warn is X/Z while out_valid is high.");

    OUT_VALID_NO_OVERLAP: assert property(
        @(posedge clk) disable iff(!rst_n)
        out_valid |-> (!in_mode_valid && !in_data_valid)
    )
    else $fatal(1, "[ERROR]: out_valid must not be high with in_mode_valid or in_data_valid (spec 7).");

    OUT_VALID_128_CYCLES: assert property(
        @(posedge clk) disable iff(!rst_n)
        !out_valid ##1 out_valid |-> out_valid[*128] ##1 !out_valid
    )
    else $fatal(1, "[ERROR]: out_valid must be high for exactly 128 consecutive cycles.");

    OUT_WARN_STABLE: assert property(
        @(posedge clk) disable iff(!rst_n)
        out_valid ##1 out_valid |-> $stable(out_warn)
    )
    else $fatal(1, "[ERROR]: out_warn must stay constant during the out_valid period.");

    LATENCY_LIMIT: assert property(
        @(posedge clk) disable iff(!rst_n)
        in_data_valid ##1 !in_data_valid |-> ##[0:99] (!out_valid ##1 out_valid)
    )
    else $fatal(1, "[ERROR]: Latency is over 100 cycles (spec 9).");

    // Stimulus rules, they check the driver

    IN_MODE_KNOWN: assert property(
        @(posedge clk) disable iff(!rst_n)
        in_mode_valid |-> !$isunknown(in_mode)
    )
    else $fatal(1, "[ERROR]: in_mode is X/Z while in_mode_valid is high.");

    IN_DATA_KNOWN: assert property(
        @(posedge clk) disable iff(!rst_n)
        in_data_valid |-> !$isunknown(in_data)
    )
    else $fatal(1, "[ERROR]: in_data is X/Z while in_data_valid is high.");

    IN_DATA_128_CYCLES: assert property(
        @(posedge clk) disable iff(!rst_n)
        !in_data_valid ##1 in_data_valid |-> in_data_valid[*128] ##1 !in_data_valid
    )
    else $fatal(1, "[ERROR]: in_data_valid must be high for exactly 128 consecutive cycles.");

    IN_MODE_TO_DATA_GAP: assert property(
        @(posedge clk) disable iff(!rst_n)
        in_mode_valid ##1 !in_mode_valid |-> !in_data_valid[*2:4] ##1 in_data_valid
    )
    else $fatal(1, "[ERROR]: in_data_valid must start 2~4 cycles after in_mode_valid falls (spec 5).");

    OUT_TO_NEXT_GAP: assert property(
        @(posedge clk) disable iff(!rst_n)
        out_valid ##1 !out_valid |-> !in_mode_valid[*2]
    )
    else $fatal(1, "[ERROR]: The next in_mode_valid must not come within 2 cycles after out_valid falls (spec 6).");

endmodule
