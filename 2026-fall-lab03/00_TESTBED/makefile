.PHONY: vcs_rtl vcs_gate vcs_post clean

######################################
# Set your desired file names
######################################
define=CORRECT
source_file="filelist.f"	# Name of your source file
output_file="simv"      	# Desired output simulation file name
log_file="vcs.log"      	# Desired log file name

######################################
# Default Setting
######################################
num_CPU_cores=8               # Maximum Number of CPU that used for simulation
TIMESCALE=-timescale=1ns/1fs
DW_SIM=/usr/cad/synopsys/synthesis/cur/dw/sim_ver/
UMC018_SIM=~iclabTA01/umc018/Verilog/umc18_neg.v
UMC018_IO_SIM=~iclabTA01/umc018/Verilog/umc18io3v5v.v

######################################
# Simulation Option and Command
######################################

# =====================================
# ============== VCS ==================
# =====================================
VCS_RTL_SIM = vcs ${TIMESCALE} \
    -j${num_CPU_cores} \
    -sverilog \
    +v2k \
    -full64 \
    -Mupdate \
    -R \
    -debug_access+all \
    -y ${DW_SIM} \
    +libext+.v \
    -f ${source_file} \
    -o ${output_file} \
    -l ${log_file} \
    +define+RTL \
	+define+${define} \
    +notimingchecks


VCS_GATE_SIM = vcs ${TIMESCALE} \
    -j${num_CPU_cores} \
    -sverilog \
    +v2k \
    -full64 \
    -Mupdate \
    -R \
    -debug_access+all \
    -f ${source_file} \
    -o ${output_file} \
    -l ${log_file} \
	-v ${UMC018_SIM} \
    +define+GATE \
	+neg_tchk

VCS_POST_SIM = vcs ${TIMESCALE} \
    -j${num_CPU_cores} \
    -sverilog \
    +v2k \
    -full64 \
    -Mupdate \
    -R \
    -debug_access+all \
    -f ${source_file} \
    -o ${output_file} \
    -l ${log_file} \
    -v ${UMC018_SIM} \
	-v ${UMC018_IO_SIM} \
    +define+POST \
    +neg_tchk

# =====================================
# ============= clean =================
# =====================================
clean_vcs = rm -rf ./csrc *.log simv* *.sdf.X *.key

vcs_rtl:
	${VCS_RTL_SIM}

vcs_gate:
	${VCS_GATE_SIM}

vcs_post:
	${VCS_POST_SIM}

clean:
	${clean_vcs}
