/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through PATTERN.sv only, not again in file.f.
`include "vif.sv"
`include "trans.sv"

`include "generator.sv"
// input mailbox #(txn) gen2drv [generate constraint-random input to driver]
// input unsigned pattern_num

`include "driver.sv"
// input virtual vif.driver_mp drv_if [driver interface]
// input mailbox #(txn) gen2drv, [receive the input data from generator]
// input int unsigned pattern_num

`include "monitor.sv"
// input virtual vif.monitor_mp mon_if [monitor interface]
// input mailbox #(mon_txn) mon2scb [monitor the i/o data and send to scoreboard]
// input int unsigned pattern_num

`include "scoreboard.sv"
// input mailbox #(mon_txn) mon2scb [receive the i/o data from monitor]
// input int unsigned pattern_num

module PATTERN (
    output logic clk,
    output wire [95:0] Inst_seq_I,
    output wire [47:0] Inst_latency_I,
    input wire [23:0] Inst_order_O,
    input wire [8:0] Ex_cycle
);

    //=============================================================
    //                       Configuration
    //=============================================================

    localparam int unsigned PATTERN_NUM = 1000;
    localparam realtime CLK_PERIOD = 50.0;
    localparam realtime TIMEOUT = (PATTERN_NUM + 10.0) * CLK_PERIOD * 10.0;

    //=============================================================
    //                    Interface Connections
    //=============================================================

    vif tb_if (.clk(clk));

    // Preserve TESTBED's scalar port connections and the driver's ownership.
    assign Inst_seq_I = tb_if.Inst_seq_I;
    assign Inst_latency_I = tb_if.Inst_latency_I;
    assign tb_if.Inst_order_O = Inst_order_O;
    assign tb_if.Ex_cycle = Ex_cycle;

    //=============================================================
    //                     Environment Objects
    //=============================================================

    // 實例化四個 component 以及兩個 mailbox
    mailbox #(txn) gen2drv;     // generator to driver
    mailbox #(mon_txn) mon2scb; // monitor to scoreboard
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    //=============================================================
    //                            Clock
    //=============================================================

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    //=============================================================
    //                           Main Flow
    //=============================================================

    initial begin: MAIN_FLOW
        clk = 1'b0;
        gen2drv = new();
        mon2scb = new();
        gen = new(gen2drv, PATTERN_NUM);
        drv = new(tb_if.driver_mp, gen2drv, PATTERN_NUM);
        mon = new(tb_if.monitor_mp, mon2scb, PATTERN_NUM);
        scb = new(mon2scb, PATTERN_NUM);

        $display("================================================================");
        $display("                  OISS Environment Started");
        $display("Patterns = %0d, clock period = %0.1f ns",   PATTERN_NUM, CLK_PERIOD);
        $display("================================================================");

        // sample_valid starts low in vif. All components start before the
        // first posedge; the first valid sample is on the following posedge.
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join

        @(negedge clk);

        $display("================================================================");
        $display("          OISS Environment Completed: %0d Patterns Passed", scb.checked_num);
        $display("                  Checked Property: Ex_cycle");
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
endmodule

