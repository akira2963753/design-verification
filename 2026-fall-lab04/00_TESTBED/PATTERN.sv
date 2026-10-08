/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      2026 FALL NYCU IC LAB, LAB04
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`define CYCLE_TIME 50.0

module PATTERN (

    //=============================================================
    //                          Output Ports
    //=============================================================
    output logic clk,
    output logic rst_n,
    output logic in_valid,
    output logic [31:0] K,
    output logic [31:0] Q,
    output logic [31:0] V,
    output logic [31:0] out_weight,

    //=============================================================
    //                          Input Ports
    //=============================================================
    input out_valid,
    input [31:0] out
);

    //=============================================================
    //                      Parameter & Integer
    //=============================================================
    parameter CYCLE = `CYCLE_TIME;
    // parameter inst_sig_width = 23;
    // parameter inst_exp_width = 8;
    // parameter inst_ieee_compliance = 0;
    // parameter inst_arch_type = 0;
    // parameter inst_arch = 0;
    
    localparam real SQRT2 = $bitstoshortreal(32'h3FB504F3);
    localparam real ERR_TOL = 1e-6;                   
    localparam int  MAX_LAT = 1000;                          

    int fd;
    int pat_num;
    int lat, total_lat;

    real q [16][4];
    real k [16][4];
    real v [16][4];
    real w [4][4];
    real golden [64];

    //=============================================================
    //                            Clock
    //=============================================================

    always #(`CYCLE_TIME / 2.0) clk = ~clk;

    //=============================================================
    //                         Reset Task
    //=============================================================

    task reset();

        force clk = 0;
        rst_n = 1;
        in_valid = 0;
        K = 'd0;
        Q = 'd0;
        V = 'd0;
        out_weight = 'd0;

        #10 rst_n = 0;

        // SPEC-4 checks outputs while rst_n is low (clk is still forced, so async reset only)
        for(int i = 0; i < 90; i++) begin
            #10; // let the async reset take effect before checking
            CHECK_RESET_OUT: assert (out_valid === 1'b0 && out === 32'd0)
            else begin
                $display("=============================================================");
                $display("   [SPEC-4 FAILED] All output signals must be zero when reset");
                $display("=============================================================");
                $fatal(1);
            end
        end

        rst_n = 1;
        release clk;

        @(negedge clk);
    endtask

    //=============================================================
    //                       Read Function
    //=============================================================
    function automatic logic [31:0] read_data();

        logic [31:0] val;
        if($fscanf(fd, "%h", val) != 1) begin
            $display("=============================================================");
            $display("      [FAILED] Pattern Input File Format Mismatch / EOF      ");
            $display("=============================================================");
            $fatal(1);
        end
        return val;

    endfunction

    //=============================================================
    //                       Write Task
    //=============================================================

    task driver();
        int r, c;

        in_valid = 1;
        for(int i = 0; i < 64; i++) begin

            // Data to design under test
            Q = read_data();
            K = read_data();
            V = read_data();
            out_weight = (i < 16)? read_data() : 'dx;

            // Data to reference model
            r = i / 4;
            c = i % 4;
            q[r][c] = $bitstoshortreal(Q);
            k[r][c] = $bitstoshortreal(K);
            v[r][c] = $bitstoshortreal(V);
            if(i < 16) w[r][c] = $bitstoshortreal(out_weight);

            @(negedge clk);
        end
        in_valid = 0;
        Q = 'dx;
        K = 'dx;
        V = 'dx;

    endtask

    //=============================================================
    //                       Main Flow
    //=============================================================

    initial begin
        fd = $fopen("../00_TESTBED/input.txt", "r");
        if(fd == 0) begin
            $display("=============================================================");
            $display("         [FAILED] Cannot Open the Pattern Input File         ");
            $display("=============================================================");
            $fatal(1);
        end
        
        // ignore the return value
        void'($fscanf(fd, "%d", pat_num));

        reset();

        total_lat = 0;
        for(int i = 0; i < pat_num; i++) begin
            driver();
            ref_model();
            check(i);
            $display(" [PATTERN %0d] PASS, latency = %0d", i, lat);

            // already at the 1st negedge after out_valid pulled down, total 2 ~ 4 negedge
            if(i != pat_num - 1) repeat($urandom_range(1, 3)) @(negedge clk);
        end

        $display("=============================================================");
        $display("                     Congratulations!                        ");
        $display("              Total execution latency = %0d", total_lat       );
        $display("=============================================================");

        $fclose(fd);
        $finish;
    end

    //=============================================================
    //                       Check Task
    //=============================================================

    task check(input int pat);

        real dut, err;

        // lat = number of negedge from in_valid pulled down to the first out_valid
        lat = 0;
        while(out_valid !== 1'b1) begin

            if(lat == MAX_LAT) begin
                $display("=============================================================");
                $display(" [SPEC-6 FAILED] Time out, Your latency over the 1000 cycles ");
                $display("=============================================================");
                $fatal(1);
            end

            @(negedge clk);
            lat++;
        end

        // 64 outputs in raster order
        for(int i = 0; i < 64; i++) begin

            dut = $bitstoshortreal(out);
            err = dut - golden[i];
            if(err < 0) err = -err; // turn to positive

            if($isunknown(out)) begin
                $display("=============================================================");
                $display("          [SPEC-2 FAILED] Your output data is unknown        ");
                $display("=============================================================");
                $fatal(1);               
            end
            else if(err >= ERR_TOL) begin
                $display("=============================================================");
                $display("                    [SPEC-2 FAILED]                          ");
                $display("    Pattern NO.%0d, Output NO.%0d (token %0d, dim %0d)", pat, i, i / 4, i % 4);
                $display("    Golden: %.10e", golden[i]);
                $display("    Yours : %.10e (32'h%08h)", dut, out);
                $display("    Error : %.3e (tolerance %.0e)", err, ERR_TOL);
                $display("=============================================================");
                $fatal(1);
            end

            @(negedge clk);
        end

        total_lat += lat;

    endtask

    //=============================================================
    //                   Reference Function
    //=============================================================

    // Standard (non-tiled) multi-head attention in double precision
    function automatic void ref_model();

        real s [16];        // one row temp of scores
        real head [16][4];  // concat of head 1 (dim 0,1) and head 2 (dim 2,3)
        real mx, sum, acc;  

        for(int h = 0; h < 2; h++) begin: head_loop
            for(int i = 0; i < 16; i++) begin: q_row_loop
                
                mx = -1.0e300; // init the row max to a very small number
                sum = 0.0;
                
                // Calculate the attention score
                for(int j = 0; j < 16; j++) begin
                    s[j] = (q[i][2*h] * k[j][2*h] + q[i][2*h+1] * k[j][2*h+1]) / SQRT2;
                    if(s[j] > mx) mx = s[j];
                end

                // Calculate the two parts of softmax
                for(int j = 0; j < 16; j++) begin
                    s[j] = $exp(s[j] - mx);
                    sum += s[j];
                end

                // Add V
                for(int d = 0; d < 2; d++) begin: v_col_loop
                    acc = 0.0;

                    // accumulate
                    for(int j = 0; j < 16; j++) acc += s[j] * v[j][2*h+d];
                    head[i][2*h+d] = acc / sum;
                end

            end
        end

        for(int t = 0; t < 16; t++) begin: head_row_loop
            for(int o = 0; o < 4; o++) begin: head_col_loop
                acc = 0.0;

                // accumulate
                for(int c = 0; c < 4; c++) acc += head[t][c] * w[o][c];
                golden[t*4+o] = acc;
            end
        end

    endfunction

    //=============================================================
    //                  SystemVerilog Assertion
    //=============================================================

    // SPEC-5 / IO-7
    CHECK_OUT: assert property(
        @(posedge clk) disable iff(!rst_n) !out_valid |-> out == 'd0)
        else begin
            $display("=============================================================");
            $display("     [SPEC-5 FAILED] out must be 0 when out_valid is low     ");
            $display("=============================================================");
            $fatal(1);
        end

    // IO-8
    CHECK_VALID: assert property(
        @(posedge clk) disable iff(!rst_n) in_valid |-> !out_valid)
        else begin
            $display("=============================================================");
            $display("   [IO-8 FAILED] out_valid cannot overlap with in_valid      ");
            $display("=============================================================");
            $fatal(1);
        end

    // IO-6
    CHECK_OUT_VALID_LEN: assert property(
        @(posedge clk) disable iff(!rst_n) $rose(out_valid) |-> out_valid[*64] ##1 !out_valid)
        else begin
            $display("=============================================================");
            $display("  [IO-6 FAILED] out_valid must be high for 64 cycles exactly ");
            $display("=============================================================");
            $fatal(1);
        end

endmodule

