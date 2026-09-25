/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       trans
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

typedef enum bit [2:0] {
    K_CHANNEL,  // according appendix flow
    K_ALL_MAX,  // llr are all max (+31 or -31)
    K_ALL_ZERO, // llr are all zero
    K_UNIFORM  // llr randomize in [-31, 31]
} kind_t;

typedef int unsigned uint;

class trans;

    rand kind_t     kind;
    rand bit        mode;
    rand int        snr_x10;    // SNR(dB) * 10 
    rand bit [63:0] u;
    rand uint       in_lat;
    rand uint       next_lat;

    static bit G[64][128];
    bit [127:0] x;  // x = uG
    bit signed [5:0] lch[128];  // quantized channel LLR

    localparam real PI = 3.141592653589793;

    constraint c_kind {
        kind dist {
            K_CHANNEL   := 88,
            K_ALL_MAX   := 4,
            K_ALL_ZERO  := 4,
            K_UNIFORM   := 4
        };
    };

    // SNR(dB) = -1 ~ 6 dB
    constraint c_snr_x10 {
        snr_x10 dist {
            [-10:10]    :/ 30,
            [11:35]     :/ 50,
            [36:60]     :/ 20     
        };
    };

    constraint c_in_lat {
        in_lat inside {[2:4]};
        next_lat inside {[2:4]};
    };

    static function void load_G(string path = "G_128_64.txt");
        int fd;
        fd = $fopen(path, "r");
        if(fd == 0) $fatal(1, "[TRANS] cannot open generator matrix %s", path);
        $fclose(fd);
        $readmemb(path, G);
    endfunction

    // Encode the u from constraint-random
    function void encode();
        foreach(x[j]) begin
            bit acc = 1'b0;
            foreach(u[i]) acc ^= u[i] & G[i][j];
            x[j] = acc;
        end
    endfunction

    // Standard normal sample by Box-Muller
    function real gauss();
        real u1, u2;
        u1 = (real'($urandom()) + 1.0) / (2.0 ** 32);  // (0, 1], keeps ln() finite
        u2 = real'($urandom()) / (2.0 ** 32);          // [0, 1)
        return $sqrt(-2.0 * $ln(u1)) * $cos(2.0 * PI * u2);
    endfunction

    // Lch = sgn(L) * min(31, floor(2|L| + 0.5))
    function bit signed [5:0] quantize(real L);
        real mag;
        int q;
        mag = (L < 0.0)? -L : L;
        mag = $floor(2.0 * mag + 0.5);
        q = (mag > 31.0)? 31 : int'(mag);
        if(L < 0.0) q = -q;
        return q[5:0];
    endfunction

    // BPSK -> AWGN -> LLR -> quantize, uses x and snr_x10
    function void gen_llr();
        real sigma2, sigma, s, r, L;
        sigma2 = $pow(10.0, -snr_x10 / 100.0);  // 10^(-SNR(dB)/10), SNR(dB) = snr_x10 / 10
        sigma = $sqrt(sigma2);
        foreach(lch[i]) begin
            s = (x[i])? -1.0 : 1.0;   // BPSK: 0 -> +1, 1 -> -1
            r = s + sigma * gauss();  // AWGN
            L = 2.0 * r / sigma2;     // LLR
            lch[i] = quantize(L);
        end
    endfunction

    function void post_randomize();
        encode();
        case(kind)
            K_CHANNEL: gen_llr();
            K_ALL_MAX: foreach(lch[i]) lch[i] = (x[i])? -6'sd31 : 6'sd31;
            K_ALL_ZERO: foreach(lch[i]) lch[i] = 6'sd0;
            K_UNIFORM: foreach(lch[i]) lch[i] = int'($urandom_range(0, 62)) - 31;
            default: gen_llr();
        endcase
    endfunction

endclass

//=============================================================
//                     Monitor Transaction
//=============================================================

// Pin-level snapshot of one pattern, logic keeps X/Z for the scoreboard
class mon_txn;
    uint testcase;
    logic mode;
    logic signed [5:0] lch[128];
    logic signed [7:0] app[128];
    logic warn[128];
    uint latency;  // cycles from the last in_data_valid to the first out_valid
endclass
