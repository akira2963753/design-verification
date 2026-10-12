/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    agent.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       agent
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// The sequencer needs no code of its own, it only arbitrates sequences and hands txn to the driver
typedef uvm_sequencer #(txn) txn_sequencer;

// Everything of one interface: sequencer + driver drive it, monitor watches it
class agent extends uvm_agent;

    `uvm_component_utils(agent)

    txn_sequencer sqr;
    driver drv;
    monitor mon;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    //=============================================================
    //                             PHASE
    //=============================================================

    // Passive agent (is_active = UVM_PASSIVE) builds the monitor only, e.g. to reuse it at chip level
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = monitor::type_id::create("mon", this);
        if(get_is_active() == UVM_ACTIVE) begin
            sqr = txn_sequencer::type_id::create("sqr", this);
            drv = driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(get_is_active() == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass
