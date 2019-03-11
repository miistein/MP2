proc getDefaultBuffers {} {
    set defaultBuffers [get_cells clk* -filter "ref_name =~ bf*"]
    return $defaultBuffers
}

proc getAddedBuffers {} {
    set addedBuffers [get_cells eco* -filter "ref_name =~ bf*"]
    return $addedBuffers
}
# Remove cells on clock tree
proc removeBuffers {} {
    puts "starting PHASE 1"
    # ref_name wildcard gets all buffers. Initially there is a buffer on every clock pin.
    foreach_in_collection bf [get_cells clk* -filter "ref_name =~ bf*"] {
        PtRemoveCell $bf
    }
}

# add buffers at first and last. Then run fineTune to get the best choice of buffers -
# There are {buffer exists, buffer dne} {s,m,f} {01,02,03,04,06,08,10,20,40,80,160} choices.
# we also need to cascade the buffers as we add them, see 
# also remember to use report_bottleneck, that may help if we can check if it is in the collection with filter_collection
# Generally speaking, a single buffer does not have that huge timing difference between best case and worst case. You must cascade a series of buffers, right? However, when cascading buffers, it's not a good idea to connect buffers with the same drive strength, say, all the buffers are in 12X. The reason is the input signal may not have enough strength to drive the initial stage cause the input capacitance of 12X buffer is relatively high. The better choice is to increase the buffer size progressively and tune the total delay into the desired zone. 
proc tryBuffersAtClockPins {} {
    puts "starting PHASE 2"
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

    # tests for usb phys
    if {[sizeof_collection $input_clock_pins]!=55]} {error "input clock pins should be 55"}
    if {[sizeof_collection $output_clock_pins]!=15]} {error "output clock pins should be 15"}
    if {[sizeof_collection $other_clock_pins]!=28]} {error "other clock pins should be 28"}
}

removeBuffers
tryBuffersAtClockPins
