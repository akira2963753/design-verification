/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       test
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Picked at runtime by +UVM_TESTNAME=<class name>, one simv runs every test
class base_test extends uvm_test;

    `uvm_component_utils(base_test)

    env m_env;
    uint pat_num = 500;     // patterns, +PAT_NUM=<n>

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    //=============================================================
    //                             PHASE
    //=============================================================

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("PAT_NUM=%d", pat_num));

        // Relative path from this test: uvm_test_top.env.scb
        uvm_config_db #(uint)::set(this, "env.scb", "pat_num", pat_num);
        m_env = env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // The simulation keeps running while any objection is raised
    virtual task run_phase(uvm_phase phase);
        rand_seq seq;

        phase.raise_objection(this);

        // The monitor writes the last pattern at the same negedge the driver calls item_done(),
        // the drain time lets the scoreboard take it before the run phase ends
        phase.phase_done.set_drain_time(this, 1000ns);

        seq = rand_seq::type_id::create("seq");
        seq.pat_num = pat_num;
        seq.start(m_env.agt.sqr);       // returns after the last item_done()

        phase.drop_objection(this);
    endtask

    // A uvm_fatal ends the simulation before this phase, only UVM_ERROR is counted here
    virtual function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        super.report_phase(phase);
        svr = uvm_report_server::get_server();

        $display("=============================================================");
        if(svr.get_severity_count(UVM_ERROR) == 0) begin
            $display("                F_ATTN UVM Test Completed");
            $display("                Congratulations! All Pass");
        end
        else begin
            $display("                F_ATTN UVM Test FAILED");
            $display("                UVM_ERROR count = %0d", svr.get_severity_count(UVM_ERROR));
        end
        $display("=============================================================");
    endfunction

endclass

//=============================================================
//                        DIRECTED TEST
//=============================================================

// Same env and sequence, only the txn type is replaced through the factory
class k_max_test extends base_test;

    `uvm_component_utils(k_max_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // The override must be set before the sequence creates any txn
    virtual function void build_phase(uvm_phase phase);
        txn::type_id::set_type_override(k_max_txn::get_type());
        super.build_phase(phase);
    endfunction

endclass
