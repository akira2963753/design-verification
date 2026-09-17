/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Scoreboard and Reference Model DPI
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

//=============================================================
//                     Reference Model DPI
//=============================================================

package oiss_ref_pkg;
    import "DPI-C" function int oiss_ref_cycle(
        input int unsigned seq0,
        input int unsigned seq1,
        input int unsigned seq2,
        input int unsigned lat0,
        input int unsigned lat1
    );

    function automatic int reference_cycle(
        input logic [95:0] inst_seq,
        input logic [47:0] inst_lat
    );
        if($isunknown({inst_seq, inst_lat})) return -1;
        return oiss_ref_cycle(
            inst_seq[31:0], inst_seq[63:32], inst_seq[95:64],
            inst_lat[31:0], {16'b0, inst_lat[47:32]}
        );
    endfunction
endpackage

class scoreboard;
    mailbox #(mon_txn) mon2scb;
    int unsigned pattern_num;
    int unsigned checked_num;

    //=============================================================
    //                         Constructor
    //=============================================================

    function new(
        input mailbox #(mon_txn) mon2scb,
        input int unsigned pattern_num
    );
        if(mon2scb == null) $fatal(1,
            {"================================================================\n",
            "                Scoreboard Mailbox is Null ! ! !\n",
            "================================================================"});

        this.mon2scb = mon2scb;
        this.pattern_num = pattern_num;
        this.checked_num = 0;
    endfunction

    //=============================================================
    //                       Diagnostic Output
    //=============================================================

    local function void stop_check(
        input string reason,
        input mon_txn tr,
        input int expected_cycle = -1
    );
        $display("================================================================");
        $display("                  Scoreboard Check Failed ! ! !");
        $display("Reason: %s", reason);
        if(tr != null) begin
            $display("TEST PATTERN [%0d]", tr.testcase);
            $display("Inst_seq_I     = %024h", tr.inst_seq);
            $display("Inst_latency_I = %012h", tr.inst_lat);
            $display("Inst_order_O   = %06h", tr.inst_order);
            $display("Actual cycle   = %0d (hex %03h)", tr.ex_cycle, tr.ex_cycle);
        end
        if(expected_cycle >= 0) $display("Expected cycle = %0d", expected_cycle);
        else $display("Expected cycle = unavailable");
        $fatal(1,
            {"================================================================\n",
            "                    Simulation Stopped ! ! !\n",
            "================================================================"});
    endfunction

    //=============================================================
    //                       Transaction Check
    //=============================================================

    function void check_one(input mon_txn tr);
        int expected_cycle;

        if(tr == null) begin
            stop_check("Null monitor transaction", tr);
            return;
        end
        if($isunknown({tr.inst_seq, tr.inst_lat})) begin
            stop_check("Sampled DUT input contains X/Z", tr);
            return;
        end
        if($isunknown(tr.ex_cycle)) begin
            stop_check("Sampled Ex_cycle contains X/Z", tr);
            return;
        end

        expected_cycle = oiss_ref_pkg::reference_cycle(tr.inst_seq, tr.inst_lat);
        if(expected_cycle < 8 || expected_cycle > 400) begin
            stop_check("Reference model rejected input or returned an invalid cycle", tr, expected_cycle);
            return;
        end
        if(int'(tr.ex_cycle) != expected_cycle) begin
            stop_check("Ex_cycle does not match the reference minimum", tr, expected_cycle);
            return;
        end

        // Instruction order correctness is outside this cycle-only checker.
        $display("TEST PATTERN [%0d] PASS: Ex_cycle = %0d", tr.testcase, expected_cycle);
    endfunction

    //=============================================================
    //                           Main Run
    //=============================================================

    task run();
        mon_txn tr;

        checked_num = 0;
        repeat(pattern_num) begin
            mon2scb.get(tr);
            check_one(tr);
            checked_num++;
        end

        $display("================================================================");
        $display("             All %0d Ex_cycle Checks Passed", checked_num);
        $display("================================================================");
        // PATTERN owns the global timeout and simulation termination.
    endtask
endclass
