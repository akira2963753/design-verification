/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/
`timescale 1ns/10ps

`ifdef RTL
    `define CYCLE_TIME 15.0
`endif
`ifdef GATE
    `define CYCLE_TIME 15.0
`endif

module PATTERN(

    //=============================================================
    //                          Input Ports
    //=============================================================
    input [6:0] chain_num,
    input [2:0] elim_color,
    input [8:0] elim_cnt,
    input out_valid,

    //=============================================================
    //                        Output Ports
    //=============================================================
    output logic clk,
    output logic rst_n,
    output logic in_valid,
    output logic [7:0]  ring_len,
    output logic [2:0]  in_color,
    output logic shot_valid,
    output logic [2:0]  shot_color,
    output logic [7:0]  shot_pos

);

    //=============================================================
    //                          Integer
    //=============================================================
    int fd, pat_num;
    int pat_cnt, shot_cnt; // current pattern / shot index for debug message
    int out_idx; // current cascade level being checked
    int lat, total_latency;

    //=============================================================
    //      Reference Function Coding By Claude Code Opus 5.5
    //=============================================================

    bit [2:0] gold_ring[$]; // index 0 of the queue is always logical index 0
    int gold_chain;
    bit [2:0] gold_color[$]; // one entry per cascade level, (0, 0) when no elimination
    bit [8:0] gold_cnt[$];

    // find the maximal same-color segment containing idx (wrap-around, bounded by ring size)
    function automatic void find_seg(input int idx, output int start, output int len);

        int m, left, right;
        m = gold_ring.size();
        left = 0;
        right = 0;
        while(left < m - 1 && gold_ring[(idx - left - 1 + m) % m] == gold_ring[idx]) left++;
        while(left + right < m - 1 && gold_ring[(idx + right + 1) % m] == gold_ring[idx]) right++;
        start = (idx - left + m) % m;
        len = left + right + 1;

    endfunction

    // remove the segment and return the right side index of the new junction
    function automatic int remove_seg(input int start, input int len);

        int m;
        m = gold_ring.size();
        if(len == m) begin
            gold_ring.delete();
            return 0;
        end
        else if(start + len <= m) begin
            // no wrap: logical index 0 survives or the bead after the segment shifts to index 0
            repeat(len) gold_ring.delete(start);
            return start % gold_ring.size();
        end
        else begin
            // wrap: index 0 is eliminated, the first survivor after the segment becomes index 0
            repeat(m - start) void'(gold_ring.pop_back());
            repeat(start + len - m) void'(gold_ring.pop_front());
            return 0;
        end

    endfunction

    function automatic void ref_model(input bit [2:0] color, input int pos);

        int idx, start, len, left, right;
        gold_chain = 0;
        gold_color.delete();
        gold_cnt.delete();

        if(gold_ring.size() == 0) gold_ring.push_back(color); // empty ring: shot_pos is ignored
        else begin
            gold_ring.insert(pos + 1, color);
            idx = pos + 1;
            find_seg(idx, start, len);
            while(len >= 3) begin
                gold_chain++;
                gold_color.push_back(gold_ring[idx]);
                gold_cnt.push_back(len);
                right = remove_seg(start, len);
                if(gold_ring.size() < 3) break;
                left = (right - 1 + gold_ring.size()) % gold_ring.size();
                if(gold_ring[left] != gold_ring[right]) break;
                idx = right;
                find_seg(idx, start, len);
            end
        end

        if(gold_chain == 0) begin
            gold_color.push_back(0);
            gold_cnt.push_back(0);
        end

    endfunction

    //=============================================================
    //                      Generate Clock
    //=============================================================

    initial clk = 0;
    always #(`CYCLE_TIME / 2.0) clk = ~clk;

    //=============================================================
    //                      Read Function
    //=============================================================

    function automatic int read_int();

        int val;
        if($fscanf(fd, "%d", val) != 1) begin
            $display("=============================================================");
            $display("      [FAILED] Pattern Input File Format Mismatch / EOF      ");
            $display("=============================================================");
            $fatal(1);
        end
        return val;

    endfunction

    //=============================================================
    //                      Reset Task
    //=============================================================

    task reset_task();

        in_valid = 0;
        ring_len = 'd0;
        in_color = 'd0;
        shot_valid = 'd0;
        shot_color = 'd0;
        shot_pos = 'd0;

        force clk = 0;
        rst_n = 1;
        #(`CYCLE_TIME) rst_n = 0;

        // SPEC 4 checks outputs 100 ns after rst_n pulled low
        for(int i = 0; i < 100 ; i++) begin
            #1; // let the async reset take effect before checking
            CHECK_RESET_OUT: assert (chain_num === 'd0 && elim_color === 'd0 && elim_cnt === 'd0 && out_valid === 'd0)
            else begin
                $display("=============================================================");
                $display("   [SPEC-4 FAILED] All output signal must be zero when reset  ");
                $display("=============================================================");
                $fatal(1);
            end
        end

        rst_n = 1;
        #(`CYCLE_TIME) release clk;
        @(negedge clk); // align the negative edge

    endtask

    //=============================================================
    //                    Write And Check Task
    //=============================================================

    task automatic write_and_check_task();

        int len, num;
        bit spec5_case, spec6_case;

        len = read_int(); // get the ring len
        num = read_int(); // get the shot num
        pat_cnt++;
        shot_cnt = 0;
        gold_ring.delete();

        //=============================================================
        //                    Ring Loading Phase
        //=============================================================

        for(int i = 0; i < len; i++) begin
            in_valid = 1'b1;
            if(i==0) ring_len = len;
            else ring_len = $urandom_range(128, 4); // don't care
            in_color = read_int();
            gold_ring.push_back(in_color);  // push in golden queue
            @(negedge clk);
        end

        in_valid = 1'b0;
        ring_len = $urandom_range(128, 4); // don't care
        in_color = $urandom_range(7, 0); // don't care
        repeat($urandom_range(1, 4)) @(negedge clk); // 1 ~ 4 negedge after the in_valid pull down

        //=============================================================
        //                    Ring Shooting Phase
        //=============================================================

        for(int i = 0; i < num; i++) begin
            shot_cnt++;
            shot_valid = 1'b1;
            shot_color = read_int();
            shot_pos = read_int();
            ref_model(shot_color, shot_pos);
            @(negedge clk);
            shot_valid = 1'b0;
            shot_color = $urandom_range(7, 0); // don't care
            shot_pos = $urandom_range(255, 0); // don't care

            // lat = number of posedge from the one sampling shot_valid to the one out_valid falls
            lat = 0;
            out_idx = 0;
            while(out_valid !== 1'b1) begin
                
                if(lat == 1000) begin
                    $display("=============================================================");
                    $display(" [SPEC-7 FAILED] Time out, Your latency over the 1000 cycles ");
                    $display("=============================================================");
                    $fatal(1);
                end

                @(negedge clk);
                lat++;
            end

            while(out_valid === 1'b1) begin

                if(lat == 1000) begin
                    $display("=============================================================");
                    $display(" [SPEC-7 FAILED] Time out, Your latency over the 1000 cycles ");
                    $display("=============================================================");
                    $fatal(1);
                end                

                spec5_case = (chain_num === 7'd0) && (elim_color !== 3'd0 || elim_cnt !== 9'd0);
                spec6_case = (lat == 0); // out_valid already high at the 1st negedge, overlapped with shot_valid
                if(!spec5_case && !spec6_case && out_idx < gold_color.size()) begin
                    if(out_idx == 0 && chain_num !== gold_chain) spec8_task();
                    else if(elim_color !== gold_color[out_idx] || elim_cnt !== gold_cnt[out_idx]) spec8_task();
                end
                out_idx++;
                @(negedge clk);
                lat++;
            end

            // Accumulate the total latency 
            total_latency += lat;

            // already at the 1st negedge after the out_valid pull down, total 1 ~ 4 negedge
            repeat($urandom_range(0, 3)) @(negedge clk);
        end

    endtask

    //=============================================================
    //                        Display Task
    //=============================================================

    task spec8_task();

        $display("=============================================================");
        $display("                    [SPEC-8 FAILED]                          ");
        $display("    Pattern NO.%0d, Shot NO.%0d, Level %0d", pat_cnt, shot_cnt, out_idx + 1);
        $display("    Golden: chain_num = %0d, elim_color = %0d, elim_cnt = %0d", gold_chain, gold_color[out_idx], gold_cnt[out_idx]);
        $display("    Yours : chain_num = %0d, elim_color = %0d, elim_cnt = %0d", chain_num, elim_color, elim_cnt);
        $display("=============================================================");
        $fatal(1);

    endtask

    task pass_task();

        $display("=============================================================");
        $display("                     Congratulations!                        ");
        $display("              Total execution latency = %0d", total_latency   );
        $display("=============================================================");

    endtask

    //=============================================================
    //                        Main Flow
    //=============================================================
    initial begin
        // open the input.txt (simulation runs under 01_RTL)
        fd = $fopen("../00_TESTBED/input.txt", "r");
        if(fd == 0) begin
            $display("=============================================================");
            $display("         [FAILED] Cannot Open the Pattern Input File         ");
            $display("=============================================================");
            $fatal(1);
        end

        // get the number of pattern
        pat_num = read_int();

        reset_task();

        for(int i = 0; i < pat_num; i++) write_and_check_task();

        pass_task();
        $fclose(fd);
        $finish;
    end

    //=============================================================
    //                  SystemVerilog Assertion
    //=============================================================

    // SPEC-5
    CHECK_OUT: assert property(
        @(posedge clk) disable iff(!rst_n) 
        (!out_valid) |-> (chain_num == 'd0 && elim_color == 'd0 && elim_cnt == 'd0)) 
        else begin
            $display("=============================================================");
            $display(" [SPEC-5 FAILED] output signals must be 0 when out_valid low ");
            $display("=============================================================");        
            $fatal(1);
        end

    // SPEC-5
    CHECK_ELIM: assert property(
        @(posedge clk) disable iff(!rst_n)
        (out_valid && chain_num == 'd0) |-> (elim_color == 'd0 && elim_cnt == 'd0))
        else begin
            $display("=============================================================");
            $display("     [SPEC-5 FAILED] elim_color and elim_cnt must be 0       ");
            $display("         when out_valid high and chain_num is zero           ");
            $display("=============================================================");        
            $fatal(1);
        end

    // SPEC-6
    CHECK_VALID: assert property(
        @(posedge clk) disable iff(!rst_n)
        (in_valid || shot_valid) |-> !out_valid)
        else begin
            $display("=============================================================");
            $display("           [SPEC-6 FAILED] out_valid must be low             ");
            $display("             when in_valid or shot_valid high                ");
            $display("=============================================================");        
            $fatal(1);
        end


    // SPEC-9
    CHECK_CHAIN_NUM: assert property(
        @(posedge clk) disable iff(!rst_n)
        (out_valid && $past(out_valid)) |-> $stable(chain_num))
        else begin
            $display("=============================================================");
            $display(" [SPEC-9 FAILED] chain_num must be stable when out_valid high");
            $display("=============================================================");        
            $fatal(1);
        end

    property p_out_valid_len;
        int n;
        @(posedge clk) disable iff(!rst_n)
        ($rose(out_valid), n = (chain_num == 0)? 1 : chain_num) |->
        (out_valid, n = n - 1)[*1:$] ##1 (!out_valid && n == 0);
    endproperty

    CHECK_OUT_VALID_STABLE: assert property(p_out_valid_len)
        else begin
            $display("=============================================================");
            $display("   [SPEC-9 FAILED] out_valid length must match chain_num     ");
            $display("=============================================================");
            $fatal(1);
        end




endmodule
