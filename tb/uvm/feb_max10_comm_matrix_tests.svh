  // --------------------------------------------------------------------------
  // Matrix descriptors and classification enums
  // --------------------------------------------------------------------------

  typedef enum int unsigned {
    FM10_KIND_LEGAL    = 1,
    FM10_KIND_OVERLAP  = 2,
    FM10_KIND_RESET    = 3,
    FM10_KIND_FAULT    = 4,
    FM10_KIND_RANDOM   = 5
  } fm10_case_kind_e;

  typedef enum int unsigned {
    FM10_FAULT_NONE         = 0,
    FM10_FAULT_LINK_TIMEOUT = 1,
    FM10_FAULT_MAX_TIMEOUT  = 2,
    FM10_FAULT_CRC          = 3,
    FM10_FAULT_NSTATUS      = 4
  } fm10_fault_kind_e;

  typedef enum int unsigned {
    FM10_RESET_NONE                 = 0,
    FM10_RESET_PRE_START            = 1,
    FM10_RESET_AFTER_ACCEPT         = 2,
    FM10_RESET_DURING_ARRIAWRITING  = 3,
    FM10_RESET_DURING_STATUS_POLL   = 4
  } fm10_reset_phase_e;

  typedef enum int unsigned {
    FM10_REJECT_NONE           = 0,
    FM10_REJECT_BUSY           = 1,
    FM10_REJECT_RESET          = 2,
    FM10_REJECT_ADDR           = 3,
    FM10_REJECT_XFER_ZERO      = 4,
    FM10_REJECT_XFER_GT_256    = 5,
    FM10_REJECT_PAGE_UNDERRUN  = 6
  } fm10_reject_reason_e;

  typedef enum int unsigned {
    FM10_REJECT_STATE_NONE      = 0,
    FM10_REJECT_STATE_BUSY      = 1,
    FM10_REJECT_STATE_RESET     = 2,
    FM10_REJECT_STATE_ADDR      = 3,
    FM10_REJECT_STATE_PAGE      = 4,
    FM10_REJECT_STATE_LENGTH    = 5
  } fm10_reject_state_e;

  typedef enum int unsigned {
    FM10_OVERLAP_REUSE                = 0,
    FM10_OVERLAP_CLEAR_PAGE_REJECT    = 1,
    FM10_OVERLAP_CLEAR_ADDR_REJECT    = 2,
    FM10_OVERLAP_BUSY_REJECT          = 3,
    FM10_OVERLAP_RESET_REJECT         = 4,
    FM10_OVERLAP_ZERO_LEN_REJECT      = 5,
    FM10_OVERLAP_GT256_REJECT         = 6,
    FM10_OVERLAP_CLEAR_STATUS_RECOVER = 7
  } fm10_overlap_mode_e;

  typedef enum int unsigned {
    FM10_RECOVERY_NONE          = 0,
    FM10_RECOVERY_RETRY_SUCCESS = 1,
    FM10_RECOVERY_CLEAR_RETRY   = 2,
    FM10_RECOVERY_RESET_RETRY   = 3
  } fm10_recovery_kind_e;

  // --------------------------------------------------------------------------
  // Table-driven case database
  // --------------------------------------------------------------------------

  class fm10_case_desc extends uvm_object;
    int unsigned            case_id;
    fm10_case_kind_e        kind;
    int unsigned            length;
    int unsigned            address;
    int unsigned            seed;
    int unsigned            align_bucket;
    int unsigned            ratio_bucket;
    fm10_fault_kind_e       fault_kind;
    fm10_reset_phase_e      reset_phase;
    fm10_overlap_mode_e     overlap_mode;
    fm10_reject_reason_e    reject_reason;
    fm10_reject_state_e     reject_state;
    fm10_recovery_kind_e    recovery_kind;
    time                    csr_half_period;
    time                    link_half_period;

    `uvm_object_utils(fm10_case_desc)

    function new(string name = "fm10_case_desc");
      super.new(name);
      case_id         = 0;
      kind            = FM10_KIND_LEGAL;
      length          = 16;
      address         = 0;
      seed            = 1;
      align_bucket    = 0;
      ratio_bucket    = 2;
      fault_kind      = FM10_FAULT_NONE;
      reset_phase     = FM10_RESET_NONE;
      overlap_mode    = FM10_OVERLAP_REUSE;
      reject_reason   = FM10_REJECT_NONE;
      reject_state    = FM10_REJECT_STATE_NONE;
      recovery_kind   = FM10_RECOVERY_NONE;
      csr_half_period = 10ns;
      link_half_period = 10ns;
    endfunction
  endclass

  class fm10_case_db;
    static function int unsigned calc_length_bucket(int unsigned length);
      if (length <= 1) begin
        return 1;
      end
      if (length <= 2) begin
        return 2;
      end
      if (length <= 4) begin
        return 4;
      end
      if (length <= 8) begin
        return 8;
      end
      if (length <= 16) begin
        return 16;
      end
      if (length <= 32) begin
        return 32;
      end
      return 64;
    endfunction

    static function fm10_case_desc make(int unsigned case_id);
      const int unsigned legal_lengths[10] = '{1, 2, 3, 4, 5, 7, 8, 15, 16, 31};
      const int unsigned fault_lengths[4] = '{4, 7, 16, 28};
      const time csr_half_periods[6] = '{6ns, 8ns, 10ns, 12ns, 14ns, 16ns};
      const time link_half_periods[6] = '{14ns, 12ns, 10ns, 8ns, 6ns, 10ns};
      fm10_case_desc d;
      int unsigned idx;
      d = new($sformatf("fm10_case_desc_%0d", case_id));
      d.case_id = case_id;

      if ((case_id >= 19) && (case_id <= 48)) begin
        idx              = case_id - 19;
        d.kind           = FM10_KIND_LEGAL;
        d.length         = legal_lengths[idx % 10];
        d.align_bucket   = idx / 10;
        d.address        = 24'h0020 + (idx / 10) + ((idx % 10) * 16);
        d.seed           = case_id + 11;
      end else if ((case_id >= 49) && (case_id <= 72)) begin
        idx              = case_id - 49;
        d.kind           = FM10_KIND_OVERLAP;
        d.overlap_mode   = fm10_overlap_mode_e'(idx % 8);
        d.align_bucket   = idx / 8;
        d.address        = 24'h0100 + (idx / 8) + ((idx % 8) * 32);
        d.seed           = case_id + 23;
        d.length         = 7 + (idx % 5) * 3;
        case (d.overlap_mode)
          FM10_OVERLAP_CLEAR_PAGE_REJECT: begin
            d.reject_reason = FM10_REJECT_PAGE_UNDERRUN;
            d.reject_state  = FM10_REJECT_STATE_PAGE;
          end
          FM10_OVERLAP_CLEAR_ADDR_REJECT: begin
            d.reject_reason = FM10_REJECT_ADDR;
            d.reject_state  = FM10_REJECT_STATE_ADDR;
          end
          FM10_OVERLAP_BUSY_REJECT: begin
            d.reject_reason = FM10_REJECT_BUSY;
            d.reject_state  = FM10_REJECT_STATE_BUSY;
          end
          FM10_OVERLAP_RESET_REJECT: begin
            d.reject_reason = FM10_REJECT_ADDR;
            d.reject_state  = FM10_REJECT_STATE_ADDR;
          end
          FM10_OVERLAP_ZERO_LEN_REJECT: begin
            d.reject_reason = FM10_REJECT_XFER_ZERO;
            d.reject_state  = FM10_REJECT_STATE_LENGTH;
            d.length        = 0;
          end
          FM10_OVERLAP_GT256_REJECT: begin
            d.reject_reason = FM10_REJECT_XFER_GT_256;
            d.reject_state  = FM10_REJECT_STATE_LENGTH;
            d.length        = 257;
          end
          default: begin
            d.reject_reason = FM10_REJECT_NONE;
            d.reject_state  = FM10_REJECT_STATE_NONE;
          end
        endcase
      end else if ((case_id >= 73) && (case_id <= 96)) begin
        idx                = case_id - 73;
        d.kind             = FM10_KIND_RESET;
        d.ratio_bucket     = idx / 4;
        d.reset_phase      = fm10_reset_phase_e'((idx % 4) + 1);
        d.length           = 12 + (idx % 3) * 4;
        d.align_bucket     = idx % 4;
        d.address          = 24'h0200 + (idx * 8) + (idx % 4);
        d.seed             = case_id + 37;
        d.csr_half_period  = csr_half_periods[d.ratio_bucket];
        d.link_half_period = link_half_periods[d.ratio_bucket];
        d.recovery_kind    = FM10_RECOVERY_RESET_RETRY;
      end else if ((case_id >= 97) && (case_id <= 112)) begin
        idx              = case_id - 97;
        d.kind           = FM10_KIND_FAULT;
        d.fault_kind     = fm10_fault_kind_e'((idx / 4) + 1);
        d.length         = fault_lengths[idx % 4];
        d.align_bucket   = idx % 4;
        d.address        = 24'h0300 + (idx * 16) + (idx % 4);
        d.seed           = case_id + 51;
      end else if ((case_id >= 113) && (case_id <= 128)) begin
        idx              = case_id - 113;
        d.kind           = FM10_KIND_RANDOM;
        d.align_bucket   = idx % 4;
        d.address        = 24'h0400 + (idx * 24) + (idx % 4);
        d.seed           = case_id + 71;
        d.length         = 5 + (idx % 7) * 3;
        if (idx < 8) begin
          d.recovery_kind = FM10_RECOVERY_NONE;
        end else begin
          d.recovery_kind = fm10_recovery_kind_e'((idx % 3) + 1);
          d.fault_kind    = fm10_fault_kind_e'((idx % 3) + 2);
        end
      end else begin
        `uvm_fatal("CASE_ID", $sformatf("unsupported matrix case id %0d", case_id))
      end

      return d;
    endfunction
  endclass

  // --------------------------------------------------------------------------
  // Coverage and reusable matrix execution helpers
  // --------------------------------------------------------------------------

  class fm10_cov_model;
    covergroup cg with function sample(
      int kind,
      int len_bucket,
      int last_word_bytes,
      int align_bucket,
      int reject_reason,
      int reject_state,
      int fault_kind,
      int recovery_kind,
      int reset_phase,
      int ratio_bucket
    );
      kind_cp : coverpoint kind {
        bins legal   = {FM10_KIND_LEGAL};
        bins overlap = {FM10_KIND_OVERLAP};
        bins reset   = {FM10_KIND_RESET};
        bins fault   = {FM10_KIND_FAULT};
        bins random  = {FM10_KIND_RANDOM};
      }
      len_cp : coverpoint len_bucket {
        bins b1  = {1};
        bins b2  = {2};
        bins b4  = {4};
        bins b8  = {8};
        bins b16 = {16};
        bins b32 = {32};
        bins b64 = {64};
      }
      last_word_cp : coverpoint last_word_bytes {
        bins one   = {1};
        bins two   = {2};
        bins three = {3};
        bins four  = {4};
      }
      align_cp : coverpoint align_bucket {
        bins a0 = {0};
        bins a1 = {1};
        bins a2 = {2};
        bins a3 = {3};
      }
      reject_cp : coverpoint reject_reason {
        bins none     = {FM10_REJECT_NONE};
        bins busy     = {FM10_REJECT_BUSY};
        bins reset    = {FM10_REJECT_RESET};
        bins addr     = {FM10_REJECT_ADDR};
        bins zero     = {FM10_REJECT_XFER_ZERO};
        bins gt256    = {FM10_REJECT_XFER_GT_256};
        bins underrun = {FM10_REJECT_PAGE_UNDERRUN};
      }
      reject_state_cp : coverpoint reject_state {
        bins none   = {FM10_REJECT_STATE_NONE};
        bins busy   = {FM10_REJECT_STATE_BUSY};
        bins reset  = {FM10_REJECT_STATE_RESET};
        bins addr   = {FM10_REJECT_STATE_ADDR};
        bins page   = {FM10_REJECT_STATE_PAGE};
        bins length = {FM10_REJECT_STATE_LENGTH};
      }
      fault_cp : coverpoint fault_kind {
        bins none         = {FM10_FAULT_NONE};
        bins link_timeout = {FM10_FAULT_LINK_TIMEOUT};
        bins max_timeout  = {FM10_FAULT_MAX_TIMEOUT};
        bins crc          = {FM10_FAULT_CRC};
        bins nstatus      = {FM10_FAULT_NSTATUS};
      }
      recovery_cp : coverpoint recovery_kind {
        bins none   = {FM10_RECOVERY_NONE};
        bins retry  = {FM10_RECOVERY_RETRY_SUCCESS};
        bins clear  = {FM10_RECOVERY_CLEAR_RETRY};
        bins reset  = {FM10_RECOVERY_RESET_RETRY};
      }
      reset_cp : coverpoint reset_phase {
        bins none        = {FM10_RESET_NONE};
        bins pre_start   = {FM10_RESET_PRE_START};
        bins accepted    = {FM10_RESET_AFTER_ACCEPT};
        bins arriawrite  = {FM10_RESET_DURING_ARRIAWRITING};
        bins poll        = {FM10_RESET_DURING_STATUS_POLL};
      }
      ratio_cp : coverpoint ratio_bucket {
        bins r0 = {0};
        bins r1 = {1};
        bins r2 = {2};
        bins r3 = {3};
        bins r4 = {4};
        bins r5 = {5};
      }

      len_align_cross     : cross len_cp, last_word_cp, align_cp;
      reject_state_cross  : cross reject_cp, reject_state_cp;
      fault_recovery_cross: cross fault_cp, recovery_cp;
      ratio_reset_cross   : cross ratio_cp, reset_cp;
    endgroup

    function new();
      cg = new();
    endfunction

    function void sample_desc(fm10_case_desc d);
      int unsigned last_word_bytes;
      if (d.length == 0) begin
        last_word_bytes = 1;
      end else begin
        last_word_bytes = ((d.length - 1) % 4) + 1;
      end
      cg.sample(
        d.kind,
        fm10_case_db::calc_length_bucket((d.length > 256) ? 64 : ((d.length == 0) ? 1 : d.length)),
        last_word_bytes,
        d.align_bucket,
        d.reject_reason,
        d.reject_state,
        d.fault_kind,
        d.recovery_kind,
        d.reset_phase,
        d.ratio_bucket
      );
    endfunction
  endclass

  class fm10_matrix_test_base extends m10p_test_base;
    static fm10_cov_model cov;
    fm10_case_desc desc;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function int unsigned get_case_id();
      return 0;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cov == null) begin
        cov = new();
      end
      desc = fm10_case_db::make(get_case_id());
    endfunction

    function automatic byte unsigned calc_expected_byte(int unsigned seed, int unsigned byte_idx);
      return byte'(((seed * 29) + byte_idx + 1) & 8'hFF);
    endfunction

    function automatic logic [31:0] calc_word(int unsigned seed, int unsigned word_idx);
      logic [31:0] word_v;
      for (int lane = 0; lane < 4; lane++) begin
        word_v[lane*8 +: 8] = calc_expected_byte(seed, word_idx * 4 + lane);
      end
      return word_v;
    endfunction

    task automatic stage_pattern_words(int unsigned length, int unsigned seed, int override_words = -1);
      logic [31:0] words[$];
      int unsigned words_needed;
      words_needed = (length + 3) / 4;
      if (override_words >= 0) begin
        words_needed = override_words;
      end
      for (int unsigned idx = 0; idx < words_needed; idx++) begin
        words.push_back(calc_word(seed, idx));
      end
      vif.stage_words(words);
    endtask

    task automatic check_flash_pattern(int unsigned flash_addr, int unsigned length, int unsigned seed);
      for (int unsigned idx = 0; idx < length; idx++) begin
        check_flash_byte((flash_addr + idx) % M10P_FLASH_MEM_BYTES, calc_expected_byte(seed, idx));
      end
      check_flash_byte((flash_addr + length) % M10P_FLASH_MEM_BYTES, 8'hFF);
    endtask

    task automatic wait_for_status_poll(output bit seen);
      seen = 1'b0;
      repeat (8000) begin
        @(posedge vif.max10_clk);
        if (vif.dbg_arria_next_data && !vif.dbg_arria_rw &&
            (vif.dbg_arria_addr == vif.FEBSPI_ADDR_PROGRAMMING_STATUS)) begin
          seen = 1'b1;
          return;
        end
      end
    endtask

    task automatic clear_all_error_state();
      write_reg(vif.REG_ERR_FLAGS, 32'hFFFF_FFFF);
      vif.clear_launch_flags();
    endtask

    task automatic wait_recovery_quiesce();
      // Let the downstream compatibility chain settle before the next retry.
      repeat (64) @(posedge vif.max10_clk);
    endtask

    task automatic run_nominal_launch(
      input int unsigned flash_addr,
      input int unsigned length,
      input int unsigned seed
    );
      logic [31:0] data;
      write_reg(vif.REG_FLASH_ADDR, flash_addr);
      write_reg(vif.REG_XFER_BYTES, length);
      stage_pattern_words(length, seed);
      vif.start_launch();
      vif.poll_launch_done(data);
      check_flash_pattern(flash_addr, length, seed);
      check_scoreboard_nominal_launch(length);
    endtask

    task automatic run_legal_case();
      run_nominal_launch(desc.address, desc.length, desc.seed);
    endtask

    task automatic run_overlap_case();
      logic [31:0] data;
      bit seen;
      case (desc.overlap_mode)
        FM10_OVERLAP_REUSE: begin
          int unsigned second_len;
          int unsigned updated_prefix_len;
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, desc.length);
          stage_pattern_words(desc.length, desc.seed);
          vif.start_launch();
          vif.wait_arriawriting_start(seen);
          expect_true("OVERLAP_BUSY", seen, "overlap case never reached downstream arriawriting");
          write_reg(vif.REG_PAGE_BASE + 0, calc_word(desc.seed + 9, 0));
          write_reg(vif.REG_PAGE_BASE + 1, calc_word(desc.seed + 9, 1));
          vif.poll_launch_done(data);
          check_flash_pattern(desc.address, desc.length, desc.seed);
          check_scoreboard_nominal_launch(desc.length);
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          second_len = (desc.length > 2) ? (desc.length - 2) : 1;
          updated_prefix_len = (second_len < 8) ? second_len : 8;
          write_reg(vif.REG_XFER_BYTES, second_len);
          vif.start_launch();
          vif.poll_launch_done(data);
          for (int unsigned idx = 0; idx < updated_prefix_len; idx++) begin
            check_flash_byte((desc.address + idx) % M10P_FLASH_MEM_BYTES, calc_expected_byte(desc.seed + 9, idx));
          end
          for (int unsigned idx = updated_prefix_len; idx < desc.length; idx++) begin
            check_flash_byte((desc.address + idx) % M10P_FLASH_MEM_BYTES, calc_expected_byte(desc.seed, idx));
          end
          check_flash_byte((desc.address + desc.length) % M10P_FLASH_MEM_BYTES, 8'hFF);
          check_scoreboard_nominal_launch(second_len);
        end
        FM10_OVERLAP_CLEAR_PAGE_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 16);
          stage_pattern_words(16, desc.seed);
          vif.clear_page();
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("CLEAR_PAGE_REJECT", data[5], "clear-page reject did not raise PAGE_UNDERRUN");
          check_last_error_code(byte'(vif.CODE_PAGE_UNDERRUN));
        end
        FM10_OVERLAP_CLEAR_ADDR_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 12);
          stage_pattern_words(12, desc.seed);
          vif.clear_addr();
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("CLEAR_ADDR_REJECT", data[2], "clear-addr reject did not raise ADDR_MISSING");
          check_last_error_code(byte'(vif.CODE_ADDR_MISSING));
        end
        FM10_OVERLAP_BUSY_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 16);
          stage_pattern_words(16, desc.seed);
          vif.start_launch();
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("BUSY_REJECT", data[0], "busy reject bit not set");
          check_last_error_code(byte'(vif.CODE_START_WHILE_BUSY));
          vif.poll_launch_done(data);
          check_scoreboard_nominal_launch(16);
        end
        FM10_OVERLAP_RESET_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 16);
          stage_pattern_words(16, desc.seed);
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("RESET_REJECT", data[2], "addr-missing reject bit not set after idle reset cleared address");
          check_last_error_code(byte'(vif.CODE_ADDR_MISSING));
        end
        FM10_OVERLAP_ZERO_LEN_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 0);
          stage_pattern_words(4, desc.seed);
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("ZERO_REJECT", data[3], "zero-length reject bit not set");
          check_last_error_code(byte'(vif.CODE_XFER_ZERO));
        end
        FM10_OVERLAP_GT256_REJECT: begin
          write_reg(vif.REG_FLASH_ADDR, desc.address);
          write_reg(vif.REG_XFER_BYTES, 32'h0000_0101);
          stage_pattern_words(16, desc.seed);
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("GT256_REJECT", data[4], "gt256 reject bit not set");
          check_last_error_code(byte'(vif.CODE_XFER_GT_256));
        end
        FM10_OVERLAP_CLEAR_STATUS_RECOVER: begin
          write_reg(vif.REG_XFER_BYTES, 16);
          stage_pattern_words(16, desc.seed);
          vif.start_launch();
          read_reg(vif.REG_ERR_FLAGS, data);
          expect_true("CLEAR_STATUS_PRE", data[2], "missing address reject not observed before recovery");
          clear_all_error_state();
          read_reg(vif.REG_LAST_ERROR, data);
          expect_eq32("CLEAR_STATUS_ZERO", data, 32'h0000_0000);
          run_nominal_launch(desc.address, 16, desc.seed + 5);
        end
      endcase
    endtask

    task automatic run_reset_case();
      logic [31:0] data;
      logic [31:0] status_word;
      bit seen;

      write_reg(vif.REG_FLASH_ADDR, desc.address);
      write_reg(vif.REG_XFER_BYTES, desc.length);
      stage_pattern_words(desc.length, desc.seed);

      case (desc.reset_phase)
        FM10_RESET_PRE_START: begin
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.poll_ready(status_word);
          read_reg(vif.REG_STAGED_WORDS, data);
          expect_true("RESET_PRE_STAGE", data[6:0] == 0, "pre-start reset did not clear staged words");
        end
        FM10_RESET_AFTER_ACCEPT: begin
          vif.start_launch();
          vif.poll_launch_accepted(status_word);
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.poll_ready(status_word);
          wait_recovery_quiesce();
          if (env.scb.get_completed_launch_count() > 0) begin
            check_scoreboard_reset_drained_launch(desc.length);
          end else begin
            check_scoreboard_reset_aborted_before_control(desc.length);
          end
        end
        FM10_RESET_DURING_ARRIAWRITING: begin
          vif.start_launch();
          vif.wait_arriawriting_start(seen);
          expect_true("RESET_ARRIA", seen, "arriawriting never asserted before reset");
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.poll_ready(status_word);
          check_flash_pattern(desc.address, desc.length, desc.seed);
          check_scoreboard_reset_drained_launch(desc.length);
        end
        FM10_RESET_DURING_STATUS_POLL: begin
          vif.start_launch();
          wait_for_status_poll(seen);
          expect_true("RESET_STATUS", seen, "status poll never observed before reset");
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.poll_ready(status_word);
          check_flash_pattern(desc.address, desc.length, desc.seed);
          check_scoreboard_reset_drained_launch(desc.length);
        end
        default: begin
        end
      endcase

      check_last_error_code(byte'(vif.CODE_ABORTED_SW_RESET));
    endtask

    task automatic run_fault_case();
      logic [31:0] data;
      write_reg(vif.REG_FLASH_ADDR, desc.address);
      write_reg(vif.REG_XFER_BYTES, desc.length);
      stage_pattern_words(desc.length, desc.seed);

      case (desc.fault_kind)
        FM10_FAULT_LINK_TIMEOUT:  vif.inj_hold_arriawriting <= 1'b1;
        FM10_FAULT_MAX_TIMEOUT:   vif.inj_force_timeout     <= 1'b1;
        FM10_FAULT_CRC:           vif.inj_force_crcerror    <= 1'b1;
        FM10_FAULT_NSTATUS:       vif.inj_force_nstatus_low <= 1'b1;
        default: begin end
      endcase

      vif.start_launch();
      vif.poll_launch_done(data);
      read_reg(vif.REG_ERR_FLAGS, data);
      case (desc.fault_kind)
        FM10_FAULT_LINK_TIMEOUT: begin
          expect_true("FAULT_LINK", data[6], "link-timeout fault bit not set");
          check_last_error_code(byte'(vif.CODE_LINK_TIMEOUT));
        end
        FM10_FAULT_MAX_TIMEOUT: begin
          expect_true("FAULT_MAX", data[7], "max-timeout fault bit not set");
          check_last_error_code(byte'(vif.CODE_MAX10_TIMEOUT));
        end
        FM10_FAULT_CRC: begin
          expect_true("FAULT_CRC", data[9], "crc fault bit not set");
          check_last_error_code(byte'(vif.CODE_MAX10_CRCERROR));
        end
        FM10_FAULT_NSTATUS: begin
          expect_true("FAULT_NSTATUS", data[8], "nstatus fault bit not set");
          check_last_error_code(byte'(vif.CODE_MAX10_NSTATUS_LOW));
        end
        default: begin end
      endcase

      vif.clear_injections();
      check_scoreboard_nominal_launch(desc.length, 1'b0);
    endtask

    task automatic run_random_case();
      logic [31:0] data;
      if (desc.recovery_kind == FM10_RECOVERY_NONE) begin
        for (int launch_idx = 0; launch_idx < 4; launch_idx++) begin
          int unsigned local_len;
          int unsigned local_addr;
          int unsigned local_seed;
          local_len  = 3 + ((desc.seed + launch_idx) % 12);
          local_addr = desc.address + launch_idx * 32;
          local_seed = desc.seed + launch_idx * 17;
          run_nominal_launch(local_addr, local_len, local_seed);
          clear_all_error_state();
          vif.clear_page();
        end
      end else begin
        write_reg(vif.REG_FLASH_ADDR, desc.address);
        write_reg(vif.REG_XFER_BYTES, desc.length);
        stage_pattern_words(desc.length, desc.seed);
        case (desc.fault_kind)
          FM10_FAULT_MAX_TIMEOUT:   vif.inj_force_timeout     <= 1'b1;
          FM10_FAULT_CRC:           vif.inj_force_crcerror    <= 1'b1;
          FM10_FAULT_NSTATUS:       vif.inj_force_nstatus_low <= 1'b1;
          default: begin end
        endcase
        vif.start_launch();
        vif.poll_launch_done(data);
        vif.clear_injections();
        clear_all_error_state();
        if ((desc.recovery_kind == FM10_RECOVERY_RETRY_SUCCESS) &&
            (desc.fault_kind == FM10_FAULT_MAX_TIMEOUT)) begin
          vif.apply_reset();
          wait_recovery_quiesce();
        end
        if (desc.recovery_kind == FM10_RECOVERY_CLEAR_RETRY) begin
          vif.clear_page();
          wait_recovery_quiesce();
        end
        if (desc.recovery_kind == FM10_RECOVERY_RESET_RETRY) begin
          write_reg(vif.REG_CTRL, 32'h0000_0001);
          vif.poll_ready(data);
          wait_recovery_quiesce();
        end
        run_nominal_launch(desc.address + 32, desc.length + 1, desc.seed + 13);
      end
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      vif.set_clock_periods(desc.csr_half_period, desc.link_half_period);
      vif.apply_reset();

      case (desc.kind)
        FM10_KIND_LEGAL:   run_legal_case();
        FM10_KIND_OVERLAP: run_overlap_case();
        FM10_KIND_RESET:   run_reset_case();
        FM10_KIND_FAULT:   run_fault_case();
        FM10_KIND_RANDOM:  run_random_case();
        default: `uvm_fatal("CASE_KIND", $sformatf("unsupported case kind %0d", desc.kind))
      endcase

      cov.sample_desc(desc);
      phase.drop_objection(this);
    endtask
  endclass

  // --------------------------------------------------------------------------
  // Generated case wrappers
  // --------------------------------------------------------------------------

`define FM10_DECLARE_MATRIX_TEST(TEST_NAME, CASE_ID) \
  class TEST_NAME extends fm10_matrix_test_base; \
    `uvm_component_utils(TEST_NAME) \
    function new(string name, uvm_component parent); \
      super.new(name, parent); \
    endfunction \
    virtual function int unsigned get_case_id(); \
      return CASE_ID; \
    endfunction \
  endclass

  `FM10_DECLARE_MATRIX_TEST(UVM_019_LEGAL_00, 19)
  `FM10_DECLARE_MATRIX_TEST(UVM_020_LEGAL_01, 20)
  `FM10_DECLARE_MATRIX_TEST(UVM_021_LEGAL_02, 21)
  `FM10_DECLARE_MATRIX_TEST(UVM_022_LEGAL_03, 22)
  `FM10_DECLARE_MATRIX_TEST(UVM_023_LEGAL_04, 23)
  `FM10_DECLARE_MATRIX_TEST(UVM_024_LEGAL_05, 24)
  `FM10_DECLARE_MATRIX_TEST(UVM_025_LEGAL_06, 25)
  `FM10_DECLARE_MATRIX_TEST(UVM_026_LEGAL_07, 26)
  `FM10_DECLARE_MATRIX_TEST(UVM_027_LEGAL_08, 27)
  `FM10_DECLARE_MATRIX_TEST(UVM_028_LEGAL_09, 28)
  `FM10_DECLARE_MATRIX_TEST(UVM_029_LEGAL_10, 29)
  `FM10_DECLARE_MATRIX_TEST(UVM_030_LEGAL_11, 30)
  `FM10_DECLARE_MATRIX_TEST(UVM_031_LEGAL_12, 31)
  `FM10_DECLARE_MATRIX_TEST(UVM_032_LEGAL_13, 32)
  `FM10_DECLARE_MATRIX_TEST(UVM_033_LEGAL_14, 33)
  `FM10_DECLARE_MATRIX_TEST(UVM_034_LEGAL_15, 34)
  `FM10_DECLARE_MATRIX_TEST(UVM_035_LEGAL_16, 35)
  `FM10_DECLARE_MATRIX_TEST(UVM_036_LEGAL_17, 36)
  `FM10_DECLARE_MATRIX_TEST(UVM_037_LEGAL_18, 37)
  `FM10_DECLARE_MATRIX_TEST(UVM_038_LEGAL_19, 38)
  `FM10_DECLARE_MATRIX_TEST(UVM_039_LEGAL_20, 39)
  `FM10_DECLARE_MATRIX_TEST(UVM_040_LEGAL_21, 40)
  `FM10_DECLARE_MATRIX_TEST(UVM_041_LEGAL_22, 41)
  `FM10_DECLARE_MATRIX_TEST(UVM_042_LEGAL_23, 42)
  `FM10_DECLARE_MATRIX_TEST(UVM_043_LEGAL_24, 43)
  `FM10_DECLARE_MATRIX_TEST(UVM_044_LEGAL_25, 44)
  `FM10_DECLARE_MATRIX_TEST(UVM_045_LEGAL_26, 45)
  `FM10_DECLARE_MATRIX_TEST(UVM_046_LEGAL_27, 46)
  `FM10_DECLARE_MATRIX_TEST(UVM_047_LEGAL_28, 47)
  `FM10_DECLARE_MATRIX_TEST(UVM_048_LEGAL_29, 48)

  `FM10_DECLARE_MATRIX_TEST(UVM_049_OVERLAP_00, 49)
  `FM10_DECLARE_MATRIX_TEST(UVM_050_OVERLAP_01, 50)
  `FM10_DECLARE_MATRIX_TEST(UVM_051_OVERLAP_02, 51)
  `FM10_DECLARE_MATRIX_TEST(UVM_052_OVERLAP_03, 52)
  `FM10_DECLARE_MATRIX_TEST(UVM_053_OVERLAP_04, 53)
  `FM10_DECLARE_MATRIX_TEST(UVM_054_OVERLAP_05, 54)
  `FM10_DECLARE_MATRIX_TEST(UVM_055_OVERLAP_06, 55)
  `FM10_DECLARE_MATRIX_TEST(UVM_056_OVERLAP_07, 56)
  `FM10_DECLARE_MATRIX_TEST(UVM_057_OVERLAP_08, 57)
  `FM10_DECLARE_MATRIX_TEST(UVM_058_OVERLAP_09, 58)
  `FM10_DECLARE_MATRIX_TEST(UVM_059_OVERLAP_10, 59)
  `FM10_DECLARE_MATRIX_TEST(UVM_060_OVERLAP_11, 60)
  `FM10_DECLARE_MATRIX_TEST(UVM_061_OVERLAP_12, 61)
  `FM10_DECLARE_MATRIX_TEST(UVM_062_OVERLAP_13, 62)
  `FM10_DECLARE_MATRIX_TEST(UVM_063_OVERLAP_14, 63)
  `FM10_DECLARE_MATRIX_TEST(UVM_064_OVERLAP_15, 64)
  `FM10_DECLARE_MATRIX_TEST(UVM_065_OVERLAP_16, 65)
  `FM10_DECLARE_MATRIX_TEST(UVM_066_OVERLAP_17, 66)
  `FM10_DECLARE_MATRIX_TEST(UVM_067_OVERLAP_18, 67)
  `FM10_DECLARE_MATRIX_TEST(UVM_068_OVERLAP_19, 68)
  `FM10_DECLARE_MATRIX_TEST(UVM_069_OVERLAP_20, 69)
  `FM10_DECLARE_MATRIX_TEST(UVM_070_OVERLAP_21, 70)
  `FM10_DECLARE_MATRIX_TEST(UVM_071_OVERLAP_22, 71)
  `FM10_DECLARE_MATRIX_TEST(UVM_072_OVERLAP_23, 72)

  `FM10_DECLARE_MATRIX_TEST(UVM_073_RESET_00, 73)
  `FM10_DECLARE_MATRIX_TEST(UVM_074_RESET_01, 74)
  `FM10_DECLARE_MATRIX_TEST(UVM_075_RESET_02, 75)
  `FM10_DECLARE_MATRIX_TEST(UVM_076_RESET_03, 76)
  `FM10_DECLARE_MATRIX_TEST(UVM_077_RESET_04, 77)
  `FM10_DECLARE_MATRIX_TEST(UVM_078_RESET_05, 78)
  `FM10_DECLARE_MATRIX_TEST(UVM_079_RESET_06, 79)
  `FM10_DECLARE_MATRIX_TEST(UVM_080_RESET_07, 80)
  `FM10_DECLARE_MATRIX_TEST(UVM_081_RESET_08, 81)
  `FM10_DECLARE_MATRIX_TEST(UVM_082_RESET_09, 82)
  `FM10_DECLARE_MATRIX_TEST(UVM_083_RESET_10, 83)
  `FM10_DECLARE_MATRIX_TEST(UVM_084_RESET_11, 84)
  `FM10_DECLARE_MATRIX_TEST(UVM_085_RESET_12, 85)
  `FM10_DECLARE_MATRIX_TEST(UVM_086_RESET_13, 86)
  `FM10_DECLARE_MATRIX_TEST(UVM_087_RESET_14, 87)
  `FM10_DECLARE_MATRIX_TEST(UVM_088_RESET_15, 88)
  `FM10_DECLARE_MATRIX_TEST(UVM_089_RESET_16, 89)
  `FM10_DECLARE_MATRIX_TEST(UVM_090_RESET_17, 90)
  `FM10_DECLARE_MATRIX_TEST(UVM_091_RESET_18, 91)
  `FM10_DECLARE_MATRIX_TEST(UVM_092_RESET_19, 92)
  `FM10_DECLARE_MATRIX_TEST(UVM_093_RESET_20, 93)
  `FM10_DECLARE_MATRIX_TEST(UVM_094_RESET_21, 94)
  `FM10_DECLARE_MATRIX_TEST(UVM_095_RESET_22, 95)
  `FM10_DECLARE_MATRIX_TEST(UVM_096_RESET_23, 96)

  `FM10_DECLARE_MATRIX_TEST(UVM_097_FAULT_00, 97)
  `FM10_DECLARE_MATRIX_TEST(UVM_098_FAULT_01, 98)
  `FM10_DECLARE_MATRIX_TEST(UVM_099_FAULT_02, 99)
  `FM10_DECLARE_MATRIX_TEST(UVM_100_FAULT_03, 100)
  `FM10_DECLARE_MATRIX_TEST(UVM_101_FAULT_04, 101)
  `FM10_DECLARE_MATRIX_TEST(UVM_102_FAULT_05, 102)
  `FM10_DECLARE_MATRIX_TEST(UVM_103_FAULT_06, 103)
  `FM10_DECLARE_MATRIX_TEST(UVM_104_FAULT_07, 104)
  `FM10_DECLARE_MATRIX_TEST(UVM_105_FAULT_08, 105)
  `FM10_DECLARE_MATRIX_TEST(UVM_106_FAULT_09, 106)
  `FM10_DECLARE_MATRIX_TEST(UVM_107_FAULT_10, 107)
  `FM10_DECLARE_MATRIX_TEST(UVM_108_FAULT_11, 108)
  `FM10_DECLARE_MATRIX_TEST(UVM_109_FAULT_12, 109)
  `FM10_DECLARE_MATRIX_TEST(UVM_110_FAULT_13, 110)
  `FM10_DECLARE_MATRIX_TEST(UVM_111_FAULT_14, 111)
  `FM10_DECLARE_MATRIX_TEST(UVM_112_FAULT_15, 112)

  `FM10_DECLARE_MATRIX_TEST(UVM_113_RANDOM_00, 113)
  `FM10_DECLARE_MATRIX_TEST(UVM_114_RANDOM_01, 114)
  `FM10_DECLARE_MATRIX_TEST(UVM_115_RANDOM_02, 115)
  `FM10_DECLARE_MATRIX_TEST(UVM_116_RANDOM_03, 116)
  `FM10_DECLARE_MATRIX_TEST(UVM_117_RANDOM_04, 117)
  `FM10_DECLARE_MATRIX_TEST(UVM_118_RANDOM_05, 118)
  `FM10_DECLARE_MATRIX_TEST(UVM_119_RANDOM_06, 119)
  `FM10_DECLARE_MATRIX_TEST(UVM_120_RANDOM_07, 120)
  `FM10_DECLARE_MATRIX_TEST(UVM_121_RANDOM_08, 121)
  `FM10_DECLARE_MATRIX_TEST(UVM_122_RANDOM_09, 122)
  `FM10_DECLARE_MATRIX_TEST(UVM_123_RANDOM_10, 123)
  `FM10_DECLARE_MATRIX_TEST(UVM_124_RANDOM_11, 124)
  `FM10_DECLARE_MATRIX_TEST(UVM_125_RANDOM_12, 125)
  `FM10_DECLARE_MATRIX_TEST(UVM_126_RANDOM_13, 126)
  `FM10_DECLARE_MATRIX_TEST(UVM_127_RANDOM_14, 127)
  `FM10_DECLARE_MATRIX_TEST(UVM_128_RANDOM_15, 128)

`undef FM10_DECLARE_MATRIX_TEST
