source ./pt_cmds.tcl
#########################################################
### add design information here
set power_enable_analysis TRUE
set power_analysis_mode averaged

set design usb_phy

set timing_remove_clock_reconvergence_pessimism true

set search_path ". "
set link_path [list * /home/linux/ieng6/ee260b/public/data/libraries/lib/tsmc65.db]

read_verilog ./${design}.v
current_design $design 
link_design $design 
read_sdc ./${design}.sdc
read_parasitics ./${design}.spef

set report_default_significant_digits 6
set timing_save_pin_arrival_and_slack true
set timing_report_always_use_valid_start_end_points false
set rc_cache_min_max_rise_fall_ceff true
set_propagated_clock [all_clocks]
set GLOBAL_CNT 0

check_timing

PtReportTiming > before_opt.rpt

PtReportTiming > after_opt.rpt

write_changes -format ptsh -out cell.sizes  

