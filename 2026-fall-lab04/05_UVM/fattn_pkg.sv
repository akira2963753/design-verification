/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    fattn_pkg.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       UVM package
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Every UVM class lives in this package, the include order is the dependency order.
// dv_pkg and vif are compiled before it through file.f.
package fattn_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import dv_pkg::*;

    `include "txn.sv"
    // class txn [uvm_sequence_item, constraint-random Q / K / V / W]
    // class k_max_txn [every K +/- 128 ~ 255, factory override target]
    // class mon_txn [sampled inputs and 64 outputs]

    `include "seq.sv"
    // class rand_seq [pat_num txn through the factory]

    `include "driver.sv"
    // seq_item_port [txn from the sequencer], virtual vif.drv from uvm_config_db

    `include "monitor.sv"
    // uvm_analysis_port #(mon_txn) ap [whole patterns], virtual vif.mon from uvm_config_db

    `include "agent.sv"
    // txn_sequencer + driver + monitor

    `include "scoreboard.sv"
    // uvm_analysis_imp #(mon_txn) imp [whole patterns from monitor], ref model and check

    `include "env.sv"
    // agent + scoreboard, monitor ap -> scoreboard imp

    `include "test.sv"
    // base_test [random], k_max_test [factory override txn -> k_max_txn]

endpackage
