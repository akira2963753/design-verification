/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      SV Practice, Problem 1
* Module:       test
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

module test;

    import sol_pkg::*;

    //=============================================================
    //                       Configuration
    //=============================================================

    string in_file = "testcase/input.txt";
    string out_file = "testcase/output.txt";
    int sel_case = 0;           // +CASE=<n>, 0 runs every case
    int show_max = 8;           // ranges printed per list in the detail

    //=============================================================
    //                            Type
    //=============================================================

    // Judge-side range, independent of the range_t written in sol.sv
    // Packed: an unpacked struct queue here crashes the VCS 2021.09 compiler
    typedef struct packed {
        logic [31:0] lo;
        logic [31:0] hi;
    } pair_t;

    //=============================================================
    //                          Variable
    //=============================================================

    int fd_in, fd_out;
    int case_num;
    int run_num, pass_num;
    int fail_case;              // first failed case, 0 = none

    //=============================================================
    //                          Function
    //=============================================================

    // One case block: "<n> <tag>" then n lines of "<lo> <hi>" in hex
    function automatic void read_block(int fd, output string tag, output pair_t p[$]);
        int n;
        pair_t x;
        void'($fscanf(fd, "%d %s", n, tag));
        repeat(n) begin
            void'($fscanf(fd, "%h %h", x.lo, x.hi));
            p.push_back(x);
        end
    endfunction

    function automatic string list_str(const ref pair_t p[$]);
        string s = "";
        int n = (p.size() < show_max)? p.size() : show_max;
        if(p.size() == 0) return "(empty)";
        for(int i = 0; i < n; i++) s = {s, $sformatf("[%08h, %08h] ", p[i].lo, p[i].hi)};
        if(p.size() > n) s = {s, $sformatf("... (+%0d more)", p.size() - n)};
        return s;
    endfunction

    // Index of the first mismatch, -1 when got equals exp
    function automatic int first_diff(const ref pair_t exp[$], const ref pair_t got[$]);
        int n = (exp.size() < got.size())? exp.size() : got.size();
        for(int i = 0; i < n; i++) begin
            if(got[i].lo !== exp[i].lo || got[i].hi !== exp[i].hi) return i;
        end
        return (exp.size() == got.size())? -1 : n;
    endfunction

    function automatic void show_detail(int d, const ref pair_t in_p[$], const ref pair_t exp_p[$], const ref pair_t got_p[$]);
        $display("    Input    : %s", list_str(in_p));
        $display("    Expected : %s", list_str(exp_p));
        $display("    Got      : %s", list_str(got_p));
        if(d < 0) return;
        if(d < exp_p.size() && d < got_p.size()) begin
            $display("    First diff at index %0d: expected [%08h, %08h], got [%08h, %08h]",
                     d, exp_p[d].lo, exp_p[d].hi, got_p[d].lo, got_p[d].hi);
        end
        else $display("    First diff at index %0d: expected size %0d, got size %0d", d, exp_p.size(), got_p.size());
    endfunction

    //=============================================================
    //                            Judge
    //=============================================================

    initial begin : JUDGE
        string tag, tag_exp;
        pair_t in_p[$], exp_p[$], got_p[$];
        pair_t x;
        range_q in_q, got_q;
        range_t r;
        int d;

        void'($value$plusargs("CASE=%d", sel_case));
        fd_in = $fopen(in_file, "r");
        fd_out = $fopen(out_file, "r");
        if(fd_in == 0 || fd_out == 0) $fatal(1, "[JUDGE] Cannot open %s or %s", in_file, out_file);
        void'($fscanf(fd_in, "%d", case_num));
        void'($fscanf(fd_out, "%d", case_num));
        if(sel_case < 0 || sel_case > case_num) $fatal(1, "[JUDGE] CASE=%0d out of range 1~%0d", sel_case, case_num);

        $display("=============================================================");
        $display("           Problem 1: Merge Intervals (%0d cases)", case_num);
        $display("=============================================================");

        for(int c = 1; c <= case_num; c++) begin
            in_p.delete();
            exp_p.delete();
            read_block(fd_in, tag, in_p);
            read_block(fd_out, tag_exp, exp_p);
            if(tag != tag_exp) $fatal(1, "[JUDGE] Case %0d: input.txt and output.txt out of sync", c);
            if(sel_case != 0 && c != sel_case) continue;

            // Partial line stays visible if the run is killed by the time limit
            $write("[Case %2d] %-18s N = %6d  ", c, tag, in_p.size());
            $fflush();

            in_q.delete();
            foreach(in_p[i]) begin
                r.lo = in_p[i].lo;
                r.hi = in_p[i].hi;
                in_q.push_back(r);
            end
            got_q = merge_ranges(in_q);
            got_p.delete();
            foreach(got_q[i]) begin
                x.lo = got_q[i].lo;
                x.hi = got_q[i].hi;
                got_p.push_back(x);
            end

            d = first_diff(exp_p, got_p);
            run_num++;
            if(d < 0) pass_num++;
            else if(fail_case == 0) fail_case = c;
            $display("%s", (d < 0)? "PASS" : "FAIL");
            if(sel_case != 0 || fail_case == c) show_detail(d, in_p, exp_p, got_p);
            $fflush();
        end

        $display("=============================================================");
        if(fail_case == 0) $display("    Result : Accepted (%0d/%0d)", pass_num, run_num);
        else begin
            $display("    Result : Wrong Answer (%0d/%0d)", pass_num, run_num);
            $display("    Replay : make case=%0d", fail_case);
        end
        $display("=============================================================");
        $fclose(fd_in);
        $fclose(fd_out);
        $finish(0);
    end

endmodule
