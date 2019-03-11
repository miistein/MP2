
proc outputSlacksClockPin {ff} {
    set in_clock_pin [filter_collection [get_pins -of $ff -filter "direction==in"] is_clock_pin==true]
    # paths through that clock_pin (paths that are effected)
    set outslacks [list]
    set out_pin [get_pins -of $ff -filter "direction==out"]
    puts "Output pin: $out_pin"
    set out_slack [get_attri [get_timing_paths -from $out_pin] slack] 
    puts "Output slack: $out_slack"
    return $out_slack
}

## remove all buffers
proc PHASE1 {buffers} {
    set clkBuffers [get_cells clk* -filter "ref_name =~ bf*"]
    foreach_in_collection bf $clkBuffers {                                                                                                           PtRemoveCell $bf                                                                                                                         }
}

proc getFirstFF {ff} {
    set in_pin [filter_collection [get_pins -of $ff -filter "direction==in"] is_clock_pin==false]
    set in_clock_pin [filter_collection [get_pins -of $ff -filter "direction==in"] is_clock_pin==true]
    set inFF [get_timing_paths -from $in_pin]
    if {$inFF==""} {
        return [get_object_name in_clock_pin]
    } else {
        return "skip"
    }
}

## final tune input ff and output ff
proc PHASE2 {} {
    set ffList [get_cells * -filter "is_sequential==true"]
    # filter to find input ff
    foreach_in_collection ff $ffList {
        set temp [getFirstFF $ff]
        puts $temp
    }
    # PtInsertCell pin libCellName 
}

## work on flip flops that are in the paths closest to 0 first, keeping into account loops and that inserting/sizing
## buffers will cause delay along related paths.

proc PHASE3 {FFs} {

}

set ffList [get_cells * -filter "is_sequential==true"]
foreach_in_collection ff $ffList {
    set in_pin [filter_collection [get_pins -of $ff -filter "direction==in"] is_clock_pin==false]
    set in_clock_pin [filter_collection [get_pins -of $ff -filter "direction==in"] is_clock_pin==true]
    set out_pin [get_pins -of $ff -filter "direction==out"]
    set in_slack [get_attri [get_timing_paths -to $in_pin] slack]
    set out_slack [get_attri [get_timing_paths -from $out_pin] slack]
    
    set temp outputSlacksClockPin $ff
    if {$in_slack < 0 && $out_slack > 0} {
	puts "[get_object_name $ff] [get_object_name $in_clock_pin]"
        PtInsertCell [get_object_name $in_clock_pin] bf01f01  
    }
}

set clkBuffers [get_cells clk* -filter "ref_name =~ bf*"]
foreach_in_collection bf $clkBuffers {                                                                                                           PtRemoveCell $bf                                                                                                                         }

