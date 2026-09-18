#======================================================
#          TSMC 90nm Design Compiler Synthesis
#======================================================

#======================================================
#                    Global Parameters
#======================================================
set DESIGN OISS
set RTL_FILE ../01_RTL/OISS.v
set PERIOD 4.0
set IO_DELAY 0.5

set sh_continue_on_error false
set compile_preserve_subdesign_interfaces true
set hdlin_auto_save_templates true

file mkdir work
file mkdir Report
file mkdir Netlist
define_design_lib WORK -path ./work

#======================================================
#                    TSMC 90nm Libraries
#======================================================
# Library files are resolved through the CAD environment search path.
set_app_var target_library [list slow.db]
set_app_var synthetic_library [list dw_foundation.sldb]
set_app_var link_library [list "*" slow.db fast.db dw_foundation.sldb]

# Associate the worst-case mapping library with its best-case timing view.
set_min_library slow.db -min_version fast.db

#======================================================
#                       Read RTL
#======================================================
analyze -format sverilog $RTL_FILE
elaborate $DESIGN
current_design $DESIGN
link

redirect Report/$DESIGN.check_precompile.rpt {
    check_design
}

write -format ddc -hierarchy -output Netlist/$DESIGN.raw.ddc

#======================================================
#                 Operating Conditions
#======================================================
set_operating_conditions -analysis_type bc_wc -min fast -max slow
set_wire_load_mode top
set_wire_load_model -name tsmc090_wl10 -library slow [current_design]

#======================================================
#                    Timing Constraints
#======================================================
# OISS is purely combinational, so use a virtual clock to constrain
# input-to-output paths.
create_clock -name vclk -period $PERIOD
set_clock_uncertainty 0.5 [get_clocks vclk]
set_clock_latency -source 0.0 [get_clocks vclk]
set_clock_latency 0.1 [get_clocks vclk]

set_input_delay -clock vclk -max $IO_DELAY [all_inputs]
set_input_delay -clock vclk -min 0.0 [all_inputs]
set_output_delay -clock vclk -max $IO_DELAY [all_outputs]
set_output_delay -clock vclk -min 0.0 [all_outputs]

# Use the 90nm I/O pad models when the pad library is available.
set INPUT_PAD_PIN [get_lib_pins -quiet tpzn90gv3wc/PDIDGZ_33/C]
if {[sizeof_collection $INPUT_PAD_PIN] > 0} {
    set_driving_cell -library tpzn90gv3wc \
        -lib_cell PDIDGZ_33 -pin C [all_inputs]
} else {
    puts "WARNING: tpzn90gv3wc input pad not found; using 0.2 ns input transition."
    set_input_transition 0.2 [all_inputs]
}

set OUTPUT_PAD_PIN [get_lib_pins -quiet tpzn90gv3wc/PDO16CDG_33/I]
if {[sizeof_collection $OUTPUT_PAD_PIN] > 0} {
    set_load [load_of tpzn90gv3wc/PDO16CDG_33/I] [all_outputs]
} else {
    puts "WARNING: tpzn90gv3wc output pad not found; using 0.05 pF output load."
    set_load 0.05 [all_outputs]
}

#======================================================
#                  Design Rule Constraints
#======================================================
set_max_area 0
set_max_transition 0.2 [current_design]
set_max_capacitance 0.1 [current_design]
set_max_fanout 10 [current_design]
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

redirect Report/$DESIGN.check_timing_precompile.rpt {
    check_timing
}

#======================================================
#                       Optimization
#======================================================
compile_ultra -no_autoungroup

#======================================================
#                      Naming Rules
#======================================================
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true

change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed "A-Za-z0-9_" \
    -max_length 255 -type cell
define_name_rules name_rule -allowed "A-Za-z0-9_[]" \
    -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

#======================================================
#                    Output Netlist
#======================================================
set verilogout_higher_designs_first true
write -format ddc -hierarchy -output Netlist/$DESIGN.opt.ddc
write -format verilog -hierarchy -output Netlist/$DESIGN\_SYN.v
write_sdf -version 2.1 -load_delay net Netlist/$DESIGN\_SYN.sdf
write_sdc Netlist/$DESIGN\_SYN.sdc

#======================================================
#                         Reports
#======================================================
redirect Report/$DESIGN.design.rpt {
    report_design
}
redirect Report/$DESIGN.resource.rpt {
    report_resource
}
redirect Report/$DESIGN.qor.rpt {
    report_qor
}
redirect Report/$DESIGN.timing.rpt {
    report_timing -delay_type max -max_paths 10 -nworst 1
}
redirect Report/$DESIGN.constraint.rpt {
    report_constraint -all_violators
}
redirect Report/$DESIGN.area.rpt {
    report_area -hierarchy
}
redirect Report/$DESIGN.power.rpt {
    report_power
}
redirect Report/$DESIGN.clock.rpt {
    report_clock
}
redirect Report/$DESIGN.port.rpt {
    report_port
}
redirect Report/$DESIGN.reference.rpt {
    report_reference
}
redirect Report/$DESIGN.check_postcompile.rpt {
    check_design
}
redirect Report/$DESIGN.check_timing_postcompile.rpt {
    check_timing
}

exit