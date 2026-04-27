package require Tcl 8.5

set script_dir [file dirname [info script]]
set helper_file [file normalize [file join $script_dir .. .. .. toolkits infra cmsis_svd lib mu3e_cmsis_svd.tcl]]
source $helper_file

namespace eval ::mu3e::cmsis::spec {}

proc ::mu3e::cmsis::spec::page_data_registers {} {
    set regs {}

    for {set idx 0} {$idx < 64} {incr idx} {
        set name [format "PAGE_DATA_%02d" $idx]
        set offs [format "0x%03X" [expr {0x80 + 4 * $idx}]]
        lappend regs [::mu3e::cmsis::svd::register $name $offs \
            -description [format {Page staging word %d. Byte lane mapping is little-endian: [7:0]=byte 4n+0 through [31:24]=byte 4n+3.} $idx] \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field value 0 32 \
                    -description [format {Raw staged page word %d.} $idx] \
                    -access read-write]]]
    }

    return $regs
}

proc ::mu3e::cmsis::spec::build_device {} {
    set registers [list \
        [::mu3e::cmsis::svd::register ID 0x000 \
            -description {IP identifier magic. Default Rev-A value is ASCII "M10P".} \
            -access read-only \
            -resetValue 0x4D313050 \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description {Packed ASCII identifier.} -access read-only]]] \
        [::mu3e::cmsis::svd::register VERSION 0x004 \
            -description {Packed interface version: [31:24]=major, [23:16]=minor, [15:12]=patch, [11:0]=build.} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field major 24 8 -description {Major version.} -access read-only] \
                [::mu3e::cmsis::svd::field minor 16 8 -description {Minor version.} -access read-only] \
                [::mu3e::cmsis::svd::field patch 12 4 -description {Patch version.} -access read-only] \
                [::mu3e::cmsis::svd::field build 0 12 -description {Build provenance; not part of the software ABI.} -access read-only]]] \
        [::mu3e::cmsis::svd::register CTRL 0x008 \
            -description {Common management control.} \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field sw_reset 0 1 -description {Soft reset pulse.} -access w1s] \
                [::mu3e::cmsis::svd::field reserved 1 31 -description {Reserved, write zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register STATUS 0x00C \
            -description {Common ready/busy/fault/resetting summary.} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field ready 0 1 -description {IP is CSR-accessible and not held in software reset.} -access read-only] \
                [::mu3e::cmsis::svd::field busy 1 1 -description {At least one local programming operation is in flight.} -access read-only] \
                [::mu3e::cmsis::svd::field fault 2 1 -description {Sticky summary: ERR_FLAGS != 0.} -access read-only] \
                [::mu3e::cmsis::svd::field resetting 3 1 -description {Software reset is in progress.} -access read-only] \
                [::mu3e::cmsis::svd::field reserved 4 28 -description {Reserved, read as zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register ERR_FLAGS 0x010 \
            -description {Sticky local error flags.} \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field start_while_busy 0 1 -description {START requested while busy.} -access rw1c] \
                [::mu3e::cmsis::svd::field start_during_reset 1 1 -description {START requested during software reset.} -access rw1c] \
                [::mu3e::cmsis::svd::field addr_missing 2 1 -description {START requested before FLASH_ADDR was valid.} -access rw1c] \
                [::mu3e::cmsis::svd::field xfer_bytes_zero 3 1 -description {XFER_BYTES was zero at START time.} -access rw1c] \
                [::mu3e::cmsis::svd::field xfer_bytes_gt_256 4 1 -description {XFER_BYTES exceeded 256 at START time.} -access rw1c] \
                [::mu3e::cmsis::svd::field page_underrun 5 1 -description {Not enough contiguous page data was staged.} -access rw1c] \
                [::mu3e::cmsis::svd::field link_timeout 6 1 -description {Downstream Arria/MAX10 link timed out.} -access rw1c] \
                [::mu3e::cmsis::svd::field max10_timeout 7 1 -description {MAX10 reported timeout.} -access rw1c] \
                [::mu3e::cmsis::svd::field max10_crcerror 8 1 -description {MAX10 reported CRC error.} -access rw1c] \
                [::mu3e::cmsis::svd::field max10_nstatus_low 9 1 -description {MAX10 reported NSTATUS low.} -access rw1c] \
                [::mu3e::cmsis::svd::field reserved 10 22 -description {Reserved, read as zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register ERR_COUNT 0x014 \
            -description {Saturating count of newly-detected error events.} \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description {Error event count.} -access read-only]]] \
        [::mu3e::cmsis::svd::register SCRATCH 0x018 \
            -description {Diagnostic scratch register with no side effects.} \
            -access read-write \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description {Scratch value.} -access read-write]]] \
        [::mu3e::cmsis::svd::register FLASH_ADDR 0x01C \
            -description {Absolute SPI flash byte address for the next page launch.} \
            -access read-write \
            -fields [list \
                [::mu3e::cmsis::svd::field flash_addr 0 24 -description {Absolute flash byte address.} -access read-write] \
                [::mu3e::cmsis::svd::field reserved 24 8 -description {Reserved, write zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register XFER_BYTES 0x020 \
            -description {Number of valid payload bytes for the next START request. Reset default is 256.} \
            -access read-write \
            -resetValue 0x00000100 \
            -fields [list \
                [::mu3e::cmsis::svd::field xfer_bytes 0 9 -description {Valid payload byte count, legal range 1..256.} -access read-write] \
                [::mu3e::cmsis::svd::field reserved 9 23 -description {Reserved, write zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register PROG_CTRL 0x024 \
            -description {Write-one pulse programming commands. Reads are not meaningful and should be avoided.} \
            -access write-only \
            -fields [list \
                [::mu3e::cmsis::svd::field start 0 1 -description {Launch one programming transaction.} -access write-only] \
                [::mu3e::cmsis::svd::field clear_page 1 1 -description {Clear the page aperture and staged-word count.} -access write-only] \
                [::mu3e::cmsis::svd::field clear_status 2 1 -description {Clear LAST_ERROR and sticky programming status.} -access write-only] \
                [::mu3e::cmsis::svd::field clear_addr 3 1 -description {Clear the local address-valid latch and zero FLASH_ADDR.} -access write-only] \
                [::mu3e::cmsis::svd::field reserved 4 28 -description {Reserved, write zero.} -access write-only]]] \
        [::mu3e::cmsis::svd::register PROG_STATUS 0x028 \
            -description {Programming engine status and mirrored MAX10 status summary.} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field ready 0 1 -description {Local engine is idle and launch-eligible.} -access read-only] \
                [::mu3e::cmsis::svd::field busy 1 1 -description {Programming launch is in progress.} -access read-only] \
                [::mu3e::cmsis::svd::field page_ready 2 1 -description {Enough contiguous page data is staged for the current XFER_BYTES.} -access read-only] \
                [::mu3e::cmsis::svd::field addr_valid 3 1 -description {FLASH_ADDR has been written since reset or clear.} -access read-only] \
                [::mu3e::cmsis::svd::field len_valid 4 1 -description {XFER_BYTES is in the legal range 1..256.} -access read-only] \
                [::mu3e::cmsis::svd::field cdc_busy 5 1 -description {Metadata or payload handoff across domains is in progress.} -access read-only] \
                [::mu3e::cmsis::svd::field launch_accepted 6 1 -description {Sticky until clear_status; most recent START was accepted.} -access read-only] \
                [::mu3e::cmsis::svd::field launch_done 7 1 -description {Sticky until clear_status; most recent accepted START finished.} -access read-only] \
                [::mu3e::cmsis::svd::field max10_arriawriting 8 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[0].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_spi_busy 9 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[1].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_fifo_empty 10 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[14].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_fifo_full 11 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[15].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_conf_done 12 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[16].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_nstatus 13 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[17].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_timeout 14 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[18].} -access read-only] \
                [::mu3e::cmsis::svd::field max10_crcerror 15 1 -description {Raw mirror of MAX10 PROGRAMMING_STATUS[19].} -access read-only] \
                [::mu3e::cmsis::svd::field engine_state 16 8 -description {Implementation-defined local debug state.} -access read-only] \
                [::mu3e::cmsis::svd::field reserved 24 8 -description {Reserved, read as zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register STAGED_WORDS 0x02C \
            -description {Number of contiguous valid words staged from PAGE_DATA[0].} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field value 0 7 -description {Count of contiguous valid words.} -access read-only] \
                [::mu3e::cmsis::svd::field reserved 7 25 -description {Reserved, read as zero.} -access read-only]]] \
        [::mu3e::cmsis::svd::register MAX10_STAT 0x030 \
            -description {Raw mirror of MAX10 PROGRAMMING_STATUS.} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field arria_writing 0 1 -description {Arria writing in progress.} -access read-only] \
                [::mu3e::cmsis::svd::field spi_busy 1 1 -description {SPI flash engine busy.} -access read-only] \
                [::mu3e::cmsis::svd::field reserved0 2 12 -description {Reserved or implementation-defined.} -access read-only] \
                [::mu3e::cmsis::svd::field fifo_empty 14 1 -description {Programming FIFO empty.} -access read-only] \
                [::mu3e::cmsis::svd::field fifo_full 15 1 -description {Programming FIFO full.} -access read-only] \
                [::mu3e::cmsis::svd::field conf_done 16 1 -description {CONF_DONE state.} -access read-only] \
                [::mu3e::cmsis::svd::field nstatus 17 1 -description {NSTATUS state.} -access read-only] \
                [::mu3e::cmsis::svd::field timeout 18 1 -description {Timeout sticky flag.} -access read-only] \
                [::mu3e::cmsis::svd::field crcerror 19 1 -description {CRC error sticky flag.} -access read-only] \
                [::mu3e::cmsis::svd::field reserved1 20 4 -description {Reserved or implementation-defined.} -access read-only] \
                [::mu3e::cmsis::svd::field max10_debug 24 8 -description {MAX10 FPP debug byte.} -access read-only]]] \
        [::mu3e::cmsis::svd::register MAX10_COUNT 0x034 \
            -description {Raw mirror of MAX10 PROGRAMMING_COUNT. Debug only.} \
            -access read-only \
            -fields [list [::mu3e::cmsis::svd::field value 0 32 -description {Raw MAX10 count/debug word.} -access read-only]]] \
        [::mu3e::cmsis::svd::register LAST_ERROR 0x038 \
            -description {Last error code and debug snapshot.} \
            -access read-only \
            -fields [list \
                [::mu3e::cmsis::svd::field error_code 0 8 -description {Last error code.} -access read-only] \
                [::mu3e::cmsis::svd::field engine_state 8 8 -description {Local engine state captured at failure.} -access read-only] \
                [::mu3e::cmsis::svd::field staged_words 16 8 -description {Staged word count captured at failure.} -access read-only] \
                [::mu3e::cmsis::svd::field max10_debug 24 8 -description {MAX10 debug byte captured at failure.} -access read-only]]]]

    set registers [concat $registers [::mu3e::cmsis::spec::page_data_registers]]

    return [::mu3e::cmsis::svd::device MU3E_MAX10_PROG_AVMM \
        -version 0.2.0 \
        -description {CMSIS-SVD description of the max10_prog_avmm control aperture. BaseAddress is 0 because this file describes the relative CSR aperture of the IP; system integration supplies the live slave base address.} \
        -peripherals [list \
            [::mu3e::cmsis::svd::peripheral MAX10_PROG_AVMM_CSR 0x0 \
                -description {Relative CSR aperture for standard-AVMM MAX10 page programming. The sparse gaps between LAST_ERROR and PAGE_DATA are reserved.} \
                -groupName MU3E_MAX10_PROG \
                -addressBlockSize 0x1000 \
                -registers $registers]]]
}

if {[info exists ::argv0] &&
    [file normalize $::argv0] eq [file normalize [info script]]} {
    set out_path [file join $script_dir max10_prog_avmm.svd]
    if {[llength $::argv] >= 1} {
        set out_path [lindex $::argv 0]
    }
    ::mu3e::cmsis::svd::write_device_file \
        [::mu3e::cmsis::spec::build_device] $out_path
}
