/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    env.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       env
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Compile these definitions through env.sv only, not again in file.f.
`include "vif.sv"
`include "trans.sv"
// class txn [constraint-random LLR], class mon_txn [pin-level snapshot]

`include "generator.sv"
// input uint pat_num
// input mailbox #(txn) gen2drv [constraint-random txn to driver]
// input string path [generator matrix file]

`include "driver.sv"
// input virtual vif.drv vif [driver interface]
// input uint pat_num, time_out
// input mailbox #(txn) gen2drv [txn from generator]

`include "monitor.sv"
// input virtual vif.mon vif [monitor interface]
// input uint pat_num
// input mailbox #(mon_txn) mon2scb [sampled i/o to scoreboard]

`include "ref_model.sv"
// spec-level decoder, used by scoreboard

`include "scoreboard.sv"
// input uint pat_num
// input mailbox #(mon_txn) mon2scb [sampled i/o from monitor]

module env (
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

    localparam uint PAT_NUM = 1000;
    localparam uint MBX_SIZE = 200;   // bounded mailbox depth
    localparam uint TIME_OUT = 1000;  // driver hang guard in cycles
    localparam realtime CLK_PERIOD = 15.0;
    localparam string G_PATH = "G_128_64.txt";
    // mode 1 + gap 4 + data 128 + latency 100 + output 128 + gap 4 < 400 cycles
    localparam realtime TIMEOUT = (PAT_NUM + 10.0) * 400.0 * CLK_PERIOD;

    //=============================================================
    //                    Interface Connections
    //=============================================================

    vif tb_if(.clk(clk));

    // Driver owns the inputs through drv_cb, env owns rst_n
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

    mailbox #(txn) gen2drv;        // generator to driver
    mailbox #(mon_txn) mon2scb;    // monitor to scoreboard

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
        gen2drv = new(MBX_SIZE);
        mon2scb = new(MBX_SIZE);
        gen = new(PAT_NUM, gen2drv, G_PATH);
        drv = new(tb_if.drv, PAT_NUM, TIME_OUT, gen2drv);
        mon = new(tb_if.mon, PAT_NUM, mon2scb);
        scb = new(PAT_NUM, mon2scb);

        $display("=============================================================");
        $display("                 LDPC Environment Started");
        $display("Patterns = %0d, clock period = %0.1f ns, mailbox = %0d", PAT_NUM, CLK_PERIOD, MBX_SIZE);
        $display("=============================================================");

        drive_reset();

        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join

        @(negedge clk);

        scb.report();
        $display("=============================================================");
        $display("                 LDPC Environment Completed");
        $display("                 Congratulations! All Pass");
        $display("=============================================================");
        $finish;
    end

    //=============================================================
    //                           Watchdog
    //=============================================================

    initial begin : WATCHDOG
        #(TIMEOUT);
        $display("=============================================================");
        $display("                 Environment Timeout ! ! !");
        $display("=============================================================");
        $display("Timeout at %0t, expected patterns = %0d", $time, PAT_NUM);
        if(scb != null) $display("Pass patterns = %0d", scb.pass_num);
        if(gen2drv != null) $display("gen2drv pending = %0d", gen2drv.num());
        if(mon2scb != null) $display("mon2scb pending = %0d", mon2scb.num());
        $fatal(1);
    end

    //=============================================================
    //                   SystemVerilog Assertion
    //=============================================================
    // Property Name: assert property(condition) <pass event> else <fail event>

    // clk is forced during drive_reset, so spec 3 is sampled at the rst_n rising edge
    RESET_OUT_ZERO: assert property(
        @(posedge rst_n)
        $time > 0 |-> (!out_valid && !out_warn && out_data == 0)
    )
    else $fatal(1, "[ERROR]: All outputs must be 0 after reset is asserted (spec 3).");

endmodule
