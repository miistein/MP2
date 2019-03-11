proc getAddedBuffers {} {
    set addedBuffers [get_cells eco* -filter "ref_name =~ bf*"]
    return $addedBuffers
}

# Remove cells on clock tree
proc removeBuffers {} {
    puts "removing buffers"
    # ref_name wildcard gets all buffers. Initially there is a buffer on every clock pin.
    set defaultBuffers [get_cells clk* -filter "ref_name =~ bf*"]
    foreach_in_collection bf $defaultBuffers {
        PtRemoveCell $bf
    }
}

proc testCollectionsUSBPHYS {input_clock_pins output_clock_pins other_clock_pins} {
    # tests for usb phys
    set x [sizeof_collection $input_clock_pins]
    if {[expr {$x!=55}]} {error "input clock pins should be 55"}
    set x [sizeof_collection $output_clock_pins]
    if {[expr {$x!=15}]} {error "output clock pins should be 15"}
    set x [sizeof_collection $other_clock_pins]
    if {[expr {$x!=28}]} {error "other clock pins should be 28"}
}

proc reportBottleneckCell {clock_pins} {
    report_bottleneck -from $clock_pins -nosplit > temp.rpt
    set inFile [open temp.rpt]
    set info "skip"
    while {[gets $inFile line]>=0} {
        if {[regexp {ff} $line]} {
            set info $line
            break
        }
    }
    close $inFile

    if {$info == "skip"} {
        return $info
    }

    # Only return the clock pin for now but can get # violations with index 2
    set regCellName [lindex $info 0]
    return "$regCellName/CP"
}

proc reportBottleneckCells {clock_pins} {
    report_bottleneck -from $clock_pins -nosplit > temp2.rpt
    set inFile [open temp2.rpt]
    set info [list]
    while {[gets $inFile line]>=0} {
        if {[regexp {ff} $line]} {
            # Only return the clock pin for now but can get # violations with index 2
            set regCellName [lindex $line 0]
            set numViolationsImpacted [lindex $line 2]
            lappend info [list "$regCellName/CP" $numViolationsImpacted]
        }   
    }
    close $inFile

    if {[llength $info] == 0} {
        return "skip"
    } else {
        return $info
    }
}

proc totalViolations {} {
    report_constraint -max_delay -all_violators -nosplit > temp3.rpt
    set vio_num 0
    set inFile [open temp3.rpt]
    while {[gets $inFile line]>=0} {
        if {[regexp {VIOLATED} $line]} {
            incr vio_num
        }
    }
    close $inFile
    
    return $vio_num
}


# moved from pt_cmds 
proc PtInsertCell {pin_name lib_cell_name} {
    global GLOBAL_CNT
    insert_buffer $pin_name $lib_cell_name -new_cell_name eco_cell_${GLOBAL_CNT} -new_net_name eco_net_${GLOBAL_CNT}

    puts "New buffer eco_cell_${GLOBAL_CNT} (${lib_cell_name}) is inserted to the pin $pin_name"
    incr GLOBAL_CNT
    return 0
}

proc getBufferCell {cp} {
    set BufferCell [get_object_name [index_collection [filter_collection [all_fanin -to $cp -only_cells] "is_sequential == false"] end]]
    return $BufferCell
}

proc naiveBuffersAtClockPins {clock_pins initialViolations} {
    puts "adding buffers to clock pins"
    set temp [reportBottleneckCell $clock_pins]
    puts "top bottlneck cell - $temp"
    set temp [reportBottleneckCells $clock_pins]
    puts "NOT USING but reports all bottleneck cell ties and corresponding # violations in the same path- $temp"

    set vt "s m f"
    # I don't try anything >= 80
    set sizes "01 02 03 04 06 08 10 20 40"

    set j 0
    set cp [reportBottleneckCell $clock_pins]
    for {set i 0} {$i < 1000} {incr i} {
        set vtchoice [lindex $vt 2]
        puts "vt $vtchoice"
        set sizechoice [lindex $sizes $j]
        puts "size $sizechoice"

        # try choice. starting from small drive strength to large drive strength.
        PtInsertCell $cp "bf01${vtchoice}${sizechoice}"
        set total [totalViolations]
        puts $total
        puts $initialViolations
        if {$total >= $initialViolations} {
            # revert
            PtRemoveCell [getBufferCell $cp]
            # get new clock pin
            set clock_pins [remove_from_collection $clock_pins $cp]
            # problem I am having is I need a list of "already tried" pins so add this to reportBottlneckCell function call
            set cp [reportBottleneckCell $clock_pins]
            if {$cp=="skip"} {break}
            continue
        } else {
            set initialViolations $total
        } 

        if {$j >= ([llength $sizes]-2)} {
            set j 0
            set clock_pins [remove_from_collection $clock_pins $cp]
            set cp [reportBottleneckCell $clock_pins]
            if {$cp=="skip"} {break}
            continue
        } else {
            incr j 2
        }
    }

    return $initialViolations
}

#set timing_save_pin_arrival_and_slack true

removeBuffers

puts "adding buffers"
set input_wires [remove_from_collection [all_inputs] clk]
set regs [get_pins -of [all_fanout -from $input_wires -endpoints_only -only_cells]]

# collections of input/output clock pins (flip flops at the input/output have no loops)
set collection_of_input_clock_pins [filter_collection $regs is_clock_pin==true]
set collection_of_output_clock_pins [filter_collection [get_pins -of [all_fanin -to [all_outputs] -only_cells]] is_clock_pin==true]

# remove duplicates
if {[sizeof_collection $collection_of_input_clock_pins] <= [sizeof_collection $collection_of_output_clock_pins]} {
    set collection_of_input_clock_pins [remove_from_collection $collection_of_input_clock_pins $collection_of_output_clock_pins]
} else {
    set collection_of_output_clock_pins [remove_from_collection $collection_of_output_clock_pins $collection_of_input_clock_pins]
}

set temp $collection_of_input_clock_pins
set collection_of_input_output_clock_pins [add_to_collection $temp $collection_of_output_clock_pins]

set collection_of_all_clock_pins [filter_collection [all_fanout -from [all_inputs] -endpoints_only  ] is_clock_pin==true]

# collection of clock pins in the middle of 
set collection_of_middle_clock_pins [remove_from_collection $collection_of_all_clock_pins $collection_of_input_output_clock_pins]

set input_clock_pins $collection_of_input_clock_pins
set output_clock_pins $collection_of_output_clock_pins
set other_clock_pins $collection_of_middle_clock_pins

testCollectionsUSBPHYS $input_clock_pins $output_clock_pins $other_clock_pins
                                                                                                                        
# niave implementation of adding buffers to clock pins that contribute the most to violations
# start from input pins, then output pins, then other pins. 

# just run through every clock pin that contributes to violations. Never traces backwards.

set v [totalViolations]
set v [naiveBuffersAtClockPins $input_clock_pins $v]
set v [naiveBuffersAtClockPins $output_clock_pins $v]
set v [naiveBuffersAtClockPins $other_clock_pins $v]
