/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      SV Practice, Problem 3
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
    int show_max = 12;          // ops printed in the detail

    //=============================================================
    //                            Type
    //=============================================================

    // Judge-side op, independent of the op_t written in sol.sv
    typedef struct packed {
        bit is_put;
        int key;
        int val;
    } jop_t;

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

    // "<cap> <m> <tag>" then m lines of "G <key>" or "P <key> <val>"
    function automatic void read_ops(int fd, output int cap, output string tag, output jop_t ops[$]);
        int m;
        string c;
        jop_t o;
        void'($fscanf(fd, "%d %d %s", cap, m, tag));
        repeat(m) begin
            void'($fscanf(fd, "%s %d", c, o.key));
            o.is_put = (c == "P");
            o.val = 0;
            if(o.is_put) void'($fscanf(fd, "%d", o.val));
            ops.push_back(o);
        end
    endfunction

    // "<m> <tag>" then m results
    function automatic void read_res(int fd, output string tag, output integer res[$]);
        int m, x;
        void'($fscanf(fd, "%d %s", m, tag));
        repeat(m) begin
            void'($fscanf(fd, "%d", x));
            res.push_back(x);
        end
    endfunction

    // Index of the first mismatch, -1 when got equals exp
    function automatic int first_diff(const ref integer exp[$], const ref integer got[$]);
        int n = (exp.size() < got.size())? exp.size() : got.size();
        for(int i = 0; i < n; i++) begin
            if(got[i] !== exp[i]) return i;
        end
        return (exp.size() == got.size())? -1 : n;
    endfunction

    function automatic string op_str(jop_t o);
        if(o.is_put) return $sformatf("P %0d %0d", o.key, o.val);
        return $sformatf("G %0d", o.key);
    endfunction

    function automatic string res_str(int i, const ref integer r[$]);
        if(i >= r.size()) return "(none)";
        return $sformatf("%0d", r[i]);
    endfunction

    // Ops leading to the first diff, or the first ops when the case passed
    function automatic void show_detail(int d, int cap, const ref jop_t ops[$], const ref integer exp_r[$], const ref integer got_r[$]);
        int lo, hi;
        string mark;            // string type, a literal ternary would pad "" with spaces
        $display("    Capacity : %0d", cap);
        $display("    Ops      : %0d, got %0d results", ops.size(), got_r.size());
        if(d >= 0) begin
            lo = (d >= show_max)? d - show_max + 1 : 0;
            hi = d;
        end
        else begin
            lo = 0;
            hi = ((ops.size() < show_max)? ops.size() : show_max) - 1;
        end
        if(hi >= ops.size()) begin
            $display("    First diff at result %0d: expected size %0d, got size %0d", d, exp_r.size(), got_r.size());
            return;
        end
        $display("    %8s  %-26s %12s %12s", "op", "command", "expected", "got");
        for(int i = lo; i <= hi; i++) begin
            mark = (i == d)? "  <== first diff" : "";
            $display("    %8d  %-26s %12s %12s%s", i, op_str(ops[i]), res_str(i, exp_r), res_str(i, got_r), mark);
        end
        if(d < 0 && ops.size() > show_max) $display("    ... (+%0d more ops)", ops.size() - show_max);
    endfunction

    //=============================================================
    //                            Judge
    //=============================================================

    initial begin : JUDGE
        string tag, tag_exp;
        jop_t ops[$];
        integer exp_r[$], got_r[$];
        op_q oq;
        res_q got_q;
        op_t o;
        int cap;
        int d;

        void'($value$plusargs("CASE=%d", sel_case));
        fd_in = $fopen(in_file, "r");
        fd_out = $fopen(out_file, "r");
        if(fd_in == 0 || fd_out == 0) $fatal(1, "[JUDGE] Cannot open %s or %s", in_file, out_file);
        void'($fscanf(fd_in, "%d", case_num));
        void'($fscanf(fd_out, "%d", case_num));
        if(sel_case < 0 || sel_case > case_num) $fatal(1, "[JUDGE] CASE=%0d out of range 1~%0d", sel_case, case_num);

        $display("=============================================================");
        $display("              Problem 3: LRU Cache (%0d cases)", case_num);
        $display("=============================================================");

        for(int c = 1; c <= case_num; c++) begin
            ops.delete();
            exp_r.delete();
            read_ops(fd_in, cap, tag, ops);
            read_res(fd_out, tag_exp, exp_r);
            if(tag != tag_exp) $fatal(1, "[JUDGE] Case %0d: input.txt and output.txt out of sync", c);
            if(sel_case != 0 && c != sel_case) continue;

            // Partial line stays visible if the run is killed by the time limit
            $write("[Case %2d] %-18s cap = %6d  M = %6d  ", c, tag, cap, ops.size());
            $fflush();

            oq.delete();
            foreach(ops[i]) begin
                o.op = (ops[i].is_put)? OP_PUT : OP_GET;
                o.key = ops[i].key;
                o.val = ops[i].val;
                oq.push_back(o);
            end
            got_q = lru_run(cap, oq);
            got_r.delete();
            foreach(got_q[i]) got_r.push_back(got_q[i]);

            d = first_diff(exp_r, got_r);
            run_num++;
            if(d < 0) pass_num++;
            else if(fail_case == 0) fail_case = c;
            $display("%s", (d < 0)? "PASS" : "FAIL");
            if(sel_case != 0 || fail_case == c) show_detail(d, cap, ops, exp_r, got_r);
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
