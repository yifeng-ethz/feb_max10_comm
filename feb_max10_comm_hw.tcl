package require -exact qsys 16.1

set_module_property NAME feb_max10_comm
set_module_property DISPLAY_NAME "FEB MAX10 Communication Bridge"
set_module_property VERSION 0.1.0
set_module_property DESCRIPTION "Arria-side AVMM CSR bridge for FEB to MAX10 flash programming. Stages one 256-byte page, crosses into the MAX10 link domain through a dual-clock FIFO, and preserves the existing downstream FEBSPI programming contract."
set_module_property GROUP "Mu3e Control Plane/Modules"
set_module_property AUTHOR "Yifeng Wang"
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false
set_module_property ELABORATION_CALLBACK elaborate
set_module_property VALIDATION_CALLBACK validate

proc add_html_text {group_name item_name html_text} {
    add_display_item $group_name $item_name TEXT ""
    set_display_item_property $item_name DISPLAY_HINT html
    set_display_item_property $item_name TEXT $html_text
}

set PAGE_WORDS_CONST              64
set PAGE_BYTES_CONST              256
set CDC_ENTRY_WIDTH_CONST         40
set CSR_LAST_WORD_CONST           0x5F
set CSR_MIN_ADDR_W_CONST          7
set CDC_MIN_ADDR_W_CONST          7
set IP_ID_DEFAULT_CONST           1295067216

set CSR_TABLE_HTML {<html><table border="1" width="100%">
<tr><th>Word</th><th>Byte</th><th>Name</th><th>Access</th><th>Description</th></tr>
<tr><td>0x000</td><td>0x0000</td><td>ID</td><td>RO</td><td>Software-visible IP identifier. Default is ASCII "M10P" but can be overridden from the GUI.</td></tr>
<tr><td>0x001</td><td>0x0004</td><td>VERSION</td><td>RO</td><td>Packed MAJOR.MINOR.PATCH.BUILD value driven from GUI parameters.</td></tr>
<tr><td>0x002</td><td>0x0008</td><td>CTRL</td><td>WO/RO-ack</td><td>Bit 0 issues software reset. Reads return only the reset-pending acknowledgement.</td></tr>
<tr><td>0x003</td><td>0x000C</td><td>STATUS</td><td>RO</td><td>Common ready/busy/fault status.</td></tr>
<tr><td>0x004</td><td>0x0010</td><td>ERR_FLAGS</td><td>RW1C</td><td>Sticky local error bits. Write 1 to clear individual flags.</td></tr>
<tr><td>0x005</td><td>0x0014</td><td>ERR_COUNT</td><td>RO</td><td>Saturating local error counter.</td></tr>
<tr><td>0x006</td><td>0x0018</td><td>SCRATCH</td><td>RW</td><td>Software scratch register.</td></tr>
<tr><td>0x007</td><td>0x001C</td><td>FLASH_ADDR</td><td>RW</td><td>24-bit absolute SPI flash byte address for the next launch.</td></tr>
<tr><td>0x008</td><td>0x0020</td><td>XFER_BYTES</td><td>RW</td><td>Valid byte count for the next page launch. Legal range 1..256.</td></tr>
<tr><td>0x009</td><td>0x0024</td><td>PROG_CTRL</td><td>WO</td><td>Bit 0 START, bit 1 CLEAR_PAGE, bit 2 CLEAR_LAUNCH_FLAGS, bit 3 CLEAR_ADDR.</td></tr>
<tr><td>0x00A</td><td>0x0028</td><td>PROG_STATUS</td><td>RO</td><td>Local launch state plus raw MAX10 programming bits.</td></tr>
<tr><td>0x00B</td><td>0x002C</td><td>STAGED_WORDS</td><td>RO</td><td>Length of the contiguous valid PAGE_DATA prefix starting at word 0.</td></tr>
<tr><td>0x00C</td><td>0x0030</td><td>MAX10_STAT</td><td>RO</td><td>Raw downstream MAX10 programming status mirror.</td></tr>
<tr><td>0x00D</td><td>0x0034</td><td>MAX10_COUNT</td><td>RO</td><td>Raw downstream MAX10 debug/programming count mirror.</td></tr>
<tr><td>0x00E</td><td>0x0038</td><td>LAST_ERROR</td><td>RO</td><td>Most recent error or reset-drain record.</td></tr>
<tr><td>0x020..0x05F</td><td>0x0080..0x017C</td><td>PAGE_DATA[0..63]</td><td>RW</td><td>Staging aperture for one 256-byte flash page.</td></tr>
</table></html>}

