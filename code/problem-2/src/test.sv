/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    test.sv
* Project:      SV Practice, Problem 2
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
    int show_max = 16;          // values printed per list in the detail

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

    // One case block: "<n> <tag>" (output.txt) or "<n> <w> <tag>" (input.txt), then n decimal values
    function automatic void read_block(int fd, bit has_w, output int w, output string tag, output integer v[$]);
        int n, x;
        if(has_w) void'($fscanf(fd, "%d %d %s", n, w, tag));
        else void'($fscanf(fd, "%d %s", n, tag));
        repeat(n) begin
            void'($fscanf(fd, "%d", x));
            v.push_back(x);
        end
    endfunction

    function automatic string list_str(const ref integer v[$]);
        string s = "";
        int n = (v.size() < show_max)? v.size() : show_max;
        if(v.size() == 0) return "(empty)";
        for(int i = 0; i < n; i++) s = {s, $sformatf("%0d ", v[i])};
        if(v.size() > n) s = {s, $sformatf("... (+%0d more)", v.size() - n)};
        return s;
    endfunction

    // Index of the first mismatch, -1 when got equals exp
    function automatic int first_diff(const ref integer exp[$], const ref integer got[$]);
        int n = (exp.size() < got.size())? exp.size() : got.size();
        for(int i = 0; i < n; i++) begin
            if(got[i] !== exp[i]) return i;
        end
        return (exp.size() == got.size())? -1 : n;
    endfunction

    // "idx (x = value)", or a note when idx does not point into x
    function automatic string idx_str(integer idx, const ref integer x[$]);
        if($isunknown(idx)) return $sformatf("%0d", idx);
        if(idx < 0 || idx >= x.size()) return $sformatf("%0d (out of range)", idx);
        return $sformatf("%0d (x = %0d)", idx, x[idx]);
    endfunction

    function automatic void show_detail(int d, int w, const ref integer x[$], const ref integer exp_i[$], const ref integer got_i[$]);
        $display("    W        : %0d", w);
        $display("    Input x  : %s", list_str(x));
        $display("    Expected : %s", list_str(exp_i));
        $display("    Got      : %s", list_str(got_i));
        if(d < 0) return;
        if(d < exp_i.size() && d < got_i.size()) begin
            $display("    First diff at output %0d, window x[%0d:%0d]: expected idx %s, got idx %s",
                     d, d, d + w - 1, idx_str(exp_i[d], x), idx_str(got_i[d], x));
        end
        else $display("    First diff at output %0d: expected size %0d, got size %0d", d, exp_i.size(), got_i.size());
    endfunction

    //=============================================================
    //                            Judge
    //=============================================================

    initial begin : JUDGE
        string tag, tag_exp;
        integer x[$], exp_i[$], got_i[$];
        sample_q xq;
        idx_q got_q;
        sample_t s;
        int w, dummy;
        int d;

        void'($value$plusargs("CASE=%d", sel_case));
        fd_in = $fopen(in_file, "r");
        fd_out = $fopen(out_file, "r");
        if(fd_in == 0 || fd_out == 0) $fatal(1, "[JUDGE] Cannot open %s or %s", in_file, out_file);
        void'($fscanf(fd_in, "%d", case_num));
        void'($fscanf(fd_out, "%d", case_num));
        if(sel_case < 0 || sel_case > case_num) $fatal(1, "[JUDGE] CASE=%0d out of range 1~%0d", sel_case, case_num);

        $display("=============================================================");
        $display("        Problem 2: Sliding Window Maximum (%0d cases)", case_num);
        $display("=============================================================");

        for(int c = 1; c <= case_num; c++) begin
            x.delete();
            exp_i.delete();
            read_block(fd_in, 1, w, tag, x);
            read_block(fd_out, 0, dummy, tag_exp, exp_i);
            if(tag != tag_exp) $fatal(1, "[JUDGE] Case %0d: input.txt and output.txt out of sync", c);
            if(sel_case != 0 && c != sel_case) continue;

            // Partial line stays visible if the run is killed by the time limit
            $write("[Case %2d] %-18s N = %6d  W = %6d  ", c, tag, x.size(), w);
            $fflush();

            xq.delete();
            foreach(x[i]) begin
                s = x[i];
                xq.push_back(s);
            end
            got_q = window_max(xq, w);
            got_i.delete();
            foreach(got_q[i]) got_i.push_back(got_q[i]);

            d = first_diff(exp_i, got_i);
            run_num++;
            if(d < 0) pass_num++;
            else if(fail_case == 0) fail_case = c;
            $display("%s", (d < 0)? "PASS" : "FAIL");
            if(sel_case != 0 || fail_case == c) show_detail(d, w, x, exp_i, got_i);
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
