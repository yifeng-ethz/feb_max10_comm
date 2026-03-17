interface feb_max10_comm_if (
    input logic csr_clk,
    input logic link_clk,
    input logic max10_clk
);
  timeunit 1ns;
  timeprecision 1ps;

  // --------------------------------------------------------------------------
  // CSR/register model constants
  // --------------------------------------------------------------------------

  localparam int unsigned CSR_ADDR_W = 10;
  localparam int unsigned BURSTCOUNT_W = 9;

  localparam int unsigned REG_ID          = 'h000;
  localparam int unsigned REG_VERSION     = 'h001;
  localparam int unsigned REG_CTRL        = 'h002;
  localparam int unsigned REG_STATUS      = 'h003;
  localparam int unsigned REG_ERR_FLAGS   = 'h004;
  localparam int unsigned REG_ERR_COUNT   = 'h005;
  localparam int unsigned REG_SCRATCH     = 'h006;
  localparam int unsigned REG_FLASH_ADDR  = 'h007;
  localparam int unsigned REG_XFER_BYTES  = 'h008;
  localparam int unsigned REG_PROG_CTRL   = 'h009;
  localparam int unsigned REG_PROG_STATUS = 'h00A;
  localparam int unsigned REG_STAGED_WORDS = 'h00B;
  localparam int unsigned REG_MAX10_STAT   = 'h00C;
  localparam int unsigned REG_MAX10_COUNT  = 'h00D;
  localparam int unsigned REG_LAST_ERROR   = 'h00E;
  localparam int unsigned REG_PAGE_BASE    = 'h020;

  localparam int unsigned FEBSPI_ADDR_PROGRAMMING_STATUS = 'h10;
  localparam int unsigned FEBSPI_ADDR_PROGRAMMING_COUNT  = 'h11;
  localparam int unsigned FEBSPI_ADDR_PROGRAMMING_CTRL   = 'h12;
  localparam int unsigned FEBSPI_ADDR_PROGRAMMING_ADDR   = 'h13;
  localparam int unsigned FEBSPI_ADDR_PROGRAMMING_WFIFO  = 'h14;
  localparam int unsigned POLL_LAUNCH_DONE_MAX_POLLS     = 40000;
  localparam int unsigned POLL_READY_MAX_POLLS           = 4000;

  localparam int unsigned CODE_START_WHILE_BUSY   = 'h01;
  localparam int unsigned CODE_START_DURING_RESET = 'h02;
  localparam int unsigned CODE_ADDR_MISSING       = 'h03;
  localparam int unsigned CODE_XFER_ZERO          = 'h04;
  localparam int unsigned CODE_XFER_GT_256        = 'h05;
  localparam int unsigned CODE_PAGE_UNDERRUN      = 'h06;
  localparam int unsigned CODE_LINK_TIMEOUT       = 'h07;
  localparam int unsigned CODE_MAX10_TIMEOUT      = 'h08;
  localparam int unsigned CODE_MAX10_NSTATUS_LOW  = 'h09;
  localparam int unsigned CODE_MAX10_CRCERROR     = 'h0A;
  localparam int unsigned CODE_ABORTED_SW_RESET   = 'h80;

  // --------------------------------------------------------------------------
  // Testbench-controlled DUT inputs and visible diagnostics
  // --------------------------------------------------------------------------

  logic rsi_csr_reset;
  logic rsi_link_reset;
  logic rsi_max10_reset_n;
  time  csr_half_period  = 10ns;
  time  link_half_period = 10ns;
  time  max10_half_period = 5ns;

  logic [CSR_ADDR_W-1:0]     avs_csr_address;
  logic                      avs_csr_read;
  logic                      avs_csr_write;
  logic [31:0]               avs_csr_writedata;
  logic [31:0]               avs_csr_readdata;
  logic                      avs_csr_readdatavalid;
  logic                      avs_csr_waitrequest;
  logic [BURSTCOUNT_W-1:0]   avs_csr_burstcount;

  logic                      inj_hold_arriawriting;
  logic                      inj_force_timeout;
  logic                      inj_force_crcerror;
  logic                      inj_force_nstatus_low;

  logic [31:0]               diag_summary;
  logic [31:0]               diag_err_flags;
  logic [31:0]               diag_last_error;
  logic [31:0]               diag_max10_stat;
  logic [31:0]               diag_max10_count;

  logic                      mon_link_csn;
  logic                      mon_link_clk;
  logic                      mon_link_mosi;
  logic                      mon_link_miso;
  logic                      mon_link_d1;
  logic                      mon_link_d2;
  logic                      mon_link_d3;

  logic [31:0]               dbg_status;
  logic [31:0]               dbg_flash_w_cnt;
  logic [31:0]               dbg_control;
  logic [23:0]               dbg_addr_from_arria;
  logic [6:0]                dbg_arria_addr;
  logic                      dbg_arria_rw;
  logic                      dbg_arria_next_data;
  logic [31:0]               dbg_arria_word_from_arria;
  logic                      dbg_arria_word_en;
  logic [7:0]                dbg_arria_byte_from_arria;
  logic                      dbg_arria_byte_en;

  logic [23:0]               flash_dbg_addr;
  logic [7:0]                flash_dbg_data;
  logic [23:0]               flash_mon_addr;
  logic [7:0]                flash_mon_data;
  logic                      flash_dbg_wip;
  logic                      flash_dbg_wel;

  // --------------------------------------------------------------------------
  // Bus and diagnostic helper tasks
  // --------------------------------------------------------------------------

  task automatic drive_idle();
    avs_csr_address      <= '0;
    avs_csr_read         <= 1'b0;
    avs_csr_write        <= 1'b0;
    avs_csr_writedata    <= '0;
    avs_csr_burstcount   <= BURSTCOUNT_W'(1);
  endtask

  task automatic clear_injections();
    inj_hold_arriawriting <= 1'b0;
    inj_force_timeout     <= 1'b0;
    inj_force_crcerror    <= 1'b0;
    inj_force_nstatus_low <= 1'b0;
  endtask

  task automatic set_clock_periods(input time csr_hp, input time link_hp, input time max10_hp = 5ns);
    csr_half_period   = csr_hp;
    link_half_period  = link_hp;
    max10_half_period = max10_hp;
  endtask

  task automatic apply_reset();
    drive_idle();
    clear_injections();
    flash_dbg_addr       <= '0;
    flash_mon_addr       <= '0;
    rsi_csr_reset        <= 1'b1;
    rsi_link_reset       <= 1'b1;
    rsi_max10_reset_n    <= 1'b0;
    repeat (8) @(posedge max10_clk);
    rsi_csr_reset        <= 1'b0;
    rsi_link_reset       <= 1'b0;
    rsi_max10_reset_n    <= 1'b1;
    repeat (4) @(posedge csr_clk);
  endtask

  task automatic csr_write(input int unsigned addr, input logic [31:0] data);
    avs_csr_address      <= addr[CSR_ADDR_W-1:0];
    avs_csr_writedata    <= data;
    avs_csr_write        <= 1'b1;
    @(posedge csr_clk);
    avs_csr_write        <= 1'b0;
    @(posedge csr_clk);
  endtask

  task automatic csr_read(input int unsigned addr, output logic [31:0] data);
    avs_csr_address      <= addr[CSR_ADDR_W-1:0];
    avs_csr_read         <= 1'b1;
    @(posedge csr_clk);
    wait (avs_csr_readdatavalid === 1'b1);
    data                 = avs_csr_readdata;
    avs_csr_read         <= 1'b0;
    @(posedge csr_clk);
  endtask

  task automatic flash_read_byte(input int unsigned addr, output logic [7:0] data);
    flash_dbg_addr       <= addr[23:0];
    #1ns;
    data                 = flash_dbg_data;
  endtask

  task automatic flash_mon_read_byte(input int unsigned addr, output logic [7:0] data);
    flash_mon_addr       <= addr[23:0];
    #1ns;
    data                 = flash_mon_data;
  endtask

  task automatic stage_words(input logic [31:0] words[$]);
    foreach (words[idx]) begin
      csr_write(REG_PAGE_BASE + idx, words[idx]);
    end
  endtask

  task automatic clear_page();
    csr_write(REG_PROG_CTRL, 32'h0000_0002);
  endtask

  task automatic clear_addr();
    csr_write(REG_PROG_CTRL, 32'h0000_0008);
  endtask

  task automatic clear_launch_flags();
    csr_write(REG_PROG_CTRL, 32'h0000_0004);
  endtask

  task automatic start_launch();
    csr_write(REG_PROG_CTRL, 32'h0000_0001);
  endtask

  task automatic poll_launch_done(output logic [31:0] prog_status);
    bit seen_busy;
    seen_busy = 1'b0;
    repeat (POLL_LAUNCH_DONE_MAX_POLLS) begin
      csr_read(REG_PROG_STATUS, prog_status);
      if (prog_status[1]) begin
        seen_busy = 1'b1;
      end
      if (seen_busy && !prog_status[1] && prog_status[7]) begin
        return;
      end
      repeat (10) @(posedge csr_clk);
    end
    $fatal(1, "poll_launch_done timeout");
  endtask

  task automatic poll_launch_accepted(output logic [31:0] prog_status);
    repeat (POLL_LAUNCH_DONE_MAX_POLLS) begin
      csr_read(REG_PROG_STATUS, prog_status);
      if (prog_status[6] && prog_status[1]) begin
        return;
      end
      repeat (10) @(posedge csr_clk);
    end
    $fatal(1, "poll_launch_accepted timeout");
  endtask

  task automatic poll_ready(output logic [31:0] status_word);
    repeat (POLL_READY_MAX_POLLS) begin
      csr_read(REG_STATUS, status_word);
      if (status_word[0] && !status_word[3]) begin
        return;
      end
      repeat (10) @(posedge csr_clk);
    end
    $fatal(1, "poll_ready timeout");
  endtask

  task automatic read_last_error_code(output logic [7:0] code);
    logic [31:0] data;
    csr_read(REG_LAST_ERROR, data);
    code = data[7:0];
  endtask

  task automatic wait_arriawriting_start(output bit seen);
    seen = 1'b0;
    repeat (4000) begin
      @(posedge max10_clk);
      if (dbg_status[0]) begin
        seen = 1'b1;
        return;
      end
    end
  endtask

endinterface
