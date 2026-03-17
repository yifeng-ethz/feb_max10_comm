package feb_max10_comm_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Shared UVM helpers
  // --------------------------------------------------------------------------

  function automatic virtual feb_max10_comm_if m10p_get_vif_or_fatal(uvm_component requester);
    virtual feb_max10_comm_if vif_h;
    if (!uvm_config_db#(virtual feb_max10_comm_if)::get(requester, "", "vif", vif_h)) begin
      `uvm_fatal("NOVIF", $sformatf("%s: virtual interface not set", requester.get_full_name()))
    end
    return vif_h;
  endfunction

  // --------------------------------------------------------------------------
  // Link/runtime model types
  // --------------------------------------------------------------------------

  typedef enum int unsigned {
    M10P_LINK_IDLE,
    M10P_LINK_STREAMING,
    M10P_LINK_ADDR_WRITTEN,
    M10P_LINK_CTRL_STARTED,
    M10P_LINK_CTRL_STOPPED
  } m10p_link_phase_e;

  localparam int unsigned M10P_FLASH_MEM_BYTES = 'h10000;

  // --------------------------------------------------------------------------
  // Transaction records
  // --------------------------------------------------------------------------

  class m10p_sram_write_rec;
    int unsigned cycle;
    int unsigned word_index;
    bit [31:0]   old_word;
    bit [31:0]   new_word;
    int unsigned launch_generation;

    function new(
      int unsigned cycle_in,
      int unsigned word_index_in,
      bit [31:0] old_word_in,
      bit [31:0] new_word_in,
      int unsigned launch_generation_in
    );
      cycle             = cycle_in;
      word_index        = word_index_in;
      old_word          = old_word_in;
      new_word          = new_word_in;
      launch_generation = launch_generation_in;
    endfunction
  endclass

  class m10p_launch_snapshot;
    int unsigned generation;
    int unsigned accepted_cycle;
    int unsigned committed_cycle;
    int unsigned completed_cycle;
    int unsigned flash_addr;
    int unsigned xfer_bytes;
    bit          committed;
    bit          completed;
    bit          reset_drained;
    byte unsigned bytes[$];

    function new();
      generation      = 0;
      accepted_cycle  = 0;
      committed_cycle = 0;
      completed_cycle = 0;
      flash_addr      = 0;
      xfer_bytes      = 0;
      committed       = 1'b0;
      completed       = 1'b0;
      reset_drained   = 1'b0;
    endfunction
  endclass

  // --------------------------------------------------------------------------
  // CSR agent
  // --------------------------------------------------------------------------

  class m10p_csr_item extends uvm_sequence_item;
    rand bit                  is_write;
    rand int unsigned         addr;
    rand logic [31:0]         data;
         logic [31:0]         rdata;

    `uvm_object_utils_begin(m10p_csr_item)
      `uvm_field_int(is_write, UVM_DEFAULT)
      `uvm_field_int(addr, UVM_DEFAULT)
      `uvm_field_int(data, UVM_HEX)
      `uvm_field_int(rdata, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "m10p_csr_item");
      super.new(name);
    endfunction
  endclass

  class m10p_csr_sequencer extends uvm_sequencer #(m10p_csr_item);
    `uvm_component_utils(m10p_csr_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class m10p_csr_driver extends uvm_driver #(m10p_csr_item);
    `uvm_component_utils(m10p_csr_driver)

    virtual feb_max10_comm_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = m10p_get_vif_or_fatal(this);
    endfunction

    task run_phase(uvm_phase phase);
      m10p_csr_item req;
      forever begin
        seq_item_port.get_next_item(req);
        if (req.is_write) begin
          vif.csr_write(req.addr, req.data);
        end else begin
          vif.csr_read(req.addr, req.rdata);
        end
        seq_item_port.item_done();
      end
    endtask
  endclass

  class m10p_csr_monitor extends uvm_component;
    `uvm_component_utils(m10p_csr_monitor)

    virtual feb_max10_comm_if vif;
    uvm_analysis_port #(m10p_csr_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = m10p_get_vif_or_fatal(this);
    endfunction

    task run_phase(uvm_phase phase);
      m10p_csr_item item;
      forever begin
        @(posedge vif.csr_clk);
        if (vif.avs_csr_write) begin
          item = m10p_csr_item::type_id::create("wr_item");
          item.is_write = 1'b1;
          item.addr     = vif.avs_csr_address;
          item.data     = vif.avs_csr_writedata;
          ap.write(item);
        end
        if (vif.avs_csr_readdatavalid) begin
          item = m10p_csr_item::type_id::create("rd_item");
          item.is_write = 1'b0;
          item.addr     = vif.avs_csr_address;
          item.rdata    = vif.avs_csr_readdata;
          ap.write(item);
        end
      end
    endtask
  endclass

  // --------------------------------------------------------------------------
  // Scoreboard
  // --------------------------------------------------------------------------

  class m10p_scoreboard extends uvm_component;
    `uvm_component_utils(m10p_scoreboard)

    virtual feb_max10_comm_if vif;
    uvm_analysis_imp #(m10p_csr_item, m10p_scoreboard) mon_imp;
    int unsigned write_count;
    int unsigned read_count;
    int unsigned csr_write_event_count;

    bit [31:0] staged_words [64];
    bit        staged_valid [64];
    bit [23:0] model_flash_addr;
    bit        model_addr_valid;
    int unsigned model_xfer_bytes;
    bit        model_resetting;
    int unsigned stage_generation;

    byte unsigned expected_flash_mem [0:M10P_FLASH_MEM_BYTES-1];
    m10p_sram_write_rec sram_write_history[$];
    m10p_launch_snapshot launch_snapshots[$];
    m10p_launch_snapshot active_snapshot;

    bit        launch_active;
    bit        launch_reset_pending;
    bit        launch_precommit_checked;
    byte unsigned launch_expected_bytes[$];
    int unsigned launch_expected_count;
    int unsigned launch_payload_index;
    int unsigned launch_flash_addr;
    bit        launch_saw_addr;
    bit        launch_saw_ctrl_start;
    bit        launch_saw_ctrl_stop;
    int unsigned launch_status_reads;
    int unsigned launch_count_reads;
    int unsigned launch_request_cycle;
    int unsigned first_payload_cycle;
    int unsigned addr_write_cycle;
    int unsigned ctrl_start_cycle;
    int unsigned first_status_cycle;
    int unsigned ctrl_stop_cycle;
    int unsigned count_read_cycle;
    m10p_link_phase_e launch_phase;

    int unsigned max10_cycle;
    bit          prev_in_reset;

    int unsigned completed_launch_count;
    int unsigned last_payload_byte_count;
    int unsigned last_expected_byte_count;
    int unsigned last_status_read_count;
    int unsigned last_count_read_count;
    bit          last_launch_reset_pending;
    int unsigned last_completed_snapshot_generation;
    m10p_launch_snapshot last_completed_snapshot;
    int unsigned         last_verified_snapshot_generation;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      mon_imp = new("mon_imp", this);
      write_count = 0;
      read_count  = 0;
      csr_write_event_count = 0;
      reset_runtime_model();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = m10p_get_vif_or_fatal(this);
    endfunction

    function void write(m10p_csr_item item);
      if (item.is_write) begin
        write_count++;
        csr_write_event_count++;
        observe_csr_write(item);
      end else begin
        read_count++;
      end
    endfunction

    function void reset_runtime_model();
      csr_write_event_count    = 0;
      for (int idx = 0; idx < 64; idx++) begin
        staged_words[idx] = '0;
        staged_valid[idx] = 1'b0;
      end
      for (int idx = 0; idx < M10P_FLASH_MEM_BYTES; idx++) begin
        expected_flash_mem[idx] = 8'hFF;
      end
      model_flash_addr         = '0;
      model_addr_valid         = 1'b0;
      model_xfer_bytes         = 32'h100;
      model_resetting          = 1'b0;
      stage_generation         = 1;
      sram_write_history.delete();
      launch_snapshots.delete();
      active_snapshot          = null;
      launch_active            = 1'b0;
      launch_reset_pending     = 1'b0;
      launch_precommit_checked = 1'b0;
      launch_expected_bytes.delete();
      launch_expected_count    = 0;
      launch_payload_index     = 0;
      launch_flash_addr        = 0;
      launch_saw_addr          = 1'b0;
      launch_saw_ctrl_start    = 1'b0;
      launch_saw_ctrl_stop     = 1'b0;
      launch_status_reads      = 0;
      launch_count_reads       = 0;
      launch_request_cycle     = 0;
      first_payload_cycle      = 0;
      addr_write_cycle         = 0;
      ctrl_start_cycle         = 0;
      first_status_cycle       = 0;
      ctrl_stop_cycle          = 0;
      count_read_cycle         = 0;
      launch_phase             = M10P_LINK_IDLE;
      max10_cycle              = 0;
      prev_in_reset            = 1'b1;
      completed_launch_count   = 0;
      last_payload_byte_count  = 0;
      last_expected_byte_count = 0;
      last_status_read_count   = 0;
      last_count_read_count    = 0;
      last_launch_reset_pending = 1'b0;
      last_completed_snapshot_generation = 0;
      last_completed_snapshot  = null;
      last_verified_snapshot_generation = 0;
    endfunction

    function void reset_launch_runtime();
      launch_active            = 1'b0;
      launch_reset_pending     = 1'b0;
      launch_precommit_checked = 1'b0;
      launch_expected_bytes.delete();
      launch_expected_count    = 0;
      launch_payload_index     = 0;
      launch_flash_addr        = 0;
      launch_saw_addr          = 1'b0;
      launch_saw_ctrl_start    = 1'b0;
      launch_saw_ctrl_stop     = 1'b0;
      launch_status_reads      = 0;
      launch_count_reads       = 0;
      launch_request_cycle     = 0;
      first_payload_cycle      = 0;
      addr_write_cycle         = 0;
      ctrl_start_cycle         = 0;
      first_status_cycle       = 0;
      ctrl_stop_cycle          = 0;
      count_read_cycle         = 0;
      launch_phase             = M10P_LINK_IDLE;
    endfunction

    function void clear_stage_model();
      for (int idx = 0; idx < 64; idx++) begin
        staged_words[idx] = '0;
        staged_valid[idx] = 1'b0;
      end
    endfunction

    function int unsigned required_words(input int unsigned xfer_bytes);
      return (xfer_bytes + 3) / 4;
    endfunction

    function int unsigned contiguous_prefix_words();
      int unsigned prefix_words;
      prefix_words = 0;
      while ((prefix_words < 64) && staged_valid[prefix_words]) begin
        prefix_words++;
      end
      return prefix_words;
    endfunction

    function bit page_ready_for_current_model();
      int unsigned words_needed;
      if ((model_xfer_bytes == 0) || (model_xfer_bytes > 256)) begin
        return 1'b0;
      end
      words_needed = required_words(model_xfer_bytes);
      return contiguous_prefix_words() >= words_needed;
    endfunction

    function void record_sram_write(int unsigned word_index, bit [31:0] new_word);
      bit [31:0] old_word;
      m10p_sram_write_rec hist_rec;
      old_word = staged_words[word_index];
      hist_rec = new(csr_write_event_count, word_index, old_word, new_word, stage_generation);
      sram_write_history.push_back(hist_rec);
    endfunction

    function void snapshot_launch_model();
      m10p_launch_snapshot snapshot_h;
      snapshot_h = new();
      snapshot_h.generation     = stage_generation;
      snapshot_h.accepted_cycle = max10_cycle;
      snapshot_h.flash_addr     = model_flash_addr;
      snapshot_h.xfer_bytes     = model_xfer_bytes;
      launch_expected_bytes.delete();
      launch_expected_count = model_xfer_bytes;
      launch_flash_addr     = model_flash_addr;
      for (int unsigned byte_idx = 0; byte_idx < launch_expected_count; byte_idx++) begin
        int unsigned word_idx;
        int unsigned byte_lane;
        word_idx  = byte_idx / 4;
        byte_lane = byte_idx % 4;
        launch_expected_bytes.push_back(byte'(staged_words[word_idx][8*byte_lane +: 8]));
        snapshot_h.bytes.push_back(byte'(staged_words[word_idx][8*byte_lane +: 8]));
      end
      launch_snapshots.push_back(snapshot_h);
      active_snapshot       = snapshot_h;
      launch_payload_index  = 0;
      launch_saw_addr       = 1'b0;
      launch_saw_ctrl_start = 1'b0;
      launch_saw_ctrl_stop  = 1'b0;
      launch_status_reads   = 0;
      launch_count_reads    = 0;
      launch_precommit_checked = 1'b0;
      launch_request_cycle  = max10_cycle;
      first_payload_cycle   = 0;
      addr_write_cycle      = 0;
      ctrl_start_cycle      = 0;
      first_status_cycle    = 0;
      ctrl_stop_cycle       = 0;
      count_read_cycle      = 0;
      launch_phase          = M10P_LINK_STREAMING;
      launch_active         = 1'b1;
      launch_reset_pending  = 1'b0;
      model_resetting       = 1'b0;
      stage_generation      = stage_generation + 1;
    endfunction

    function void observe_csr_write(m10p_csr_item item);
      int unsigned page_index;
      bit page_ready_after;
      bit addr_valid_after;

      if ((item.addr >= vif.REG_PAGE_BASE) && (item.addr < (vif.REG_PAGE_BASE + 64))) begin
        page_index = item.addr - vif.REG_PAGE_BASE;
        record_sram_write(page_index, item.data);
        staged_words[page_index] = item.data;
        staged_valid[page_index] = 1'b1;
      end else begin
        case (item.addr)
          vif.REG_CTRL: begin
            if (item.data[0]) begin
              clear_stage_model();
              model_flash_addr     = '0;
              model_addr_valid     = 1'b0;
              model_xfer_bytes     = 32'h100;
              model_resetting      = launch_active;
              launch_reset_pending = launch_active;
              stage_generation     = stage_generation + 1;
            end
          end

          vif.REG_FLASH_ADDR: begin
            model_flash_addr = item.data[23:0];
            model_addr_valid = 1'b1;
          end

          vif.REG_XFER_BYTES: begin
            model_xfer_bytes = item.data[8:0];
          end

          vif.REG_PROG_CTRL: begin
            if (item.data[1]) begin
              clear_stage_model();
              stage_generation = stage_generation + 1;
            end
            if (item.data[3]) begin
              model_flash_addr = '0;
              model_addr_valid = 1'b0;
            end

            if (item.data[0]) begin
              page_ready_after = page_ready_for_current_model();
              addr_valid_after = model_addr_valid;
              if (!launch_active &&
                  !model_resetting &&
                  addr_valid_after &&
                  (model_xfer_bytes != 0) &&
                  (model_xfer_bytes <= 256) &&
                  page_ready_after) begin
                snapshot_launch_model();
              end
            end
          end

          default: begin
          end
        endcase
      end
    endfunction

    task automatic verify_flash_snapshot_bytes(
      input m10p_launch_snapshot snapshot_h,
      input bit update_expected_mem,
      input bit allow_old_image,
      input string reason
    );
      logic [7:0] got_byte;
      int unsigned flash_idx;
      int unsigned tail_idx;
      bit old_image_match;
      bit new_image_match;
      bit old_or_new_only_match;
      bit prefix_old_after_new_match;
      bit seen_old_after_new;
      bit byte_is_new;
      bit byte_is_old;
      int unsigned first_mismatch_idx;
      logic [7:0] first_mismatch_got;
      logic [7:0] first_mismatch_new;
      logic [7:0] first_mismatch_old;
      bit first_mismatch_valid;

      if (snapshot_h == null) begin
        `uvm_fatal("SCB_FLASH", $sformatf("null launch snapshot used for flash verification (%s)", reason))
      end

      old_image_match = 1'b1;
      new_image_match = 1'b1;
      old_or_new_only_match = 1'b1;
      prefix_old_after_new_match = 1'b1;
      seen_old_after_new = 1'b0;
      first_mismatch_idx = 0;
      first_mismatch_got = '0;
      first_mismatch_new = '0;
      first_mismatch_old = '0;
      first_mismatch_valid = 1'b0;
      for (int unsigned byte_idx = 0; byte_idx < snapshot_h.xfer_bytes; byte_idx++) begin
        flash_idx = (snapshot_h.flash_addr + byte_idx) % M10P_FLASH_MEM_BYTES;
        vif.flash_mon_read_byte(flash_idx, got_byte);
        byte_is_new = (got_byte === snapshot_h.bytes[byte_idx]);
        byte_is_old = (got_byte === expected_flash_mem[flash_idx]);
        if (!byte_is_new) begin
          new_image_match = 1'b0;
          if (!first_mismatch_valid) begin
            first_mismatch_idx = flash_idx;
            first_mismatch_got = got_byte;
            first_mismatch_new = snapshot_h.bytes[byte_idx];
            first_mismatch_old = expected_flash_mem[flash_idx];
            first_mismatch_valid = 1'b1;
          end
        end
        if (!byte_is_old) begin
          old_image_match = 1'b0;
        end
        if (!(byte_is_new || byte_is_old)) begin
          old_or_new_only_match = 1'b0;
        end
        if (prefix_old_after_new_match) begin
          if (seen_old_after_new) begin
            if (!byte_is_old) begin
              prefix_old_after_new_match = 1'b0;
            end
          end else begin
            if (byte_is_new) begin
              begin
              end
            end else if (byte_is_old) begin
              seen_old_after_new = 1'b1;
            end else begin
              prefix_old_after_new_match = 1'b0;
            end
          end
        end
      end

      tail_idx = (snapshot_h.flash_addr + snapshot_h.xfer_bytes) % M10P_FLASH_MEM_BYTES;
      vif.flash_mon_read_byte(tail_idx, got_byte);
      if (got_byte !== expected_flash_mem[tail_idx]) begin
        old_image_match = 1'b0;
        old_or_new_only_match = 1'b0;
        prefix_old_after_new_match = 1'b0;
      end

      if (new_image_match) begin
        if (got_byte !== expected_flash_mem[tail_idx]) begin
          `uvm_fatal("SCB_FLASH",
                     $sformatf("flash tail mismatch (%s) gen=%0d tail_addr=0x%06x exp_old=0x%02x got=0x%02x",
                               reason, snapshot_h.generation, tail_idx, expected_flash_mem[tail_idx], got_byte))
        end
        if (!snapshot_h.committed) begin
          snapshot_h.committed       = 1'b1;
          snapshot_h.committed_cycle = max10_cycle;
        end
        if (update_expected_mem) begin
          for (int unsigned byte_idx = 0; byte_idx < snapshot_h.xfer_bytes; byte_idx++) begin
            flash_idx = (snapshot_h.flash_addr + byte_idx) % M10P_FLASH_MEM_BYTES;
            expected_flash_mem[flash_idx] = snapshot_h.bytes[byte_idx];
          end
        end
      end else if (!(allow_old_image && (old_or_new_only_match || old_image_match || prefix_old_after_new_match))) begin
        `uvm_fatal("SCB_FLASH",
                   $sformatf("flash mismatch (%s) gen=%0d first_idx=0x%06x exp_new=0x%02x exp_old=0x%02x got=0x%02x tail_addr=0x%06x tail_old=0x%02x tail_got=0x%02x",
                             reason, snapshot_h.generation, first_mismatch_idx, first_mismatch_new,
                             first_mismatch_old, first_mismatch_got, tail_idx,
                             expected_flash_mem[tail_idx], got_byte))
      end
    endtask

    task automatic verify_flash_precommit_state(input m10p_launch_snapshot snapshot_h);
      logic [7:0] got_byte;
      int unsigned flash_idx;
      if (snapshot_h == null) begin
        `uvm_fatal("SCB_FLASH_PRE", "precommit check requested with null snapshot")
      end
      flash_idx = snapshot_h.flash_addr % M10P_FLASH_MEM_BYTES;
      vif.flash_mon_read_byte(flash_idx, got_byte);
      if (got_byte !== expected_flash_mem[flash_idx]) begin
        `uvm_fatal("SCB_FLASH_PRE",
                   $sformatf("flash changed before commit for gen=%0d addr=0x%06x exp_old=0x%02x got=0x%02x",
                             snapshot_h.generation, flash_idx, expected_flash_mem[flash_idx], got_byte))
      end
    endtask

    function void check_launch_complete(string reason);
      if (launch_expected_count == 0) begin
        `uvm_fatal("SCB_LAUNCH", $sformatf("launch completed without a valid snapshot (%s)", reason))
      end
      if (launch_payload_index != launch_expected_count) begin
        `uvm_fatal("SCB_PAYLOAD", $sformatf("launch ended with %0d/%0d payload bytes observed (%s)",
                  launch_payload_index, launch_expected_count, reason))
      end
      if (!launch_saw_addr) begin
        `uvm_fatal("SCB_ADDR", $sformatf("launch ended without downstream address write (%s)", reason))
      end
      if (!launch_saw_ctrl_start) begin
        `uvm_fatal("SCB_CTRL_START", $sformatf("launch ended without downstream CTRL.START write (%s)", reason))
      end
      if (!launch_saw_ctrl_stop) begin
        `uvm_fatal("SCB_CTRL_STOP", $sformatf("launch ended without downstream CTRL.STOP write (%s)", reason))
      end
      if (launch_status_reads == 0) begin
        `uvm_fatal("SCB_STATUS", $sformatf("launch ended without downstream STATUS read (%s)", reason))
      end
      if (!launch_reset_pending && (launch_count_reads == 0)) begin
        `uvm_fatal("SCB_COUNT", $sformatf("nominal launch ended without downstream COUNT read (%s)", reason))
      end
      if ((first_payload_cycle == 0) ||
          (addr_write_cycle <= first_payload_cycle) ||
          (ctrl_start_cycle <= addr_write_cycle) ||
          (first_status_cycle <= ctrl_start_cycle) ||
          (ctrl_stop_cycle <= ctrl_start_cycle)) begin
        `uvm_fatal("SCB_TIMING", $sformatf("downstream phase ordering invalid (%s): payload=%0d addr=%0d start=%0d status=%0d stop=%0d",
                  reason, first_payload_cycle, addr_write_cycle, ctrl_start_cycle, first_status_cycle, ctrl_stop_cycle))
      end
    endfunction

    function void finalize_launch(string reason);
      check_launch_complete(reason);
      if (active_snapshot == null) begin
        `uvm_fatal("SCB_SNAPSHOT", $sformatf("launch finalized without an active snapshot (%s)", reason))
      end
      active_snapshot.completed      = 1'b1;
      active_snapshot.completed_cycle = max10_cycle;
      active_snapshot.reset_drained  = launch_reset_pending;
      completed_launch_count    += 1;
      last_payload_byte_count    = launch_payload_index;
      last_expected_byte_count   = launch_expected_count;
      last_status_read_count     = launch_status_reads;
      last_count_read_count      = launch_count_reads;
      last_launch_reset_pending  = launch_reset_pending;
      last_completed_snapshot_generation = active_snapshot.generation;
      last_completed_snapshot    = active_snapshot;
      `uvm_info("SCB_PROTO",
                $sformatf("launch complete reason=%s bytes=%0d status_reads=%0d count_reads=%0d cycles(payload=%0d addr=%0d start=%0d status=%0d stop=%0d count=%0d)",
                          reason, launch_payload_index, launch_status_reads, launch_count_reads,
                          first_payload_cycle, addr_write_cycle, ctrl_start_cycle,
                          first_status_cycle, ctrl_stop_cycle, count_read_cycle),
                UVM_LOW)
      reset_launch_runtime();
      if (last_launch_reset_pending) begin
        clear_stage_model();
        model_flash_addr = '0;
        model_addr_valid = 1'b0;
        model_xfer_bytes = 32'h100;
      end
      model_resetting = 1'b0;
      active_snapshot = null;
    endfunction

    function void observe_payload_byte();
      byte unsigned got_byte;
      if (!launch_active) begin
        `uvm_fatal("SCB_WFIFO", "observed WFIFO payload without an active launch")
      end
      if (launch_saw_addr || launch_saw_ctrl_start) begin
        `uvm_fatal("SCB_WFIFO", "observed WFIFO payload after downstream address/control phase started")
      end
      if (first_payload_cycle == 0) begin
        first_payload_cycle = max10_cycle;
      end
      if (launch_payload_index >= launch_expected_count) begin
        `uvm_fatal("SCB_WFIFO", $sformatf("observed extra WFIFO byte 0x%02x beyond expected %0d bytes",
                  vif.dbg_arria_byte_from_arria, launch_expected_count))
      end
      got_byte = vif.dbg_arria_byte_from_arria;
      if (got_byte !== launch_expected_bytes[launch_payload_index]) begin
        `uvm_fatal("SCB_WFIFO",
                   $sformatf("WFIFO byte mismatch at index %0d: expected 0x%02x got 0x%02x",
                             launch_payload_index, launch_expected_bytes[launch_payload_index], got_byte))
      end
      launch_payload_index += 1;
      launch_phase = M10P_LINK_STREAMING;
    endfunction

    function void observe_word_write();
      if (!launch_active) begin
        `uvm_fatal("SCB_WORD", $sformatf("observed downstream write addr=0x%02x without an active launch", vif.dbg_arria_addr))
      end

      case (vif.dbg_arria_addr)
        vif.FEBSPI_ADDR_PROGRAMMING_ADDR: begin
          if (launch_payload_index != launch_expected_count) begin
            `uvm_fatal("SCB_ADDR", $sformatf("address write arrived after %0d/%0d payload bytes",
                      launch_payload_index, launch_expected_count))
          end
          if (launch_saw_addr) begin
            `uvm_fatal("SCB_ADDR", "duplicate downstream address write observed")
          end
          if (vif.dbg_arria_word_from_arria[23:0] !== launch_flash_addr[23:0]) begin
            `uvm_fatal("SCB_ADDR",
                       $sformatf("downstream address mismatch: expected 0x%06x got 0x%06x",
                                 launch_flash_addr[23:0], vif.dbg_arria_word_from_arria[23:0]))
          end
          launch_saw_addr  = 1'b1;
          addr_write_cycle = max10_cycle;
          launch_phase     = M10P_LINK_ADDR_WRITTEN;
        end

        vif.FEBSPI_ADDR_PROGRAMMING_CTRL: begin
          if (vif.dbg_arria_word_from_arria[0]) begin
            if (!launch_saw_addr) begin
              `uvm_fatal("SCB_CTRL_START", "CTRL.START arrived before downstream address write")
            end
            if (launch_saw_ctrl_start) begin
              `uvm_fatal("SCB_CTRL_START", "duplicate CTRL.START write observed")
            end
            launch_saw_ctrl_start = 1'b1;
            ctrl_start_cycle      = max10_cycle;
            launch_phase          = M10P_LINK_CTRL_STARTED;
          end else begin
            if (!launch_saw_ctrl_start) begin
              `uvm_fatal("SCB_CTRL_STOP", "CTRL.STOP arrived before CTRL.START")
            end
            if (launch_saw_ctrl_stop) begin
              `uvm_fatal("SCB_CTRL_STOP", "duplicate CTRL.STOP write observed")
            end
            launch_saw_ctrl_stop = 1'b1;
            ctrl_stop_cycle      = max10_cycle;
            launch_phase         = M10P_LINK_CTRL_STOPPED;
            if (launch_reset_pending) begin
              finalize_launch("reset_drained_stop");
            end
          end
        end

        default: begin
        end
      endcase
    endfunction

    function void observe_read_beat();
      if (!launch_active) begin
        return;
      end

      case (vif.dbg_arria_addr)
        vif.FEBSPI_ADDR_PROGRAMMING_STATUS: begin
          if (!launch_saw_ctrl_start) begin
            `uvm_fatal("SCB_STATUS", "STATUS read observed before CTRL.START")
          end
          launch_status_reads += 1;
          if (first_status_cycle == 0) begin
            first_status_cycle = max10_cycle;
          end
        end

        vif.FEBSPI_ADDR_PROGRAMMING_COUNT: begin
          if (!launch_saw_ctrl_stop) begin
            `uvm_fatal("SCB_COUNT", "COUNT read observed before CTRL.STOP")
          end
          launch_count_reads += 1;
          if (count_read_cycle == 0) begin
            count_read_cycle = max10_cycle;
          end
          finalize_launch("count_read");
        end

        default: begin
        end
      endcase
    endfunction

    function int unsigned get_completed_launch_count();
      return completed_launch_count;
    endfunction

    function int unsigned get_last_payload_byte_count();
      return last_payload_byte_count;
    endfunction

    function int unsigned get_last_expected_byte_count();
      return last_expected_byte_count;
    endfunction

    function int unsigned get_last_status_read_count();
      return last_status_read_count;
    endfunction

    function int unsigned get_last_count_read_count();
      return last_count_read_count;
    endfunction

    function bit get_last_launch_reset_pending();
      return last_launch_reset_pending;
    endfunction

    function int unsigned get_snapshot_count();
      return launch_snapshots.size();
    endfunction

    function int unsigned get_last_completed_snapshot_generation();
      return last_completed_snapshot_generation;
    endfunction

    function int unsigned count_sram_writes_for_generation(int unsigned generation);
      int unsigned match_count;
      match_count = 0;
      foreach (sram_write_history[idx]) begin
        if (sram_write_history[idx].launch_generation == generation) begin
          match_count++;
        end
      end
      return match_count;
    endfunction

    task automatic verify_last_completed_flash_image();
      if (last_completed_snapshot == null) begin
        `uvm_fatal("SCB_FLASH", "flash verification requested without a completed snapshot")
      end
      if (last_verified_snapshot_generation >= last_completed_snapshot.generation) begin
        return;
      end
      repeat (2) @(posedge vif.max10_clk);
      verify_flash_snapshot_bytes(last_completed_snapshot, 1'b1, 1'b0, "post_done");
      last_verified_snapshot_generation = last_completed_snapshot.generation;
    endtask

    function void close_reset_aborted_before_control();
      if (!launch_active) begin
        `uvm_fatal("SCB_RESET_ABORT", "reset-aborted close requested without an active launch")
      end
      if (!launch_reset_pending) begin
        `uvm_fatal("SCB_RESET_ABORT", "reset-aborted close requested without reset_pending")
      end
      if (launch_saw_addr ||
          launch_saw_ctrl_start ||
          launch_saw_ctrl_stop ||
          (launch_status_reads != 0) ||
          (launch_count_reads != 0)) begin
        `uvm_fatal("SCB_RESET_ABORT",
                   "early reset-abort requested after address/control downstream activity was already observed")
      end
      if (active_snapshot == null) begin
        `uvm_fatal("SCB_RESET_ABORT", "reset-aborted close requested without an active snapshot")
      end

      active_snapshot.completed       = 1'b1;
      active_snapshot.completed_cycle = max10_cycle;
      active_snapshot.reset_drained   = 1'b1;
      last_payload_byte_count         = launch_payload_index;
      last_expected_byte_count        = launch_expected_count;
      last_status_read_count          = 0;
      last_count_read_count           = 0;
      last_launch_reset_pending       = 1'b1;
      last_completed_snapshot_generation = active_snapshot.generation;
      last_completed_snapshot         = active_snapshot;
      `uvm_info("SCB_PROTO",
                $sformatf("launch aborted before downstream control gen=%0d payload_bytes=%0d exp_bytes=%0d",
                          active_snapshot.generation, launch_payload_index, launch_expected_count),
                UVM_LOW)
      reset_launch_runtime();
      clear_stage_model();
      model_flash_addr                = '0;
      model_addr_valid                = 1'b0;
      model_xfer_bytes                = 32'h100;
      model_resetting                 = 1'b0;
      active_snapshot                 = null;
    endfunction

    task run_phase(uvm_phase phase);
      bit in_reset;
      m10p_launch_snapshot snapshot_h;
      forever begin
        @(posedge vif.max10_clk);
        in_reset = vif.rsi_csr_reset || vif.rsi_link_reset || !vif.rsi_max10_reset_n;
        if (in_reset) begin
          if (!prev_in_reset) begin
            clear_stage_model();
            reset_launch_runtime();
            model_flash_addr = '0;
            model_addr_valid = 1'b0;
            model_xfer_bytes = 32'h100;
            model_resetting  = 1'b0;
          end
          prev_in_reset = 1'b1;
          continue;
        end

        prev_in_reset = 1'b0;
        max10_cycle  += 1;

        if (vif.dbg_arria_byte_en && vif.dbg_arria_rw &&
            (vif.dbg_arria_addr == vif.FEBSPI_ADDR_PROGRAMMING_WFIFO)) begin
          observe_payload_byte();
        end

        if (vif.dbg_arria_word_en && vif.dbg_arria_rw) begin
          observe_word_write();
        end

        if (vif.dbg_arria_next_data && !vif.dbg_arria_rw) begin
          observe_read_beat();
        end

        if (launch_active && launch_saw_ctrl_start && !launch_precommit_checked && !vif.flash_dbg_wip && (active_snapshot != null)) begin
          snapshot_h = active_snapshot;
          launch_precommit_checked = 1'b1;
          fork
            begin
              verify_flash_precommit_state(snapshot_h);
            end
          join_none
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (launch_active) begin
        `uvm_fatal("SCB_INCOMPLETE", "test ended with an incomplete downstream launch still open in the scoreboard")
      end
    endfunction
  endclass

  // --------------------------------------------------------------------------
  // Environment and common test utilities
  // --------------------------------------------------------------------------

  class m10p_env extends uvm_env;
    `uvm_component_utils(m10p_env)

    m10p_csr_sequencer csr_seqr;
    m10p_csr_driver    csr_drv;
    m10p_csr_monitor   csr_mon;
    m10p_scoreboard    scb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      csr_seqr = m10p_csr_sequencer::type_id::create("csr_seqr", this);
      csr_drv  = m10p_csr_driver   ::type_id::create("csr_drv",  this);
      csr_mon  = m10p_csr_monitor  ::type_id::create("csr_mon",  this);
      scb      = m10p_scoreboard   ::type_id::create("scb",      this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      csr_drv.seq_item_port.connect(csr_seqr.seq_item_export);
      csr_mon.ap.connect(scb.mon_imp);
    endfunction
  endclass

  class m10p_test_base extends uvm_test;
    `uvm_component_utils(m10p_test_base)

    m10p_env env;
    virtual feb_max10_comm_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = m10p_env::type_id::create("env", this);
      vif = m10p_get_vif_or_fatal(this);
    endfunction

    task automatic expect_eq32(string tag, logic [31:0] got, logic [31:0] exp);
      if (got !== exp) begin
        `uvm_fatal(tag, $sformatf("expected 0x%08h got 0x%08h", exp, got))
      end
    endtask

    task automatic expect_true(string tag, bit cond, string msg);
      if (!cond) begin
        `uvm_fatal(tag, msg)
      end
    endtask

    task automatic read_reg(int unsigned addr, output logic [31:0] data);
      vif.csr_read(addr, data);
      `uvm_info("CSR_RD", $sformatf("addr=0x%03x data=0x%08h", addr, data), UVM_MEDIUM)
    endtask

    task automatic write_reg(int unsigned addr, logic [31:0] data);
      vif.csr_write(addr, data);
      `uvm_info("CSR_WR", $sformatf("addr=0x%03x data=0x%08h", addr, data), UVM_MEDIUM)
    endtask

    task automatic stage_default_16b();
      logic [31:0] words[$];
      words.push_back(32'h04030201);
      words.push_back(32'h08070605);
      words.push_back(32'h0C0B0A09);
      words.push_back(32'h100F0E0D);
      vif.stage_words(words);
    endtask

    task automatic check_last_error_code(byte exp_code);
      logic [7:0] code;
      vif.read_last_error_code(code);
      if (code !== exp_code) begin
        `uvm_fatal("LAST_ERROR", $sformatf("expected code 0x%02h got 0x%02h", exp_code, code))
      end
    endtask

    task automatic check_flash_byte(int unsigned addr, byte exp);
      logic [7:0] got;
      vif.flash_read_byte(addr, got);
      if (got !== exp) begin
        `uvm_fatal("FLASH", $sformatf("flash[%0d] expected 0x%02h got 0x%02h", addr, exp, got))
      end
    endtask

    task automatic check_scoreboard_nominal_launch(int unsigned exp_bytes, bit verify_flash = 1'b1);
      expect_true("SCB_DONE", env.scb.get_completed_launch_count() > 0, "scoreboard did not close a nominal launch");
      expect_true("SCB_BYTES",
                  env.scb.get_last_payload_byte_count() == exp_bytes,
                  $sformatf("scoreboard observed %0d payload bytes, expected %0d",
                            env.scb.get_last_payload_byte_count(), exp_bytes));
      expect_true("SCB_EXPECTED",
                  env.scb.get_last_expected_byte_count() == exp_bytes,
                  $sformatf("scoreboard snapshot expected %0d bytes, expected %0d",
                            env.scb.get_last_expected_byte_count(), exp_bytes));
      expect_true("SCB_STATUS_RD",
                  env.scb.get_last_status_read_count() > 0,
                  "scoreboard did not observe downstream STATUS polling");
      expect_true("SCB_COUNT_RD",
                  env.scb.get_last_count_read_count() > 0,
                  "scoreboard did not observe downstream COUNT read");
      expect_true("SCB_RESET_TAG",
                  !env.scb.get_last_launch_reset_pending(),
                  "scoreboard tagged a nominal launch as reset-drained");
      if (verify_flash) begin
        env.scb.verify_last_completed_flash_image();
      end
    endtask

    task automatic check_scoreboard_reset_drained_launch(int unsigned exp_bytes);
      expect_true("SCB_DONE", env.scb.get_completed_launch_count() > 0, "scoreboard did not close a reset-drained launch");
      expect_true("SCB_BYTES",
                  env.scb.get_last_payload_byte_count() == exp_bytes,
                  $sformatf("scoreboard observed %0d payload bytes, expected %0d",
                            env.scb.get_last_payload_byte_count(), exp_bytes));
      expect_true("SCB_RESET_TAG",
                  env.scb.get_last_launch_reset_pending(),
                  "scoreboard did not tag the last launch as reset-drained");
      expect_true("SCB_STATUS_RD",
                  env.scb.get_last_status_read_count() > 0,
                  "scoreboard did not observe downstream STATUS polling during reset drain");
    endtask

    task automatic check_scoreboard_reset_aborted_before_control(int unsigned exp_bytes);
      env.scb.close_reset_aborted_before_control();
      expect_true("SCB_BYTES",
                  env.scb.get_last_payload_byte_count() <= exp_bytes,
                  $sformatf("scoreboard observed %0d payload bytes, expected at most %0d before control abort",
                            env.scb.get_last_payload_byte_count(), exp_bytes));
      expect_true("SCB_EXPECTED",
                  env.scb.get_last_expected_byte_count() == exp_bytes,
                  $sformatf("scoreboard snapshot expected %0d bytes, expected %0d",
                            env.scb.get_last_expected_byte_count(), exp_bytes));
      expect_true("SCB_RESET_TAG",
                  env.scb.get_last_launch_reset_pending(),
                  "scoreboard did not tag the last launch as reset-aborted");
      expect_true("SCB_STATUS_RD",
                  env.scb.get_last_status_read_count() == 0,
                  "scoreboard should not observe downstream STATUS polling before control-phase abort");
      expect_true("SCB_COUNT_RD",
                  env.scb.get_last_count_read_count() == 0,
                  "scoreboard should not observe downstream COUNT reads before control-phase abort");
    endtask

  endclass

  // --------------------------------------------------------------------------
  // Directed tests
  // --------------------------------------------------------------------------

  class UVM_001_RESET_DEFAULTS extends m10p_test_base;
    `uvm_component_utils(UVM_001_RESET_DEFAULTS)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      read_reg(vif.REG_XFER_BYTES, data);
      expect_eq32("RESET_XFER", data, 32'h0000_0100);
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_eq32("RESET_ERR_FLAGS", data, 32'h0000_0000);
      read_reg(vif.REG_STATUS, data);
      expect_true("RESET_STATUS", data[0] == 1'b1, "ready bit not set after reset");
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_002_CSR_STAGE_STATUS extends m10p_test_base;
    `uvm_component_utils(UVM_002_CSR_STAGE_STATUS)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0012_3456);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0008);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h0403_0201);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h0807_0605);
      read_reg(vif.REG_STAGED_WORDS, data);
      expect_true("STAGED_WORDS", data[6:0] == 7'd2, "staged words mismatch");
      read_reg(vif.REG_PROG_STATUS, data);
      expect_true("PROG_STATUS", data[4:2] == 3'b111, "prog status bits 4:2 mismatch");
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_003_FULL_CHAIN extends m10p_test_base;
    `uvm_component_utils(UVM_003_FULL_CHAIN)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      vif.poll_launch_done(data);
      for (int unsigned idx = 0; idx < 16; idx++) begin
        check_flash_byte(idx, byte'(idx + 1));
      end
      check_flash_byte(16, 8'hFF);
      check_scoreboard_nominal_launch(16, 1'b0);
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_004_ODD_LEN_OVERLAP extends m10p_test_base;
    `uvm_component_utils(UVM_004_ODD_LEN_OVERLAP)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      bit seen_arriawriting;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0020);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0007);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h4433_2211);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h8877_6655);
      vif.start_launch();
      vif.wait_arriawriting_start(seen_arriawriting);
      expect_true("ODD_LEN_BUSY", seen_arriawriting, "launch never reached downstream arriawriting state");
      write_reg(vif.REG_PAGE_BASE + 0, 32'hDDCC_BBAA);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h1100_FFEE);
      vif.poll_launch_done(data);
      check_flash_byte(32, 8'h11);
      check_flash_byte(33, 8'h22);
      check_flash_byte(34, 8'h33);
      check_flash_byte(35, 8'h44);
      check_flash_byte(36, 8'h55);
      check_flash_byte(37, 8'h66);
      check_flash_byte(38, 8'h77);
      check_flash_byte(39, 8'hFF);
      check_scoreboard_nominal_launch(7);
      expect_true("ODD_LEN_SNAP_GEN", env.scb.get_last_completed_snapshot_generation() == 1,
                  "first overlapped launch did not close snapshot generation 1");
      expect_true("ODD_LEN_GEN2_WRITES", env.scb.count_sram_writes_for_generation(2) >= 2,
                  "overlap writes were not tracked as next-generation SRAM history");
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_005_MISSING_ADDR extends m10p_test_base;
    `uvm_component_utils(UVM_005_MISSING_ADDR)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_ADDR", data[2] == 1'b1, "ERR_ADDR_MISSING not set");
      check_last_error_code(byte'(vif.CODE_ADDR_MISSING));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_006_ZERO_LENGTH extends m10p_test_base;
    `uvm_component_utils(UVM_006_ZERO_LENGTH)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0000);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h0403_0201);
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_ZERO", data[3] == 1'b1, "ERR_XFER_BYTES_ZERO not set");
      check_last_error_code(byte'(vif.CODE_XFER_ZERO));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_007_PAGE_UNDERRUN extends m10p_test_base;
    `uvm_component_utils(UVM_007_PAGE_UNDERRUN)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h0403_0201);
      write_reg(vif.REG_PAGE_BASE + 2, 32'h0C0B_0A09);
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_UNDERRUN", data[5] == 1'b1, "ERR_PAGE_UNDERRUN not set");
      check_last_error_code(byte'(vif.CODE_PAGE_UNDERRUN));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_008_START_WHILE_BUSY extends m10p_test_base;
    `uvm_component_utils(UVM_008_START_WHILE_BUSY)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_BUSY", data[0] == 1'b1, "ERR_START_WHILE_BUSY not set");
      check_last_error_code(byte'(vif.CODE_START_WHILE_BUSY));
      vif.poll_launch_done(data);
      check_scoreboard_nominal_launch(16, 1'b0);
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_009_FORCED_TIMEOUT extends m10p_test_base;
    `uvm_component_utils(UVM_009_FORCED_TIMEOUT)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      vif.inj_force_timeout <= 1'b1;
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      vif.poll_launch_done(data);
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_TIMEOUT", data[7] == 1'b1, "ERR_MAX10_TIMEOUT not set");
      check_last_error_code(byte'(vif.CODE_MAX10_TIMEOUT));
      check_scoreboard_nominal_launch(16, 1'b0);
      vif.clear_injections();
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_010_CRCERROR extends m10p_test_base;
    `uvm_component_utils(UVM_010_CRCERROR)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      vif.inj_force_crcerror <= 1'b1;
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      vif.poll_launch_done(data);
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_CRC", data[9] == 1'b1, "ERR_MAX10_CRCERROR not set");
      check_last_error_code(byte'(vif.CODE_MAX10_CRCERROR));
      check_scoreboard_nominal_launch(16, 1'b0);
      vif.clear_injections();
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_011_NSTATUS_LOW extends m10p_test_base;
    `uvm_component_utils(UVM_011_NSTATUS_LOW)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      vif.inj_force_nstatus_low <= 1'b1;
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      vif.poll_launch_done(data);
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_NSTATUS", data[8] == 1'b1, "ERR_MAX10_NSTATUS_LOW not set");
      check_last_error_code(byte'(vif.CODE_MAX10_NSTATUS_LOW));
      check_scoreboard_nominal_launch(16, 1'b0);
      vif.clear_injections();
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_012_FLUSH_PRELAUNCH extends m10p_test_base;
    `uvm_component_utils(UVM_012_FLUSH_PRELAUNCH)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0040);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      write_reg(vif.REG_CTRL, 32'h0000_0001);
      vif.poll_ready(data);
      read_reg(vif.REG_STAGED_WORDS, data);
      expect_true("FLUSH_PRE_STAGED", data[6:0] == 7'd0, "staged words not cleared by prelaunch flush");
      read_reg(vif.REG_FLASH_ADDR, data);
      expect_true("FLUSH_PRE_ADDR", data[23:0] == 24'h0, "flash addr not cleared by prelaunch flush");
      check_last_error_code(byte'(vif.CODE_ABORTED_SW_RESET));
      check_flash_byte(16'h0040, 8'hFF);
      expect_true("SCB_NO_LAUNCH", env.scb.get_completed_launch_count() == 0, "scoreboard observed a downstream launch during prelaunch flush");
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_013_FLUSH_DURING_PROGRAM extends m10p_test_base;
    `uvm_component_utils(UVM_013_FLUSH_DURING_PROGRAM)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      logic [31:0] status_word;
      bit seen_start_issued;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      vif.start_launch();
      seen_start_issued = 1'b0;
      repeat (4000) begin
        @(posedge vif.max10_clk);
        if (vif.dbg_status[0]) begin
          seen_start_issued = 1'b1;
          break;
        end
      end
      expect_true("FLUSH_DUR_START", seen_start_issued, "launch never reached downstream ARRIAWRITING before flush");
      write_reg(vif.REG_CTRL, 32'h0000_0001);
      vif.poll_ready(status_word);
      check_last_error_code(byte'(vif.CODE_ABORTED_SW_RESET));
      for (int unsigned idx = 0; idx < 16; idx++) begin
        check_flash_byte(idx, byte'(idx + 1));
      end
      read_reg(vif.REG_STAGED_WORDS, data);
      expect_true("FLUSH_DUR_CLEAR", data[6:0] == 7'd0, "staged words not cleared after drained flush");
      check_scoreboard_reset_drained_launch(16);
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_014_XFER_GT_256 extends m10p_test_base;
    `uvm_component_utils(UVM_014_XFER_GT_256)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0000);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0101);
      stage_default_16b();
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("ERR_GT256", data[4] == 1'b1, "ERR_XFER_BYTES_GT_256 not set");
      check_last_error_code(byte'(vif.CODE_XFER_GT_256));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_015_CLEAR_PAGE_REJECT extends m10p_test_base;
    `uvm_component_utils(UVM_015_CLEAR_PAGE_REJECT)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0040);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      write_reg(vif.REG_PROG_CTRL, 32'h0000_0002);
      read_reg(vif.REG_STAGED_WORDS, data);
      expect_true("CLEAR_PAGE_STAGED", data[6:0] == 7'd0, "clear_page did not clear staged words");
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("CLEAR_PAGE_ERR", data[5] == 1'b1, "clear_page launch did not raise PAGE_UNDERRUN");
      check_last_error_code(byte'(vif.CODE_PAGE_UNDERRUN));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_016_CLEAR_ADDR_REJECT extends m10p_test_base;
    `uvm_component_utils(UVM_016_CLEAR_ADDR_REJECT)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0080);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0010);
      stage_default_16b();
      write_reg(vif.REG_PROG_CTRL, 32'h0000_0008);
      read_reg(vif.REG_FLASH_ADDR, data);
      expect_true("CLEAR_ADDR_ZERO", data[23:0] == 24'h0, "clear_addr did not clear flash address");
      vif.start_launch();
      read_reg(vif.REG_ERR_FLAGS, data);
      expect_true("CLEAR_ADDR_ERR", data[2] == 1'b1, "clear_addr launch did not raise ADDR_MISSING");
      check_last_error_code(byte'(vif.CODE_ADDR_MISSING));
      phase.drop_objection(this);
    endtask
  endclass

  class UVM_017_BACK_TO_BACK_ODD extends m10p_test_base;
    `uvm_component_utils(UVM_017_BACK_TO_BACK_ODD)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      phase.raise_objection(this);
      vif.apply_reset();

      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0060);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0005);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h4433_2211);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h8877_6655);
      vif.start_launch();
      vif.poll_launch_done(data);
      check_flash_byte(16'h0060, 8'h11);
      check_flash_byte(16'h0061, 8'h22);
      check_flash_byte(16'h0062, 8'h33);
      check_flash_byte(16'h0063, 8'h44);
      check_flash_byte(16'h0064, 8'h55);
      check_flash_byte(16'h0065, 8'hFF);
      check_scoreboard_nominal_launch(5);

      vif.clear_page();
      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0070);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0003);
      write_reg(vif.REG_PAGE_BASE + 0, 32'hCCBB_AA99);
      vif.start_launch();
      vif.poll_launch_done(data);
      check_flash_byte(16'h0070, 8'h99);
      check_flash_byte(16'h0071, 8'hAA);
      check_flash_byte(16'h0072, 8'hBB);
      check_flash_byte(16'h0073, 8'hFF);
      expect_true("BACK2BACK_DONE", env.scb.get_completed_launch_count() == 2, "scoreboard did not close two back-to-back launches");
      check_scoreboard_nominal_launch(3);

      phase.drop_objection(this);
    endtask
  endclass

  class UVM_018_TWO_LAUNCH_OVERLAP_REUSE extends m10p_test_base;
    `uvm_component_utils(UVM_018_TWO_LAUNCH_OVERLAP_REUSE)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      logic [31:0] data;
      bit seen_arriawriting;
      phase.raise_objection(this);
      vif.apply_reset();

      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0100);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_000B);
      write_reg(vif.REG_PAGE_BASE + 0, 32'h4433_2211);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h8877_6655);
      write_reg(vif.REG_PAGE_BASE + 2, 32'h00BB_AA99);
      vif.start_launch();
      vif.wait_arriawriting_start(seen_arriawriting);
      expect_true("OVERLAP_REUSE_BUSY", seen_arriawriting, "first launch never reached downstream arriawriting state");

      write_reg(vif.REG_PAGE_BASE + 0, 32'hDDCC_BBAA);
      write_reg(vif.REG_PAGE_BASE + 1, 32'h1100_FFEE);

      vif.poll_launch_done(data);
      check_flash_byte(16'h0100, 8'h11);
      check_flash_byte(16'h0101, 8'h22);
      check_flash_byte(16'h0102, 8'h33);
      check_flash_byte(16'h0103, 8'h44);
      check_flash_byte(16'h0104, 8'h55);
      check_flash_byte(16'h0105, 8'h66);
      check_flash_byte(16'h0106, 8'h77);
      check_flash_byte(16'h0107, 8'h88);
      check_flash_byte(16'h0108, 8'h99);
      check_flash_byte(16'h0109, 8'hAA);
      check_flash_byte(16'h010A, 8'hBB);
      expect_true("OVERLAP_REUSE_GEN1", env.scb.get_last_completed_snapshot_generation() == 1,
                  "first launch did not complete snapshot generation 1");
      expect_true("OVERLAP_REUSE_GEN2_WR", env.scb.count_sram_writes_for_generation(2) >= 2,
                  "overlap writes were not retained as generation 2 history");
      check_scoreboard_nominal_launch(11);

      write_reg(vif.REG_FLASH_ADDR, 32'h0000_0100);
      write_reg(vif.REG_XFER_BYTES, 32'h0000_0007);
      vif.start_launch();
      vif.poll_launch_done(data);

      check_flash_byte(16'h0100, 8'hAA);
      check_flash_byte(16'h0101, 8'hBB);
      check_flash_byte(16'h0102, 8'hCC);
      check_flash_byte(16'h0103, 8'hDD);
      check_flash_byte(16'h0104, 8'hEE);
      check_flash_byte(16'h0105, 8'hFF);
      check_flash_byte(16'h0106, 8'h00);
      check_flash_byte(16'h0107, 8'h88);
      check_flash_byte(16'h0108, 8'h99);
      check_flash_byte(16'h0109, 8'hAA);
      check_flash_byte(16'h010A, 8'hBB);
      expect_true("OVERLAP_REUSE_SNAP_COUNT", env.scb.get_snapshot_count() == 2,
                  "expected two explicit launch snapshots after overlap reuse sequence");
      expect_true("OVERLAP_REUSE_GEN2", env.scb.get_last_completed_snapshot_generation() == 2,
                  "second launch did not complete snapshot generation 2");
      check_scoreboard_nominal_launch(7);

      phase.drop_objection(this);
    endtask
  endclass

  // --------------------------------------------------------------------------
  // Table-driven matrix tests
  // --------------------------------------------------------------------------

  `include "feb_max10_comm_matrix_tests.svh"

endpackage