proc compute_derived_values {} {
    set csr_addr_w           [get_parameter_value CSR_ADDR_W]
    set cdc_fifo_addr_w      [get_parameter_value CDC_FIFO_ADDR_W]
    set cdc_fifo_depth       [expr {1 << $cdc_fifo_addr_w}]
    set cdc_fifo_bits        [expr {$cdc_fifo_depth * $::CDC_ENTRY_WIDTH_CONST}]
    set page_ram_bits        [expr {$::PAGE_BYTES_CONST * 8}]
    set total_bits           [expr {$page_ram_bits + $cdc_fifo_bits}]
    set total_bytes          [expr {$total_bits / 8}]
    set csr_span_words       [expr {1 << $csr_addr_w}]

    set_parameter_value PAGE_WORDS_DERIVED      $::PAGE_WORDS_CONST
    set_parameter_value PAGE_BYTES_DERIVED      $::PAGE_BYTES_CONST
    set_parameter_value PAGE_RAM_BITS_DERIVED   $page_ram_bits
    set_parameter_value CDC_FIFO_DEPTH_DERIVED  $cdc_fifo_depth
    set_parameter_value CDC_FIFO_BITS_DERIVED   $cdc_fifo_bits
    set_parameter_value TOTAL_RAM_BITS_DERIVED  $total_bits
    set_parameter_value TOTAL_RAM_BYTES_DERIVED $total_bytes
    set_parameter_value CSR_SPAN_WORDS_DERIVED  $csr_span_words

    catch {
        set_display_item_property sizing_html TEXT "<html><b>Derived storage</b><br/>PAGE_DATA RAM: <b>${::PAGE_BYTES_CONST}</b> bytes (<b>${page_ram_bits}</b> bits)<br/>CDC FIFO depth: <b>${cdc_fifo_depth}</b> entries of ${::CDC_ENTRY_WIDTH_CONST} bits<br/>CDC FIFO storage: <b>${cdc_fifo_bits}</b> bits<br/>Total local staging storage: <b>${total_bytes}</b> bytes (<b>${total_bits}</b> bits)<br/>CSR aperture span: <b>${csr_span_words}</b> words</html>"
    }
}

proc validate {} {
    compute_derived_values

    set csr_addr_w           [get_parameter_value CSR_ADDR_W]
    set burstcount_w         [get_parameter_value BURSTCOUNT_W]
    set cdc_fifo_addr_w      [get_parameter_value CDC_FIFO_ADDR_W]
    set build_value          [get_parameter_value BUILD]
    set version_major        [get_parameter_value VERSION_MAJOR]
    set version_minor        [get_parameter_value VERSION_MINOR]
    set version_patch        [get_parameter_value VERSION_PATCH]
    set ip_id_value          [get_parameter_value IP_ID]
    set csr_span_words       [get_parameter_value CSR_SPAN_WORDS_DERIVED]
    set cdc_fifo_depth       [get_parameter_value CDC_FIFO_DEPTH_DERIVED]

    if {$csr_addr_w < $::CSR_MIN_ADDR_W_CONST} {
        send_message error "CSR_ADDR_W must be at least $::CSR_MIN_ADDR_W_CONST to cover registers through word 0x[format %02X $::CSR_LAST_WORD_CONST]."
    }
    if {$csr_span_words <= $::CSR_LAST_WORD_CONST} {
        send_message error "CSR_ADDR_W only exposes $csr_span_words words, which is smaller than the required CSR window ending at word 0x[format %02X $::CSR_LAST_WORD_CONST]."
    }
    if {$burstcount_w < 1 || $burstcount_w > 16} {
        send_message error "BURSTCOUNT_W must stay in the range 1..16."
    }
    if {$cdc_fifo_addr_w < $::CDC_MIN_ADDR_W_CONST} {
        send_message error "CDC_FIFO_ADDR_W must be at least $::CDC_MIN_ADDR_W_CONST so the FIFO can hold one header plus the full 64-word page payload."
    }
    if {$cdc_fifo_depth < ($::PAGE_WORDS_CONST + 1)} {
        send_message error "The CDC FIFO depth is ${cdc_fifo_depth}, but at least [expr {$::PAGE_WORDS_CONST + 1}] entries are required for one header plus a full page."
    }
    if {$build_value < 0 || $build_value > 4095} {
        send_message error "BUILD must stay in the range 0..4095."
    }
    if {$version_major < 0 || $version_major > 255} {
        send_message error "VERSION_MAJOR must stay in the range 0..255."
    }
    if {$version_minor < 0 || $version_minor > 255} {
        send_message error "VERSION_MINOR must stay in the range 0..255."
    }
    if {$version_patch < 0 || $version_patch > 15} {
        send_message error "VERSION_PATCH must stay in the range 0..15."
    }
    if {$ip_id_value < 0 || $ip_id_value > 2147483647} {
        send_message error "IP_ID must stay in the signed 31-bit Platform Designer integer range."
    }
}

