`timescale 1ns/1ps
import uvm_pkg::*;
import feb_max10_comm_pkg::*;

module feb_max10_comm_uvm_tb;
  localparam int unsigned CSR_ADDR_W   = 10;
  localparam int unsigned BURSTCOUNT_W = 9;
  localparam int unsigned DEBUG_LEVEL  = 1;
  localparam string       DEFAULT_UVM_TEST = "UVM_003_FULL_CHAIN";

  logic csr_clk   = 1'b0;
  logic link_clk  = 1'b0;
  logic max10_clk = 1'b0;

  // Shared virtual interface carrying clocks, CSR pins, injections, and probes.
  feb_max10_comm_if tb_if (
    .csr_clk(csr_clk),
    .link_clk(link_clk),
    .max10_clk(max10_clk)
  );

  // Clock generation comes from the interface timing knobs so matrix tests can
  // vary CSR/link ratios without editing the top-level harness.
  always #(tb_if.csr_half_period)  csr_clk   = ~csr_clk;
  always #(tb_if.link_half_period) link_clk  = ~link_clk;
  always #(tb_if.max10_half_period) max10_clk = ~max10_clk;

  feb_max10_comm_model_wrapper #(
    .CSR_ADDR_W(CSR_ADDR_W),
    .BURSTCOUNT_W(BURSTCOUNT_W),
    .DEBUG_LEVEL(DEBUG_LEVEL)
  ) dut (
    .csi_csr_clk           (csr_clk),
    .csi_link_clk          (link_clk),
    .csi_max10_clk         (max10_clk),
    .rsi_csr_reset         (tb_if.rsi_csr_reset),
    .rsi_link_reset        (tb_if.rsi_link_reset),
    .rsi_max10_reset_n     (tb_if.rsi_max10_reset_n),
    .avs_csr_address       (tb_if.avs_csr_address),
    .avs_csr_read          (tb_if.avs_csr_read),
    .avs_csr_write         (tb_if.avs_csr_write),
    .avs_csr_writedata     (tb_if.avs_csr_writedata),
    .avs_csr_readdata      (tb_if.avs_csr_readdata),
    .avs_csr_readdatavalid (tb_if.avs_csr_readdatavalid),
    .avs_csr_waitrequest   (tb_if.avs_csr_waitrequest),
    .avs_csr_burstcount    (tb_if.avs_csr_burstcount),
    .inj_hold_arriawriting (tb_if.inj_hold_arriawriting),
    .inj_force_timeout     (tb_if.inj_force_timeout),
    .inj_force_crcerror    (tb_if.inj_force_crcerror),
    .inj_force_nstatus_low (tb_if.inj_force_nstatus_low),
    .diag_summary          (tb_if.diag_summary),
    .diag_err_flags        (tb_if.diag_err_flags),
    .diag_last_error       (tb_if.diag_last_error),
    .diag_max10_stat       (tb_if.diag_max10_stat),
    .diag_max10_count      (tb_if.diag_max10_count),
    .mon_link_csn          (tb_if.mon_link_csn),
    .mon_link_clk          (tb_if.mon_link_clk),
    .mon_link_mosi         (tb_if.mon_link_mosi),
    .mon_link_miso         (tb_if.mon_link_miso),
    .mon_link_d1           (tb_if.mon_link_d1),
    .mon_link_d2           (tb_if.mon_link_d2),
    .mon_link_d3           (tb_if.mon_link_d3),
    .dbg_status            (tb_if.dbg_status),
    .dbg_flash_w_cnt       (tb_if.dbg_flash_w_cnt),
    .dbg_control           (tb_if.dbg_control),
    .dbg_addr_from_arria   (tb_if.dbg_addr_from_arria),
    .dbg_arria_addr        (tb_if.dbg_arria_addr),
    .dbg_arria_rw          (tb_if.dbg_arria_rw),
    .dbg_arria_next_data   (tb_if.dbg_arria_next_data),
    .dbg_arria_word_from_arria(tb_if.dbg_arria_word_from_arria),
    .dbg_arria_word_en     (tb_if.dbg_arria_word_en),
    .dbg_arria_byte_from_arria(tb_if.dbg_arria_byte_from_arria),
    .dbg_arria_byte_en     (tb_if.dbg_arria_byte_en),
    .flash_dbg_addr        (tb_if.flash_dbg_addr),
    .flash_dbg_data        (tb_if.flash_dbg_data),
    .flash_mon_addr        (tb_if.flash_mon_addr),
    .flash_mon_data        (tb_if.flash_mon_data),
    .flash_dbg_wip         (tb_if.flash_dbg_wip),
    .flash_dbg_wel         (tb_if.flash_dbg_wel)
  );

  initial begin
    tb_if.drive_idle();
    tb_if.clear_injections();
    tb_if.rsi_csr_reset      = 1'b1;
    tb_if.rsi_link_reset     = 1'b1;
    tb_if.rsi_max10_reset_n  = 1'b0;
    tb_if.flash_dbg_addr     = '0;

    uvm_config_db#(virtual feb_max10_comm_if)::set(null, "*", "vif", tb_if);

    if ($test$plusargs("UVM_TESTNAME")) begin
      run_test();
    end else begin
      run_test(DEFAULT_UVM_TEST);
    end
  end
endmodule
