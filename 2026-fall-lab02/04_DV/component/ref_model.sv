/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    ref_model.sv
* Project:      2026 FALL NYCU IC LAB, LAB02
* Module:       reference model
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

// Spec-level LDPC decoder: per-edge C2V / V2C storage, no RTL architecture
class ref_model;

    localparam int Z = 16;
    localparam int N_LAYER = 4;
    localparam int N_COL = 8;
    localparam int N_CN = N_LAYER * Z;  // 64
    localparam int N_VN = N_COL * Z;    // 128
    localparam int CN_DEG = 7;
    localparam int VN_DEG_MAX = 4;  // column group 0~3: 3, 4~7: 4
    localparam int T_MAX = 8;
    localparam int V2C_MAX = 31;

    // Base graph (-1: zero matrix, s: identity cyclically right-shifted by s)
    const int BG[N_LAYER][N_COL] = '{
        '{-1, 14, 10, 2, 13, 12, 9, 3},
        '{5, -1, 14, 10, 2, 13, 12, 9},
        '{0, 5, -1, 14, 10, 2, 13, 12},
        '{7, 0, 5, -1, 14, 10, 2, 13}
    };

    // Edge (i, e): e-th connection of CN i
    int cn_vn[N_CN][CN_DEG];    // VN index of edge (i, e)
    int vn_deg[N_VN];               // degree of VN j
    int vn_cn[N_VN][VN_DEG_MAX];    // CN index of the d-th edge of VN j
    int vn_slot[N_VN][VN_DEG_MAX];  // e of the d-th edge of VN j

    int c2v[N_CN][CN_DEG];
    int v2c[N_CN][CN_DEG];
    int iters;  // iterations used by the last decode()

    function new();
        int e, j;
        vn_deg = '{default: 0};
        for(int k = 0; k < N_LAYER; k++) begin
            for(int r = 0; r < Z; r++) begin
                e = 0;
                for(int c = 0; c < N_COL; c++) begin
                    if(BG[k][c] >= 0) begin
                        j = c * Z + (r + BG[k][c]) % Z;
                        cn_vn[k*Z+r][e] = j;
                        vn_cn[j][vn_deg[j]] = k * Z + r;
                        vn_slot[j][vn_deg[j]] = e;
                        vn_deg[j]++;
                        e++;
                    end
                end
            end
        end
    endfunction

    function int clip(int x, int lim);
        return (x > lim)? lim : (x < -lim)? -lim : x;
    endfunction

    // round_half_up(0.75 * m) = (3m + 2) >> 2
    function int nms_mag(int m);
        return (3 * m + 2) >>> 2;
    endfunction

    // Sum of all C2V into VN j
    function int c2v_sum(int j);
        int s = 0;
        for(int d = 0; d < vn_deg[j]; d++) s += c2v[vn_cn[j][d]][vn_slot[j][d]];
        return s;
    endfunction

    // V2C of edge (i, e) = clip(Lch + C2V from the other CNs)
    function void vn_update(int i, const ref bit signed [5:0] lch[N_VN]);
        int j;
        for(int e = 0; e < CN_DEG; e++) begin
            j = cn_vn[i][e];
            v2c[i][e] = clip(lch[j] + c2v_sum(j) - c2v[i][e], V2C_MAX);
        end
    endfunction

    // C2V of edge (i, e) = sign(others) * nms(min |others|)
    function void cn_update(int i);
        int new_c2v[CN_DEG];
        bit neg;
        int mag, x, a;
        for(int e = 0; e < CN_DEG; e++) begin
            neg = 1'b0;
            mag = V2C_MAX + 1;
            for(int o = 0; o < CN_DEG; o++) begin
                if(o != e) begin
                    x = v2c[i][o];
                    a = (x < 0)? -x : x;
                    if(x < 0) neg = ~neg;  // 0 counts as positive
                    if(a < mag) mag = a;
                end
            end
            new_c2v[e] = (neg)? -nms_mag(mag) : nms_mag(mag);
        end
        for(int e = 0; e < CN_DEG; e++) c2v[i][e] = new_c2v[e];
    endfunction

    function bit syndrome_ok(const ref int app[N_VN]);
        bit s;
        for(int i = 0; i < N_CN; i++) begin
            s = 1'b0;
            for(int e = 0; e < CN_DEG; e++) s ^= (app[cn_vn[i][e]] < 0);
            if(s) return 1'b0;
        end
        return 1'b1;
    endfunction

    // Whole-frame decode: 128 Lch in, 128 APP + warn out
    function void decode(bit mode, const ref bit signed [5:0] lch[N_VN], output bit signed [7:0] app[N_VN], output bit warn);
        int app_i[N_VN];

        // Initialization: C2V = 0, V2C = Lch
        for(int i = 0; i < N_CN; i++) begin
            for(int e = 0; e < CN_DEG; e++) begin
                c2v[i][e] = 0;
                v2c[i][e] = lch[cn_vn[i][e]];
            end
        end

        warn = 1'b1;
        iters = T_MAX;
        for(int t = 0; t < T_MAX; t++) begin
            if(mode == 1'b0) begin  // flooding
                for(int i = 0; i < N_CN; i++) cn_update(i);
                for(int i = 0; i < N_CN; i++) vn_update(i, lch);
            end
            else begin  // layered
                for(int k = 0; k < N_LAYER; k++) begin
                    for(int i = k * Z; i < (k + 1) * Z; i++) begin
                        vn_update(i, lch);
                        cn_update(i);
                    end
                end
            end

            // Bit estimation and syndrome check
            for(int j = 0; j < N_VN; j++) app_i[j] = lch[j] + c2v_sum(j);
            if(syndrome_ok(app_i)) begin
                warn = 1'b0;
                iters = t + 1;
                break;
            end
        end

        // |APP| <= 31 + 4 * 23 = 123, fits 8b without saturation
        for(int j = 0; j < N_VN; j++) app[j] = app_i[j];
    endfunction

endclass
