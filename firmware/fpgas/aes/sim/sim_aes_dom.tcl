# Vivado TCL Script for AES-DOM Simulation
# 
# Usage:
#   vivado -mode batch -source sim_aes_dom.tcl
#   OR
#   vivado -mode gui -source sim_aes_dom.tcl
#
# This script creates a simulation project, adds all sources,
# and runs the simulation.

# Configuration
set project_name "aes_dom_sim"
set project_dir "./vivado_sim"
set part "xc7a35tcpg236-1"  # CW305 Artix-7

# Get script directory
set script_dir [file dirname [info script]]
set hdl_dir [file normalize "$script_dir/../hdl"]
set aes_dom_dir [file normalize "$script_dir/../../../../aes-dom"]

puts "=========================================="
puts "AES-DOM Simulation Setup"
puts "=========================================="
puts "HDL directory: $hdl_dir"
puts "AES-DOM directory: $aes_dom_dir"
puts "=========================================="

# Create project
if {[file exists $project_dir]} {
    file delete -force $project_dir
}
create_project $project_name $project_dir -part $part

# Add VHDL sources from aes-dom
set vhdl_files {
    masked_aes_pkg.vhdl
    gf2_mul.vhdl
    shared_mul_gf2.vhdl
    real_dom_shared_mul_gf2.vhdl
    shared_mul_gf4.vhdl
    real_dom_shared_mul_gf4.vhdl
    shared_mul.vhdl
    lin_map.vhdl
    square_scaler.vhdl
    masked_mul.vhdl
    inverter.vhdl
    aes_sbox.vhdl
    rcon.vhdl
    aes_key_regs.vhdl
    aes_state_regs.vhdl
    mix_columns.vhdl
    aes_ctrl_lsfr.vhdl
    aes_top.vhdl
}

puts "\nAdding VHDL sources..."
foreach f $vhdl_files {
    set filepath "$aes_dom_dir/$f"
    if {[file exists $filepath]} {
        add_files -norecurse $filepath
        set_property file_type {VHDL 2008} [get_files $filepath]
        puts "  Added: $f"
    } else {
        puts "  WARNING: File not found: $filepath"
    }
}

# Add VHDL wrapper
set vhdl_wrapper "$hdl_dir/aes_dom_verilog_wrapper.vhdl"
if {[file exists $vhdl_wrapper]} {
    add_files -norecurse $vhdl_wrapper
    set_property file_type {VHDL 2008} [get_files $vhdl_wrapper]
    puts "  Added: aes_dom_verilog_wrapper.vhdl"
}

# Add Verilog sources
set verilog_files {
    aes_dom_wrapper.v
}

puts "\nAdding Verilog sources..."
foreach f $verilog_files {
    set filepath "$hdl_dir/$f"
    if {[file exists $filepath]} {
        add_files -norecurse $filepath
        puts "  Added: $f"
    } else {
        puts "  WARNING: File not found: $filepath"
    }
}

# Add testbench
set tb_file "$script_dir/tb_aes_dom_wrapper.v"
if {[file exists $tb_file]} {
    add_files -fileset sim_1 -norecurse $tb_file
    puts "  Added testbench: tb_aes_dom_wrapper.v"
}

# Set top module for simulation
set_property top tb_aes_dom_wrapper [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n=========================================="
puts "Running simulation..."
puts "=========================================="

# Launch simulation
launch_simulation

# Run simulation
run all

puts "\n=========================================="
puts "Simulation complete!"
puts "=========================================="

# Keep GUI open if running in GUI mode
# Comment out the following line if you want the GUI to stay open
# close_project