proc elaborate {} {
    compute_derived_values

    set debug_level [get_parameter_value DEBUG_LEVEL]

    set_port_property avs_csr_address WIDTH_EXPR [get_parameter_value CSR_ADDR_W]
    set_port_property avs_csr_burstcount WIDTH_EXPR [get_parameter_value BURSTCOUNT_W]
    if {$debug_level > 0} {
        set_interface_property diagnostic ENABLED true
    } else {
        set_interface_property diagnostic ENABLED false
    }
}

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL feb_max10_comm
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file rtl/dcfifo_40x128.vhd VHDL PATH rtl/dcfifo_40x128.vhd
add_fileset_file rtl/max10_spi_split.vhd VHDL PATH rtl/max10_spi_split.vhd
add_fileset_file rtl/max10_link.vhd VHDL PATH rtl/max10_link.vhd
add_fileset_file rtl/max10_controller.vhd VHDL PATH rtl/max10_controller.vhd
add_fileset_file rtl/feb_max10_comm.vhd VHDL PATH rtl/feb_max10_comm.vhd TOP_LEVEL_FILE
add_fileset_file feb_max10_comm.sdc SDC PATH feb_max10_comm.sdc

add_parameter CSR_ADDR_W NATURAL 10
set_parameter_property CSR_ADDR_W DISPLAY_NAME "CSR Address Width"
set_parameter_property CSR_ADDR_W UNITS Bits
set_parameter_property CSR_ADDR_W ALLOWED_RANGES 7:32
set_parameter_property CSR_ADDR_W HDL_PARAMETER true
set_parameter_property CSR_ADDR_W DESCRIPTION "AVMM CSR address width in words. Must cover the PAGE_DATA aperture through word 0x5F."

add_parameter BURSTCOUNT_W NATURAL 9
set_parameter_property BURSTCOUNT_W DISPLAY_NAME "Burstcount Width"
set_parameter_property BURSTCOUNT_W UNITS Bits
set_parameter_property BURSTCOUNT_W ALLOWED_RANGES 1:16
set_parameter_property BURSTCOUNT_W HDL_PARAMETER true
set_parameter_property BURSTCOUNT_W DESCRIPTION "Burstcount width presented to the AVMM slave. Match the upstream sc_hub master."

add_parameter CDC_FIFO_ADDR_W NATURAL 7
set_parameter_property CDC_FIFO_ADDR_W DISPLAY_NAME "CDC FIFO Address Width"
set_parameter_property CDC_FIFO_ADDR_W UNITS Bits
set_parameter_property CDC_FIFO_ADDR_W ALLOWED_RANGES 7:10
set_parameter_property CDC_FIFO_ADDR_W HDL_PARAMETER true
set_parameter_property CDC_FIFO_ADDR_W DESCRIPTION "Dual-clock FIFO depth is 2^CDC_FIFO_ADDR_W entries. One entry is reserved for the launch header; 64 payload words are required for a full page."

