/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    ref_model.sv
* Project:      2026 FALL NYCU IC LAB, LAB03
* Module:       reference model
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Spec-level ZUMA ring, the queue-based golden model of 00_TESTBED/PATTERN.v
class ref_model;

    //=============================================================
    //                          Variable
    //=============================================================

    bit [2:0] ring[$];          // index 0 of the queue is always logical index 0
    int chain;                  // cascade levels of the last shot
    bit [2:0] elim_color[$];    // one entry per level, (0, 0) when no elimination
    bit [8:0] elim_cnt[$];

    // Corner events of the last shot
    bit ev_wrap;                // a segment crossed logical index M-1 / 0
    bit ev_head;                // logical index 0 was eliminated
    bit ev_clear;               // the whole ring was eliminated

    //=============================================================
    //                          Function
    //=============================================================

    // New game: discard the previous ring
    function void load(bit [2:0] init[$]);
        ring = init;
    endfunction

    // find the maximal same-color segment containing idx (wrap-around, bounded by ring size)
    function void find_seg(input int idx, output int start, output int len);
        int m, left, right;
        m = ring.size();
        left = 0;
        right = 0;
        while((left < m - 1) && (ring[(idx - left - 1 + m) % m] == ring[idx])) left++;
        while(left + right < m - 1 && ring[(idx + right + 1) % m] == ring[idx]) right++;
        start = (idx - left + m) % m;
        len = left + right + 1;
    endfunction

    // remove the segment and return the right side index of the new junction
    function int remove_seg(input int start, input int len);
        int m;
        m = ring.size();
        ev_head |= (start == 0) || (start + len > m);
        if(len == m) begin
            ev_clear = 1'b1;
            ring.delete();
            return 0;
        end
        else if(start + len <= m) begin
            // no wrap: logical index 0 survives or the bead after the segment shifts to index 0
            repeat(len) ring.delete(start);
            return start % ring.size();
        end
        else begin
            // wrap: index 0 is eliminated, the first survivor after the segment becomes index 0
            ev_wrap = 1'b1;
            repeat(m - start) void'(ring.pop_back());
            repeat(start + len - m) void'(ring.pop_front());
            return 0;
        end
    endfunction

    function void shoot(bit [2:0] color, int pos);
        int idx, start, len, left, right;
        chain = 0;
        elim_color.delete();
        elim_cnt.delete();
        ev_wrap = 1'b0;
        ev_head = 1'b0;
        ev_clear = 1'b0;

        if(ring.size() == 0) ring.push_back(color); // empty ring: shot_pos is ignored
        else begin
            ring.insert(pos + 1, color);
            idx = pos + 1;
            find_seg(idx, start, len);
            while(len >= 3) begin
                chain++;
                elim_color.push_back(ring[idx]);
                elim_cnt.push_back(len);
                right = remove_seg(start, len);
                if(ring.size() < 3) break;
                left = (right - 1 + ring.size()) % ring.size();
                if(ring[left] != ring[right]) break;
                idx = right;
                find_seg(idx, start, len);
            end
        end

        if(chain == 0) begin
            elim_color.push_back(0);
            elim_cnt.push_back(0);
        end
    endfunction

    // Run length of the new bead if color is inserted after pos, the ring is not changed
    function int run_len(int pos, bit [2:0] color);
        int m, left, right;
        m = ring.size();
        left = 0;
        right = 0;
        while(left < m && ring[(pos - left + m) % m] == color) left++;
        while(left + right < m && ring[(pos + 1 + right) % m] == color) right++;
        return left + right + 1;
    endfunction

endclass
