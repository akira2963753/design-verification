/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    trans.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       transaction
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

typedef int unsigned uint;

//=============================================================
// K_CHANNEL:   According to the LDPC encoding flow
// K_ALL_MAX:   All LLRs set to maximum
// K_ALL_ZERO:  All LLRs set to zero
// K_UNIFORM:   Uniformly random LLRs in range [-31, 31]
//=============================================================

typedef enum bit [2:0] {
    K_CHANNEL,  
    K_ALL_MAX, 
    K_ALL_ZERO, 
    K_UNIFORM  
} kind_t;

class txn;

    //=============================================================
    //                         Parameter
    //=============================================================

    localparam real PI = 3.141592653589793;

    //=============================================================
    //                          Variable
    //=============================================================

    rand kind_t     kind;
    rand bit        mode;
    rand int        snr_x10;    // SNR(dB) * 10 [-1dB, 6dB] 
    rand bit [63:0] u;
    rand uint       in_lat;
    rand uint       next_lat;

    static bit G[64][128];      // Generator Matrix (G), static
    bit [127:0] x;              // x = uG
    bit signed [5:0] lch[128];  // Quantized channel LLRs

    //=============================================================
    //                         Constraints
    //=============================================================
    constraint c_kind {
        kind dist {
            K_CHANNEL   := 88,
            K_ALL_MAX   := 4,
            K_ALL_ZERO  := 4,
            K_UNIFORM   := 4
        };
    };

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

    //=============================================================
    //                         Function
    //=============================================================

    // Static function, because all members use same generator matrix 
    static function void load_G(string path = "G_128_64.txt");

        // Check whether the file exists
        int fd;
        fd = $fopen(path, "r");
        if(fd == 0) begin
            $display("=============================================================");
            $display("       [TRANS] Cannot open generator matrix from %s ", path);
            $display("=============================================================");
            $fatal(1);
        end
        $fclose(fd);

        // Read generator matrix
        $readmemb(path, G);

    endfunction

    //=============================================================
    //              Encode the u from constraint-random
    //=============================================================
    function void encode();
        foreach(x[j]) begin
            bit acc = 1'b0;
            foreach(u[i]) acc ^= u[i] & G[i][j];
            x[j] = acc;
        end
    endfunction

    //=============================================================
    //              Standard normal sample by Box-Muller
    //=============================================================

    function real gauss();
        real u1, u2;
        u1 = (real'($urandom()) + 1.0) / (2.0 ** 32);  // (0, 1], keeps ln() finite
        u2 = real'($urandom()) / (2.0 ** 32);          // [0, 1)
        return $sqrt(-2.0 * $ln(u1)) * $cos(2.0 * PI * u2);
    endfunction

    //=============================================================
    //                  Quantization function
    //          Lch = sgn(L) * min(31, floor(2|L| + 0.5))
    //=============================================================
    function bit signed [5:0] quantize(real L);
        real mag;
        int q;
        mag = (L < 0.0)? -L : L;
        mag = $floor(2.0 * mag + 0.5);
        q = (mag > 31.0)? 31 : int'(mag);
        if(L < 0.0) q = -q;
        return q[5:0];
    endfunction

    //=============================================================
    //              LLR caculation based on spec
    //=============================================================
    function void gen_llr();
        real sigma2, sigma, s, r, L;
        sigma2 = $pow(10.0, -snr_x10 / 100.0);  // 10^(-SNR(dB)/10), SNR(dB) = snr_x10 / 10
        sigma = $sqrt(sigma2);
        foreach(lch[i]) begin
            s = (x[i])? -1.0 : 1.0;     // BPSK: 0 to +1, 1 to -1
            r = s + sigma * gauss();    // AWGN
            L = 2.0 * r / sigma2;       // LLR
            lch[i] = quantize(L);       // Quantization
        end
    endfunction

    //=============================================================
    //                        Post Randomize
    //=============================================================

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

class mon_txn;
    logic mode;
    logic signed [5:0] lch[128];
    logic signed [7:0] app[128];
    logic warn[128];
    uint  run_lat;
endclass