add_parameter DEBUG_LEVEL NATURAL 1
set_parameter_property DEBUG_LEVEL DISPLAY_NAME "Debug Level"
set_parameter_property DEBUG_LEVEL UNITS None
set_parameter_property DEBUG_LEVEL ALLOWED_RANGES 0:4
set_parameter_property DEBUG_LEVEL HDL_PARAMETER true
set_parameter_property DEBUG_LEVEL DESCRIPTION {When DEBUG_LEVEL=0 the optional diagnostic conduit is disabled during elaboration. Any nonzero value enables the conduit.}

add_parameter BUILD NATURAL 0
set_parameter_property BUILD DISPLAY_NAME "Build Stamp"
set_parameter_property BUILD UNITS None
set_parameter_property BUILD ALLOWED_RANGES 0:4095
set_parameter_property BUILD HDL_PARAMETER true
set_parameter_property BUILD DESCRIPTION {12-bit build stamp packed into VERSION[11:0].}

add_parameter VERSION_MAJOR NATURAL 0
set_parameter_property VERSION_MAJOR DISPLAY_NAME "Version Major"
set_parameter_property VERSION_MAJOR UNITS None
set_parameter_property VERSION_MAJOR ALLOWED_RANGES 0:255
set_parameter_property VERSION_MAJOR HDL_PARAMETER true

add_parameter VERSION_MINOR NATURAL 1
set_parameter_property VERSION_MINOR DISPLAY_NAME "Version Minor"
set_parameter_property VERSION_MINOR UNITS None
set_parameter_property VERSION_MINOR ALLOWED_RANGES 0:255
set_parameter_property VERSION_MINOR HDL_PARAMETER true

add_parameter VERSION_PATCH NATURAL 0
set_parameter_property VERSION_PATCH DISPLAY_NAME "Version Patch"
set_parameter_property VERSION_PATCH UNITS None
set_parameter_property VERSION_PATCH ALLOWED_RANGES 0:15
set_parameter_property VERSION_PATCH HDL_PARAMETER true

add_parameter IP_ID NATURAL $IP_ID_DEFAULT_CONST
set_parameter_property IP_ID DISPLAY_NAME "IP Identifier"
set_parameter_property IP_ID UNITS None
set_parameter_property IP_ID ALLOWED_RANGES 0:2147483647
set_parameter_property IP_ID HDL_PARAMETER true
set_parameter_property IP_ID DISPLAY_HINT hexadecimal
set_parameter_property IP_ID DESCRIPTION "Software-visible ID register value. Default corresponds to ASCII \"M10P\"."

foreach derived_name {PAGE_WORDS_DERIVED PAGE_BYTES_DERIVED PAGE_RAM_BITS_DERIVED CDC_FIFO_DEPTH_DERIVED CDC_FIFO_BITS_DERIVED TOTAL_RAM_BITS_DERIVED TOTAL_RAM_BYTES_DERIVED CSR_SPAN_WORDS_DERIVED} {
    add_parameter $derived_name NATURAL 0
    set_parameter_property $derived_name HDL_PARAMETER false
    set_parameter_property $derived_name DERIVED true
    set_parameter_property $derived_name VISIBLE false
}

set TAB_CONFIGURATION "Configuration"
set TAB_IDENTITY      "Identity"
set TAB_INTERFACES    "Interfaces"
set TAB_REGMAP        "Register Map"

add_display_item "" $TAB_CONFIGURATION GROUP tab
add_display_item $TAB_CONFIGURATION "Overview" GROUP
add_display_item $TAB_CONFIGURATION "Sizing" GROUP
add_display_item $TAB_CONFIGURATION "Advanced" GROUP

