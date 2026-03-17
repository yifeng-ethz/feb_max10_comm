# feb_max10_comm.sdc
#
# CDC timing intent for the local launch queue between:
# - csr_clock domain (write side)
# - link_clock domain (read side)
#
# This file constrains only the dedicated queue FIFO and the explicit toggle
# synchronizers inside feb_max10_comm. The generated system-level Qsys FIFOs
# contribute their own vendor SDC files separately.
#
# Important:
# 1. Do not globally false-path csr_clock and link_clock for this IP.
# 2. These constraints are conditional and silently skip if the expected
#    primitive register names are not present in the netlist.

proc fm10_apply_delay_pair {from_nodes to_nodes} {
    if {[get_collection_size $from_nodes] > 0 && [get_collection_size $to_nodes] > 0} {
        set_max_delay -from $from_nodes -to $to_nodes 100
        set_min_delay -from $from_nodes -to $to_nodes -100
    }
}

proc fm10_apply_net_delay_pair {from_nodes to_nodes} {
    if {[get_collection_size $from_nodes] > 0 && [get_collection_size $to_nodes] > 0} {
        set_net_delay -max 2 -from $from_nodes -to $to_nodes
        set_net_delay -min 0 -from $from_nodes -to $to_nodes
    }
}

proc fm10_get_registers_any {patterns} {
    set nodes [get_registers -nowarn __fm10_no_match__]
    foreach pattern $patterns {
        set matches [get_registers -nowarn $pattern]
        if {[get_collection_size $matches] > 0} {
            set nodes [add_to_collection $nodes $matches]
        }
    }
    return $nodes
}

proc constrain_fm10_queue_fifo {} {
    set wr_gray_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|in_wr_ptr_gray[*]
        *|max10_controller:*|u_cdc_fifo|u_fifo*|in_wr_ptr_gray[*]
    }]
    set wr_sync_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|*write_crosser*|*din_s1
        *|max10_controller:*|u_cdc_fifo|u_fifo*|*write_crosser*|*din_s1
    }]
    set rd_gray_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|out_rd_ptr_gray[*]
        *|max10_controller:*|u_cdc_fifo|u_fifo*|out_rd_ptr_gray[*]
    }]
    set rd_sync_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|*read_crosser*|*din_s1
        *|max10_controller:*|u_cdc_fifo|u_fifo*|*read_crosser*|*din_s1
    }]

    fm10_apply_delay_pair     $wr_gray_regs $wr_sync_regs
    fm10_apply_delay_pair     $rd_gray_regs $rd_sync_regs
    fm10_apply_net_delay_pair $wr_gray_regs $wr_sync_regs
    fm10_apply_net_delay_pair $rd_gray_regs $rd_sync_regs

    set mem_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|mem*
        *|max10_controller:*|u_cdc_fifo|u_fifo*|mem*
    }]
    set payload_regs [fm10_get_registers_any {
        *|feb_max10_comm:*|u_cdc_fifo|u_fifo*|internal_out_payload*
        *|max10_controller:*|u_cdc_fifo|u_fifo*|internal_out_payload*
    }]
    if {[get_collection_size $mem_regs] > 0 && [get_collection_size $payload_regs] > 0} {
        set_net_delay -max 2 -from $mem_regs -to $payload_regs
        set_net_delay -min 0 -from $mem_regs -to $payload_regs
    }
}

proc constrain_fm10_toggle_syncs {} {
    set launch_src [fm10_get_registers_any {
        *|max10_controller:*|cdc_pusher*launch_toggle
        *|feb_max10_comm:*|cdc_pusher*launch_toggle
    }]
    set launch_sync [fm10_get_registers_any {
        *|max10_controller:*|max_master*launch_toggle_sync*
        *|feb_max10_comm:*|max_master*launch_toggle_sync*
    }]
    set done_src [fm10_get_registers_any {
        *|max10_controller:*|max_master*done_toggle
        *|feb_max10_comm:*|max_master*done_toggle
    }]
    set done_meta [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*done_toggle_meta
        *|feb_max10_comm:*|csr_slave*done_toggle_meta
    }]
    set done_sync [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*done_toggle_sync
        *|feb_max10_comm:*|csr_slave*done_toggle_sync
    }]

    fm10_apply_delay_pair     $launch_src $launch_sync
    fm10_apply_delay_pair     $done_src   $done_meta
    fm10_apply_delay_pair     $done_meta  $done_sync
    fm10_apply_net_delay_pair $launch_src $launch_sync
    fm10_apply_net_delay_pair $done_src   $done_meta
    fm10_apply_net_delay_pair $done_meta  $done_sync
}

proc constrain_fm10_reset_syncs {} {
    set reset_src [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*resetting
        *|feb_max10_comm:*|csr_slave*resetting
    }]
    set reset_sync0 [fm10_get_registers_any {
        *|max10_controller:*|max_master*reset_sync[0]
        *|feb_max10_comm:*|max_master*reset_sync[0]
    }]

    fm10_apply_delay_pair     $reset_src  $reset_sync0
    fm10_apply_net_delay_pair $reset_src  $reset_sync0
}

proc constrain_fm10_debug_mirror_syncs {} {
    set stat_src [fm10_get_registers_any {
        *|max10_controller:*|max_master*max10_stat[*]
        *|feb_max10_comm:*|max_master*max10_stat[*]
    }]
    set stat_meta [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*stat_meta[*]
        *|feb_max10_comm:*|csr_slave*stat_meta[*]
    }]
    set count_src [fm10_get_registers_any {
        *|max10_controller:*|max_master*max10_count[*]
        *|feb_max10_comm:*|max_master*max10_count[*]
    }]
    set count_meta [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*count_meta[*]
        *|feb_max10_comm:*|csr_slave*count_meta[*]
    }]
    set err_flags_src [fm10_get_registers_any {
        *|max10_controller:*|max_master*err_flags[*]
        *|feb_max10_comm:*|max_master*err_flags[*]
    }]
    set err_flags_meta [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*err_flags_meta[*]
        *|feb_max10_comm:*|csr_slave*err_flags_meta[*]
    }]
    set err_code_src [fm10_get_registers_any {
        *|max10_controller:*|max_master*err_code[*]
        *|feb_max10_comm:*|max_master*err_code[*]
    }]
    set err_code_meta [fm10_get_registers_any {
        *|max10_controller:*|csr_slave*err_code_meta[*]
        *|feb_max10_comm:*|csr_slave*err_code_meta[*]
    }]

    fm10_apply_delay_pair     $stat_src      $stat_meta
    fm10_apply_delay_pair     $count_src     $count_meta
    fm10_apply_delay_pair     $err_flags_src $err_flags_meta
    fm10_apply_delay_pair     $err_code_src  $err_code_meta
    fm10_apply_net_delay_pair $stat_src      $stat_meta
    fm10_apply_net_delay_pair $count_src     $count_meta
    fm10_apply_net_delay_pair $err_flags_src $err_flags_meta
    fm10_apply_net_delay_pair $err_code_src  $err_code_meta
}

constrain_fm10_queue_fifo
constrain_fm10_toggle_syncs
constrain_fm10_reset_syncs
constrain_fm10_debug_mirror_syncs
