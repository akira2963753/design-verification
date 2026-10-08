/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    sol.sv
* Project:      SV Practice, Problem 1
* Module:       sol_pkg
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

package sol_pkg;

    //=============================================================
    //                            Type
    //=============================================================
    // 先定義出無號數 uint 的資料型態
    typedef int unsigned uint;

    typedef struct packed{
        uint lo;
        uint hi;
    } range_t;

    // 定義 range_t 的 queue
    typedef range_t range_q [$]; 


    //=============================================================
    //                          Function
    //=============================================================

    function automatic range_q merge_ranges(input range_q in_q);
        int len;

        len = in_q.size();
        for(int i = 1; i < len; i++) begin
            // Overlap, eg, [1, 5][4, 8] or [4, 8][1, 5]
            if((in_q[i].lo <= in_q[i-1].hi) && (in_q[i].hi >= in_q[i-1].lo)) begin
                // find the maximum and minimum
            end 
        end
    endfunction 


endpackage