add_html_text "Overview" overview_html "<html><b>Function</b><br/>This IP accepts standard incrementing AVMM bursts from sc_hub, stages one 256-byte flash page, and forwards it onto the existing MAX10 FEBSPI programming chain. The downstream MAX10 firmware contract remains unchanged.<br/><br/><b>Clocking</b><br/>CSR and page staging live in <b>csr_clock</b>. The downstream FEBSPI master lives in <b>link_clock</b>. Launch metadata and payload cross domains through a dedicated dual-clock FIFO.</html>"
add_display_item "Sizing" CSR_ADDR_W parameter
add_display_item "Sizing" BURSTCOUNT_W parameter
add_display_item "Sizing" CDC_FIFO_ADDR_W parameter
add_html_text "Sizing" sizing_html "<html><b>Derived storage</b><br/>Derived RAM sizing is updated by the validation callback.</html>"
add_html_text "Advanced" advanced_html "<html><b>Integration notes</b><br/>1. The PAGE_DATA aperture occupies words <b>0x020..0x05F</b>.<br/>2. The dual-clock FIFO must be large enough for one launch header plus 64 payload words.<br/>3. The conduit exports split in/out/oe signals so top-level board files can own the final tri-state buffers and board-specific pin workarounds.</html>"
add_display_item "Advanced" DEBUG_LEVEL parameter

add_display_item "" $TAB_IDENTITY GROUP tab
add_display_item $TAB_IDENTITY "Versioning" GROUP
add_display_item $TAB_IDENTITY "Register Identity" GROUP

add_html_text "Versioning" versioning_html {<html><b>VERSION register encoding</b><br/>VERSION[31:24] = MAJOR, VERSION[23:16] = MINOR, VERSION[15:12] = PATCH, VERSION[11:0] = BUILD.</html>}
add_display_item "Versioning" VERSION_MAJOR parameter
add_display_item "Versioning" VERSION_MINOR parameter
add_display_item "Versioning" VERSION_PATCH parameter
add_display_item "Versioning" BUILD parameter
add_html_text "Register Identity" identity_html "<html><b>ID register</b><br/>The software-visible ID register is normally ASCII <b>M10P</b>, but can be overridden for integration experiments or derivative products.</html>"
add_display_item "Register Identity" IP_ID parameter

add_display_item "" $TAB_INTERFACES GROUP tab
add_display_item $TAB_INTERFACES "AVMM Slave" GROUP
add_display_item $TAB_INTERFACES "MAX10 Link Conduit" GROUP
add_display_item $TAB_INTERFACES "Diagnostic Conduit" GROUP

add_html_text "AVMM Slave" avmm_html "<html><b>csr_avmm</b><br/>32-bit Avalon-MM slave, word-addressed, no byteenable usage in the RTL, and burstcount-aware for incrementing PAGE_DATA writes.</html>"
add_html_text "MAX10 Link Conduit" conduit_html "<html><b>max10_link</b><br/>Split-port custom link toward the Arria-to-MAX10 SPI-like wires. The board top level should terminate this conduit with explicit tri-state IO buffers.</html>"
add_html_text "Diagnostic Conduit" diagnostic_html "<html><b>diagnostic</b><br/>Optional CSR-domain diagnostic conduit for waveform capture and board bring-up. Set <b>DEBUG_LEVEL=0</b> to disable this interface during elaboration.</html>"

add_display_item "" $TAB_REGMAP GROUP tab
add_display_item $TAB_REGMAP "CSR Window" GROUP
add_html_text "CSR Window" csr_table_html $CSR_TABLE_HTML

# ─── Presets ─────────────────────────────────────────────────────────────────
# Presets are provided via the sibling .qprs file:
#   feb_max10_comm_presets.qprs
#
# Preset 1 — FEB Standard:
#   CSR_ADDR_W=10, BURSTCOUNT_W=9, CDC_FIFO_ADDR_W=7, DEBUG_LEVEL=1
#   Default FEB integration with sc_hub. Diagnostic conduit enabled.
#
# Preset 2 — Production Minimal:
#   CSR_ADDR_W=7, BURSTCOUNT_W=1, CDC_FIFO_ADDR_W=7, DEBUG_LEVEL=0
#   Reduced footprint. Diagnostic conduit disabled.
# ─────────────────────────────────────────────────────────────────────────────

