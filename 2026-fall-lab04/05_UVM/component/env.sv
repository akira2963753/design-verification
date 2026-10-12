/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    env.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       environment
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class env extends uvm_env;

    `uvm_component_utils(env)

    agent agt;
    scoreboard scb;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    //=============================================================
    //                             PHASE
    //=============================================================

    // build_phase runs top-down: the test builds env, env builds agent, agent builds driver ...
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = agent::type_id::create("agt", this);
        scb = scoreboard::type_id::create("scb", this);
    endfunction

    // connect_phase runs after every component exists, replaces passing mailboxes through new()
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.imp);
    endfunction

endclass
