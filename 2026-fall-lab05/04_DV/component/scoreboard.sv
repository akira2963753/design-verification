/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    scoreboard.sv
* Project:      2026 FALL NYCU IC LAB, LAB05
* Module:       scoreboard
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

import dv_pkg::*;

class scoreboard;

    //=============================================================
    //                          CONSTRUCTOR
    //=============================================================

    mailbox #(mon_txn) mon2scb;     // images and bytes from the monitor, in time order
    mailbox #(uint) scb2drv;        // latency of every finished image, the driver starts the next one

    img_txn img;                    // image being checked, kept for dump_pattern()
    bit [7:0] expect_q [$];         // golden bytes not yet received
    uint byte_cnt;                  // bytes received of the current image
    uint img_byte;                  // golden byte number of the current image

    // Statistics
    uint pat_cnt;
    uint total_lat;
    uint max_lat;
    uint total_byte;
    uint max_byte;

    function new(
        mailbox #(mon_txn) mon2scb,
        mailbox #(uint) scb2drv
    );
        this.mon2scb = mon2scb;
        this.scb2drv = scb2drv;
        this.pat_cnt = 0;
        this.total_lat = 0;
        this.max_lat = 0;
        this.total_byte = 0;
        this.max_byte = 0;
    endfunction

    //=============================================================
    //                       REFERENCE MODEL
    //=============================================================

    // Same as 00_TESTBED/PATTERN.sv JPEG_Like_Encoder, raster pixels in, output bytes out
    function void ref_model(input logic [7:0] pix [16384], ref bit [7:0] gold [$]);
        int p [16][16][8][8];   // [bx][by][x][y]
        int r [16][16][8][8];   // [bx][by][u][y]
        int a [16][16][8][8];   // [bx][by][u][v]
        int z [16][16][64];     // [bx][by][n]

        int acc, prev_dc, diff, run, size, len;
        bit [15:0] code;

        bit bs [$]; // bitstream, earliest bit first

        //=============================================================
        //               Input Processing & Level Shifting
        //=============================================================
        for(int by = 0; by < 16; by++) begin
            for(int bx = 0; bx < 16; bx++) begin
                for(int y = 0; y < 8; y++) begin
                    for(int x = 0; x < 8; x++) begin
                        p[bx][by][x][y] = int'(pix[128 * (8 * by + y) + 8 * bx + x]) - 128;
                    end
                end
            end
        end

        //=============================================================
        //            Calculate the R(u, y) for all blocks
        //=============================================================
        for(int by = 0; by < 16; by++) begin
            for(int bx = 0; bx < 16; bx++) begin
                for(int y = 0; y < 8; y++) begin
                    for(int u = 0; u < 8; u++) begin
                        acc = 0;
                        for(int x = 0; x < 8; x++) acc += p[bx][by][x][y] * C_TAB[u][x];
                        r[bx][by][u][y] = acc;
                    end
                end
            end
        end

        //=============================================================
        //     Calculate A(u, v), D(u, v) and quant for all blocks
        //=============================================================
        for(int by = 0; by < 16; by++) begin
            for(int bx = 0; bx < 16; bx++) begin
                for(int u = 0; u < 8; u++) begin
                    for(int v = 0; v < 8; v++) begin
                        acc = 0;
                        for(int y = 0; y < 8; y++) acc += r[bx][by][u][y] * C_TAB[v][y];
                        // D(u, v) and quantization are two separate roundings
                        a[bx][by][u][v] = round_s(round_s(acc, 18), S_TAB[v][u]);
                    end
                end
            end
        end

        //=============================================================
        //                          Zigzag Scan
        //=============================================================
        for(int by = 0; by < 16; by++) begin
            for(int bx = 0; bx < 16; bx++) begin
                for(int k = 0; k < 64; k++) z[bx][by][k] = a[bx][by][ZZ_U[k]][ZZ_V[k]];
            end
        end

        //=============================================================
        //             Entropy coding for block 0 to 255
        //=============================================================
        prev_dc = 0;
        for(int by = 0; by < 16; by++) begin
            for(int bx = 0; bx < 16; bx++) begin

                // DC: Huffman(SIZE(diff)) + amplitude
                diff = z[bx][by][0] - prev_dc;
                prev_dc = z[bx][by][0];
                size = get_size(diff);
                DC_HUFF(size, len, code);
                put_bits(bs, code, len);
                put_bits(bs, get_amp(diff, size), size);

                // AC: run-length + Huffman(RUN, SIZE) + amplitude
                run = 0;
                for(int k = 1; k < 64; k++) begin
                    if(z[bx][by][k] == 0) begin
                        run++;
                    end
                    else begin
                        while(run >= 16) begin
                            AC_HUFF(15, 0, len, code);  // ZRL
                            put_bits(bs, code, len);
                            run -= 16;
                        end
                        size = get_size(z[bx][by][k]);
                        AC_HUFF(run, size, len, code);
                        put_bits(bs, code, len);
                        put_bits(bs, get_amp(z[bx][by][k], size), size);
                        run = 0;
                    end
                end
                if(run > 0) begin
                    AC_HUFF(0, 0, len, code);           // EOB
                    put_bits(bs, code, len);
                end

            end
        end

        //=============================================================
        //                        Byte Packing
        //=============================================================
        while(bs.size() % 8 != 0) bs.push_back(1'b1);  // end of image padding

        gold.delete();
        for(int i = 0; i < bs.size(); i += 8) begin
            gold.push_back({bs[i], bs[i + 1], bs[i + 2], bs[i + 3], bs[i + 4], bs[i + 5], bs[i + 6], bs[i + 7]});
        end

    endfunction

    //=============================================================
    //                         CHECK FUNCTION
    //=============================================================

    // Write the failed image in input.txt format (pat_num, mode, pixels) for PATTERN replay
    function void dump_pattern();
        int fd;
        fd = $fopen("fail_input.txt", "w");
        $fdisplay(fd, "1");
        $fdisplay(fd, "0");
        for(int i = 0; i < PIX_NUM; i++) $fdisplay(fd, "%h", img.pix[i]);
        $fclose(fd);
        $display("Image written to fail_input.txt (input.txt format)");
    endfunction

    // A new image: the golden bytes become the expected queue
    function void check_img(img_txn t);
        if(expect_q.size() != 0) begin
            $display("=============================================================");
            $display("   [SPEC-20 FAILED] Pattern NO.%0d got %0d of %0d bytes before the next image", pat_cnt, byte_cnt, img_byte);
            $display("=============================================================");
            dump_pattern();
            $fatal(1);
        end
        img = t;
        ref_model(img.pix, expect_q);
        img_byte = expect_q.size();
        byte_cnt = 0;
    endfunction

    // SPEC-19 / 20: the k-th out_valid byte equals the k-th golden byte, checked when it comes out
    function void check_byte(byte_txn t);
        bit [7:0] gold;

        if(expect_q.size() == 0) begin
            $display("=============================================================");
            $display("   [SPEC-20 FAILED] out_valid is high but no byte is expected");
            $display("   (more bytes than golden, or output before the image is complete)");
            $display("   Last finished pattern NO.%0d, time %0t", pat_cnt - 1, $time);
            $display("=============================================================");
            $fatal(1);
        end

        gold = expect_q.pop_front();
        if(t.data !== gold) begin
            $display("=============================================================");
            $display("                    [SPEC-19 FAILED]                         ");
            $display("    Pattern NO.%0d, Byte NO.%0d of %0d, time %0t", pat_cnt, byte_cnt, img_byte, $time);
            $display("    Golden: %02h", gold);
            $display("    Yours : %02h", t.data);
            $display("=============================================================");
            dump_pattern();
            $fatal(1);
        end
        byte_cnt++;

        // The last byte: the image passes, the driver may start the next one
        if(expect_q.size() == 0) begin
            total_lat += t.lat;
            if(t.lat > max_lat) max_lat = t.lat;
            total_byte += img_byte;
            if(img_byte > max_byte) max_byte = img_byte;
            $display(" [PATTERN %0d] PASS, latency = %0d, bytes = %0d", pat_cnt, t.lat, img_byte);
            pat_cnt++;
            void'(scb2drv.try_put(t.lat));  // unbounded mailbox, never fails, and put() is not allowed in a function
        end
    endfunction

    function void report();
        $display("=============================================================");
        $display("                     Scoreboard Summary");
        $display("=============================================================");
        $display("Pass patterns = %0d", pat_cnt);
        $display("Latency: total = %0d, max = %0d, avg = %.2f cycles", total_lat, max_lat, (pat_cnt == 0)? 0.0 : real'(total_lat) / pat_cnt);
        $display("Output bytes: total = %0d, max = %0d", total_byte, max_byte);
        $display("=============================================================");
    endfunction

    //=============================================================
    //                           MAIN FLOW
    //=============================================================

    task run();
        mon_txn t;
        img_txn i;
        byte_txn b;
        forever begin
            mon2scb.get(t);
            if($cast(i, t)) check_img(i);
            else if($cast(b, t)) check_byte(b);
        end
    endtask

endclass