add_interface csr_avmm avalon end
set_interface_property csr_avmm addressUnits WORDS
set_interface_property csr_avmm associatedClock csr_clock
set_interface_property csr_avmm associatedReset csr_reset
set_interface_property csr_avmm bitsPerSymbol 8
set_interface_property csr_avmm burstOnBurstBoundariesOnly false
set_interface_property csr_avmm burstcountUnits WORDS
set_interface_property csr_avmm explicitAddressSpan 0
set_interface_property csr_avmm holdTime 0
set_interface_property csr_avmm linewrapBursts false
set_interface_property csr_avmm maximumPendingReadTransactions 1
set_interface_property csr_avmm maximumPendingWriteTransactions 0
set_interface_property csr_avmm readLatency 0
set_interface_property csr_avmm readWaitTime 0
set_interface_property csr_avmm setupTime 0
set_interface_property csr_avmm timingUnits Cycles
set_interface_property csr_avmm writeWaitTime 0
set_interface_property csr_avmm ENABLED true
set_interface_assignment csr_avmm embeddedsw.configuration.isFlash 0
set_interface_assignment csr_avmm embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment csr_avmm embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment csr_avmm embeddedsw.configuration.isPrintableDevice 0

add_interface_port csr_avmm avs_csr_address address Input 1
add_interface_port csr_avmm avs_csr_read read Input 1
add_interface_port csr_avmm avs_csr_write write Input 1
add_interface_port csr_avmm avs_csr_writedata writedata Input 32
add_interface_port csr_avmm avs_csr_readdata readdata Output 32
add_interface_port csr_avmm avs_csr_readdatavalid readdatavalid Output 1
add_interface_port csr_avmm avs_csr_waitrequest waitrequest Output 1
add_interface_port csr_avmm avs_csr_burstcount burstcount Input 1

add_interface csr_clock clock end
set_interface_property csr_clock ENABLED true
add_interface_port csr_clock csi_csr_clk clk Input 1

add_interface csr_reset reset end
set_interface_property csr_reset associatedClock csr_clock
set_interface_property csr_reset synchronousEdges DEASSERT
set_interface_property csr_reset ENABLED true
add_interface_port csr_reset rsi_csr_reset reset Input 1

add_interface link_clock clock end
set_interface_property link_clock ENABLED true
add_interface_port link_clock csi_link_clk clk Input 1

add_interface link_reset reset end
set_interface_property link_reset associatedClock link_clock
set_interface_property link_reset synchronousEdges DEASSERT
set_interface_property link_reset ENABLED true
add_interface_port link_reset rsi_link_reset reset Input 1

add_interface max10_link conduit end
set_interface_property max10_link associatedClock link_clock
set_interface_property max10_link associatedReset link_reset
set_interface_property max10_link ENABLED true

add_interface_port max10_link coe_max10_spi_csn csn Output 1
add_interface_port max10_link coe_max10_spi_clk clk Output 1
add_interface_port max10_link coe_max10_spi_mosi_in mosi_in Input 1
add_interface_port max10_link coe_max10_spi_mosi_out mosi_out Output 1
add_interface_port max10_link coe_max10_spi_mosi_oe mosi_oe Output 1
add_interface_port max10_link coe_max10_spi_miso_in miso_in Input 1
add_interface_port max10_link coe_max10_spi_miso_out miso_out Output 1
add_interface_port max10_link coe_max10_spi_miso_oe miso_oe Output 1
add_interface_port max10_link coe_max10_spi_d1_in d1_in Input 1
add_interface_port max10_link coe_max10_spi_d1_out d1_out Output 1
add_interface_port max10_link coe_max10_spi_d1_oe d1_oe Output 1
add_interface_port max10_link coe_max10_spi_d2_in d2_in Input 1
add_interface_port max10_link coe_max10_spi_d2_out d2_out Output 1
add_interface_port max10_link coe_max10_spi_d2_oe d2_oe Output 1
add_interface_port max10_link coe_max10_spi_d3_in d3_in Input 1
add_interface_port max10_link coe_max10_spi_d3_out d3_out Output 1
add_interface_port max10_link coe_max10_spi_d3_oe d3_oe Output 1

add_interface diagnostic conduit end
set_interface_property diagnostic associatedClock csr_clock
set_interface_property diagnostic associatedReset csr_reset
set_interface_property diagnostic ENABLED true

add_interface_port diagnostic coe_diag_summary summary Output 32
add_interface_port diagnostic coe_diag_err_flags err_flags Output 32
add_interface_port diagnostic coe_diag_last_error last_error Output 32
add_interface_port diagnostic coe_diag_max10_stat max10_stat Output 32
add_interface_port diagnostic coe_diag_max10_count max10_count Output 32
