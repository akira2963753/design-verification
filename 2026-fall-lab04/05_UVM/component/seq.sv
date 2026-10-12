/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    seq.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       sequence
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Takes the place of the 04_DV generator, the sequencer between it and the driver replaces gen2drv
class rand_seq extends uvm_sequence #(txn);

    `uvm_object_utils(rand_seq)

    uint pat_num = 1;       // set by the test before start()

    function new(string name = "rand_seq");
        super.new(name);
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    virtual task body();
        txn t;
        for(int i = 0; i < pat_num; i++) begin
            // Through the factory, a test override turns every txn into k_max_txn here
            t = txn::type_id::create($sformatf("t_%0d", i));

            // start_item() waits until the driver asks for an item, randomize as late as possible
            start_item(t);
            if(!t.randomize()) `uvm_fatal("SEQ", $sformatf("Randomize failed at pattern %0d", i))

            // Returns after the driver calls item_done()
            finish_item(t);
        end
    endtask

endclass
