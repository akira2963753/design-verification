/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    oiss.cpp
* Project:      2026 FALL NYCU IC LAB, LAB01
* Module:       OISS Reference C++ Model
* Author:       Marco <harry2963753@gmail.com>
*
******************************************************************************/

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>

namespace {
using Words = std::array<unsigned int, 8>;

struct Solver {
    Words predecessors{}, latency{}, finish{};
    unsigned int best = 401;

    // Enumerate legal issue orders. For a fixed order, issuing each instruction
    // at its earliest allowed time minimizes all subsequent completion times.
    void search(unsigned int used, unsigned int next_issue, unsigned int completion) {
        if (completion >= best) return;
        if (used == 255) {
            best = completion;
            return;
        }
        for (unsigned int i = 0; i < 8; ++i) {
            if ((used & (1u << i)) || (predecessors[i] & ~used)) continue;
            unsigned int start = next_issue;
            for (unsigned int j = 0; j < 8; ++j) {
                if (predecessors[i] & (1u << j)) start = std::max(start, finish[j]);
            }
            finish[i] = start + latency[i];
            search(used | (1u << i), start + 1, std::max(completion, finish[i]));
        }
    }
};

int solve(const Words& inst, const Words& op_latency) {
    constexpr Words minimum{1, 1, 20, 30, 6, 6, 2, 1};
    constexpr Words maximum{5, 5, 40, 50, 10, 10, 4, 1};
    Words reads{}, writes{};
    Solver solver;
    for (unsigned int i = 0; i < 8; ++i) {
        if (inst[i] > 0xfff || op_latency[i] < minimum[i] ||
            op_latency[i] > maximum[i]) return -1;
        const auto op = inst[i] >> 9;
        const auto rs = (inst[i] >> 6) & 7;
        const auto rt = (inst[i] >> 3) & 7;
        const auto rd = inst[i] & 7;
        if (op < 4 || op == 6) reads[i] = (1u << rs) | (1u << rt);
        if (op == 5) reads[i] = 1u << rd;
        if (op <= 4) writes[i] = 1u << rd;
        solver.latency[i] = op_latency[op];
    }
    for (unsigned int i = 0; i < 8; ++i) {
        for (unsigned int j = i + 1; j < 8; ++j) {
            if ((writes[i] & reads[j]) || (reads[i] & writes[j]) ||
                (writes[i] & writes[j])) solver.predecessors[j] |= 1u << i;
        }
    }
    solver.search(0, 0, 0);
    return static_cast<int>(solver.best);
}
} // namespace

// Scalar DPI arguments avoid simulator-specific open-array APIs. Word 0 is LSB.
// Returns minimum Ex_cycle, or -1 for an invalid encoding/latency.
extern "C" int oiss_ref_cycle(unsigned int seq0, unsigned int seq1,
                              unsigned int seq2, unsigned int lat0,
                              unsigned int lat1) {
    static_assert(std::numeric_limits<unsigned int>::digits == 32);
    if (lat1 > 0xffff) return -1;
    const std::array<unsigned int, 3> seq{seq0, seq1, seq2};
    const std::uint64_t packed_lat = (std::uint64_t{lat1} << 32) | lat0;
    Words inst{}, latency{};
    for (unsigned int i = 0; i < 8; ++i) {
        const auto bit = i * 12;
        const auto word = bit / 32;
        const auto shift = bit % 32;
        std::uint64_t window = seq[word];
        if (word + 1 < seq.size()) window |= std::uint64_t{seq[word + 1]} << 32;
        inst[i] = static_cast<unsigned int>((window >> shift) & 0xfff);
        latency[i] = static_cast<unsigned int>((packed_lat >> (i * 6)) & 63);
    }
    return solve(inst, latency);
}

#ifdef OISS_REF_STANDALONE
#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: oiss_ref input.txt output.txt\n";
        return 2;
    }
    std::ifstream input(argv[1]), golden(argv[2]);
    unsigned int count;
    if (!input || !golden || !(input >> std::dec >> count)) return 2;
    unsigned int mismatches = 0;
    for (unsigned int p = 0; p < count; ++p) {
        Words inst{}, latency{};
        int expected;
        for (auto& value : inst) if (!(input >> std::hex >> value) || value > 0xfff) return 2;
        for (auto& value : latency) if (!(input >> std::dec >> value) || value > 63) return 2;
        if (!(golden >> std::dec >> expected)) return 2;
        std::array<unsigned int, 3> seq{};
        std::uint64_t packed_lat = 0;
        for (unsigned int i = 0; i < 8; ++i) {
            const auto bit = i * 12;
            const std::uint64_t field = std::uint64_t{inst[i]} << (bit % 32);
            seq[bit / 32] |= static_cast<unsigned int>(field);
            if (bit / 32 + 1 < seq.size()) seq[bit / 32 + 1] |= static_cast<unsigned int>(field >> 32);
            packed_lat |= std::uint64_t{latency[i]} << (i * 6);
        }
        // Exercise the same packed scalar entry point that SV calls.
        const int actual = oiss_ref_cycle(seq[0], seq[1], seq[2],
            static_cast<unsigned int>(packed_lat), static_cast<unsigned int>(packed_lat >> 32));
        if (actual < 0 || actual != expected) {
            ++mismatches;
            std::cerr << "Pattern " << p << ": expected " << expected << ", actual " << actual << '\n';
        }
    }
    std::string extra;
    if ((input >> extra) || (golden >> extra)) {
        std::cerr << "Unexpected trailing data\n";
        return 2;
    }
    std::cout << "Compared " << count << " patterns; mismatches: " << mismatches << '\n';
    return mismatches ? 1 : 0;
}
#endif
