+incdir+../00_TESTBED/
-sverilog ./OISS.v
-sverilog ../00_TESTBED/PATTERN.sv
-sverilog ../00_TESTBED/TESTBED.v
-CFLAGS "-std=c++17" ../00_TESTBED/component/oiss.cpp
