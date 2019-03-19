# TODOS
# - Better ordering for the list. Update the rest of the list on every iteration.
# - sizing of the buffers. Which sequence is the best? 01,02,03,..80. Can I try using slow, then try medium, then fast?
# - sorting of the clock pins. I really want the least violations (which I have) as well as the greatest slack

# TONIGHT
#  Do tonight: fix bug and implement the following - (dont worry about what my ordering is for the list). Actually I may want better ordering for the list too. I want to update the list on every iteration. Because the number of violations can increase as I add buffers to clock pins... I really have no idea how to do this though. 
#
# maybe use getattr buffer size for this information
#  01 -> 02 ... 40 -> on next iteration have a counter I attatch to function call . What do I want? Probably just 40 -> 40 -> 40, or whatever goes along with increasing. 

# Remove cells on clock tree
#

# setting for report timing
set timing_save_pin_arrival_and_slack true

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


set prev [list]

proc col2list { col } {
   set list ""
   foreach_in_collection c $col { lappend list [get_object_name $c] }
   return $list
}

proc sortByBottleneck {clock_pins} {
    # removing from collection seems to help a lot. adding on the violations at the end? Haven't tried whether this helps.
    report_bottleneck -from $clock_pins -max_cells 17261 -max_paths 10000 -nworst_paths 100 -nosplit > temp.rpt
    set inFile [open temp.rpt r]
    set info "skip"
    set cps [list]
    while {[gets $inFile line]>=0} {
        if {[regexp {ff} $line]} {
            set regCellName [lindex $line 0]
            set numViolationsOnPath [lindex $line 2]
            set temp "$regCellName/CP"
            lappend cps $temp
        }
    }
    set reversecps [lreverse $cps]
    # remove duplicate elements from list
    set sortedcps [lsort -unique $reversecps]

    # Only return the clock pin for now but can get # violations with index 2
    set remove_sorted [remove_from_collection $clock_pins $sortedcps]
    set firsthalf [col2list $remove_sorted]
    
    #set lensorted [llength remove_sorted]
    #if {[sizeof_collection $clock_pins] == $lensorted} {
    #    return $firsthalf
    #}
    close $inFile
    return [list {*}$firsthalf {*}$sortedcps]
}

proc totalViolations {} {
    report_constraint -significant_digits 1 -max_delay -all_violators -nosplit > temp2.rpt
    set vio_num 0
    set inFile [open temp2.rpt r]
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

#proc getBufferCell {cp} {
#    set BufferCell [get_object_name [index_collection [filter_collection [all_fanin -to $cp -only_cells] "is_sequential == false"] end]]
#    return $BufferCell
#}

global global_numinsertions
set global_numinsertions -1
proc insertCell {clockpin vtchoice sizechoice} {
    PtInsertCell $clockpin "bf01${vtchoice}${sizechoice}"
    global global_numinsertions
    set global_numinsertions [expr $global_numinsertions+1]
}

proc removeLastBuffer {clockpin} {
    global global_numinsertions
    #set lastBuffer [get_object_name [index_collection [get_cells eco_$global_numinsertions -filter "ref_name =~ bf*"] 0]]
    set lastBuffer "eco_cell_$global_numinsertions"
    PtRemoveCell $lastBuffer
}

proc naiveBuffersAtClockPins {clock_pins initialViolations all_clock_pins} {
    set vt "s m f"
    set sizes "01 02 03 04 06 08 10 20 40 80"

    puts "starting a new buffer run ... "
    puts "LENGTH OF INPUT LIST IS [sizeof_collection $clock_pins]"
    puts "LENGTH OF LIST IS [llength [sortByBottleneck $clock_pins]] (should be 55,15,28)"
    
    set iterations [llength [sortByBottleneck $clock_pins]]
    set clockpins [sortByBottleneck $clock_pins]
    set en 1
    set i -1
    while {$en} {
        incr i
        set clockpin [lindex $clockpins 0]
        set clockpins [lreplace [sortByBottleneck $clock_pins] 0 $i]
        if {[llength $clockpins]==0} {set en 0}
        for {set j 0} {$j <= 9} {incr j} {
            set vtchoice [lindex $vt 2]
            set sizechoice [lindex $sizes $j]

            insertCell $clockpin $vtchoice $sizechoice
            set total [totalViolations]
            puts $total
            puts $initialViolations
            if {$total > $initialViolations} {
                # recover from insertion
                removeLastBuffer $clockpin
                break
            } else {
                set initialViolations $total
            }
        
            incr j
        }
        # IDEA: 
        # clockpin got through without breaking. Appending it to a new list of clockpins so we can do this all over again.
        # lappend
    }

    return $initialViolations
}

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
for {set j 0} {$j <= 9} {incr j} {
    set v [naiveBuffersAtClockPins $input_clock_pins $v $input_clock_pins]
    set v [naiveBuffersAtClockPins $output_clock_pins $v $output_clock_pins]
    set v [naiveBuffersAtClockPins $other_clock_pins $v $other_clock_pins]
}
