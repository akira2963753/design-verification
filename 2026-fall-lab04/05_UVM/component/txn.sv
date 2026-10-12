/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    txn.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       transaction
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

class txn extends uvm_sequence_item;

    // Registers txn to the factory and builds type_id / create(), txn::type_id::create() goes through overrides
    `uvm_object_utils(txn)

    rand fp32_t q [64];
    rand fp32_t k [64];
    rand fp32_t v [64];
    rand fp32_t w [16];

    // K Range = +/- 0.5 ~ 255.0
    constraint c_k {
        foreach(k[i]) {
            k[i].exp dist {
                EXP_0P5 :/ 35,
                [EXP_0P5+1 : EXP_255-1] :/ 30,
                EXP_255 :/ 35
            };

            if(k[i].exp == EXP_255) k[i].frac inside {[23'd0 : FRAC_255]};

        }
    }

    // Q, V, W Range = +/- 0 ~ 0.5
    constraint c_qvw {
        foreach(q[i]) {
            q[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(q[i].exp == 8'd0) q[i].frac == 23'd0;
            if(q[i].exp == EXP_0P5) q[i].frac == FRAC_0P5;
        }
        foreach(v[i]) {
            v[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(v[i].exp == 8'd0) v[i].frac == 23'd0;
            if(v[i].exp == EXP_0P5) v[i].frac == FRAC_0P5;
        }
        foreach(w[i]) {
            w[i].exp inside {8'd0, [EXP_MIN : EXP_0P5]};
            if(w[i].exp == 8'd0) w[i].frac == 23'd0;
            if(w[i].exp == EXP_0P5) w[i].frac == FRAC_0P5;
        }
    }

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    // uvm_object takes a name only, no parent
    function new(string name = "txn");
        super.new(name);
    endfunction

    //=============================================================
    //                             COPY
    //=============================================================

    // Data only, the factory builds the object: clone() = create() + copy() -> do_copy()
    virtual function void do_copy(uvm_object rhs);
        txn rhs_;
        if(!$cast(rhs_, rhs)) `uvm_fatal("TXN", "do_copy: rhs is not a txn")
        super.do_copy(rhs);
        q = rhs_.q;
        k = rhs_.k;
        v = rhs_.v;
        w = rhs_.w;
    endfunction

    //=============================================================
    //                            PRINT
    //=============================================================

    function string mat2str(string name, fp32_t a[], int rows);
        string s;
        s = $sformatf("=========================== %s (%0dx4) ==================================\n", name, rows);

        for(int t = 0; t < rows; t++) begin
            s = {s, $sformatf("[%2d] ", t)};
            for(int d = 0; d < 4; d++) s = {s, $sformatf("%h(%11.4e) ", a[t*4 + d], fp2r(a[t*4 + d]))};
            s = {s, "\n"};
        end
        return s;
    endfunction

    virtual function string convert2string();
        return {mat2str("Q", q, 16),
                mat2str("K", k, 16),
                mat2str("V", v, 16),
                mat2str("W", w, 4)};
    endfunction

endclass

//=============================================================
//                    DIRECTED TRANSACTION
//=============================================================

// Every K is +/- 128.0 ~ 255.0, the largest attention scores
class k_max_txn extends txn;

    // The macro also builds create(), no hand-written create() to forget
    `uvm_object_utils(k_max_txn)

    constraint c_k_max {
        foreach(k[i]) k[i].exp == EXP_255;
    }

    function new(string name = "k_max_txn");
        super.new(name);
    endfunction

endclass

//=============================================================
//                    MONITOR TRANSACTION
//=============================================================

// One mon_txn per pattern, the driver already checks 64 in_valid / out_valid cycles
class mon_txn extends uvm_sequence_item;

    `uvm_object_utils(mon_txn)

    logic [31:0] q[64];     // one word per in_valid cycle
    logic [31:0] k[64];
    logic [31:0] v[64];
    logic [31:0] w[16];     // out_weight of the first 16 in_valid cycles only
    logic [31:0] out[64];   // one word per out_valid cycle
    uint lat;               // negedges from in_valid pulled down to the 1st out_valid, same as PATTERN

    function new(string name = "mon_txn");
        super.new(name);
    endfunction

endclass
