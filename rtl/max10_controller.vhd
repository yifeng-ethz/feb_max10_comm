-- File name : max10_controller.vhd
-- Author    : Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision  : 0.1.0 (skeleton created)
-- Date      : 20260316
-- =========
-- Description : [FEB-side L3 MAX10 communication controller]
--
-- Function
--   This block is the L3 FEB-side transaction engine. It accepts AVMM control
--   accesses, manages page staging, drives the CDC payload queue, and sequences
--   commands toward the L2 `max10_link` layer.
--
-- Notes
--   1) This file intentionally contains only ownership partitions and blank
--      process realization.
--   2) The outer interface is kept close to the current AVMM/conduit contract
--      so later integration is straightforward.
--
-- ================ synthesizer configuration ==================
-- altera vhdl_input_version vhdl_2008
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity max10_controller is
    generic (
        CSR_ADDR_W                  : natural := 10;
        BURSTCOUNT_W                : natural := 9;
        CDC_FIFO_ADDR_W             : natural := 7;
        BOOT_HIST_AUTO_REFRESH      : natural := 0;
        DEBUG_LEVEL                 : natural := 1;
        STATUS_POLL_LIMIT           : natural := 50000;
        BUILD                       : natural := 0;
        VERSION_MAJOR               : natural := 0;
        VERSION_MINOR               : natural := 1;
        VERSION_PATCH               : natural := 0;
        IP_ID                       : natural := 16#4D313050#;
        LINK_ROLE                   : string  := "FEB"
    );
    port (
        avs_csr_address             : in    std_logic_vector(CSR_ADDR_W-1 downto 0);
        avs_csr_read                : in    std_logic;
        avs_csr_write               : in    std_logic;
        avs_csr_writedata           : in    std_logic_vector(31 downto 0);
        avs_csr_readdata            : out   std_logic_vector(31 downto 0);
        avs_csr_readdatavalid       : out   std_logic;
        avs_csr_waitrequest         : out   std_logic;
        avs_csr_burstcount          : in    std_logic_vector(BURSTCOUNT_W-1 downto 0);

        csi_csr_clk                 : in    std_logic;
        rsi_csr_reset               : in    std_logic;
        csi_link_clk                : in    std_logic;
        rsi_link_reset              : in    std_logic;

        coe_max10_spi_csn           : out   std_logic;
        coe_max10_spi_clk           : out   std_logic;
        coe_max10_spi_mosi_in       : in    std_logic;
        coe_max10_spi_mosi_out      : out   std_logic;
        coe_max10_spi_mosi_oe       : out   std_logic;
        coe_max10_spi_miso_in       : in    std_logic;
        coe_max10_spi_miso_out      : out   std_logic;
        coe_max10_spi_miso_oe       : out   std_logic;
        coe_max10_spi_d1_in         : in    std_logic;
        coe_max10_spi_d1_out        : out   std_logic;
        coe_max10_spi_d1_oe         : out   std_logic;
        coe_max10_spi_d2_in         : in    std_logic;
        coe_max10_spi_d2_out        : out   std_logic;
        coe_max10_spi_d2_oe         : out   std_logic;
        coe_max10_spi_d3_in         : in    std_logic;
        coe_max10_spi_d3_out        : out   std_logic;
        coe_max10_spi_d3_oe         : out   std_logic;

        coe_diag_summary            : out   std_logic_vector(31 downto 0);
        coe_diag_err_flags          : out   std_logic_vector(31 downto 0);
        coe_diag_last_error         : out   std_logic_vector(31 downto 0);
        coe_diag_max10_stat         : out   std_logic_vector(31 downto 0);
        coe_diag_max10_count        : out   std_logic_vector(31 downto 0)
    );
end entity max10_controller;

architecture rtl of max10_controller is

    ---------------------------------------------------------------------------
    -- Subtypes and array types
    ---------------------------------------------------------------------------
    subtype word_t is std_logic_vector(31 downto 0);
    subtype page_group_valid_t is std_logic_vector(7 downto 0);
    subtype page_prefix_len_t is natural range 0 to 8;
    subtype staged_words_count_t is natural range 0 to 64;
    type page_mem_array is array (0 to 63) of word_t;
    type page_valid_group_array_t is array (0 to 7) of page_group_valid_t;
    type page_prefix_len_array_t is array (0 to 7) of page_prefix_len_t;

    ---------------------------------------------------------------------------
    -- CSR word-offset constants (SPEC sections 4 and 5)
    ---------------------------------------------------------------------------
    constant CSR_WO_ID_CONST            : natural := 16#000#;
    constant CSR_WO_VERSION_CONST       : natural := 16#001#;
    constant CSR_WO_CTRL_CONST          : natural := 16#002#;
    constant CSR_WO_STATUS_CONST        : natural := 16#003#;
    constant CSR_WO_ERR_FLAGS_CONST     : natural := 16#004#;
    constant CSR_WO_ERR_COUNT_CONST     : natural := 16#005#;
    constant CSR_WO_SCRATCH_CONST       : natural := 16#006#;
    constant CSR_WO_FLASH_ADDR_CONST    : natural := 16#007#;
    constant CSR_WO_XFER_BYTES_CONST    : natural := 16#008#;
    constant CSR_WO_PROG_CTRL_CONST     : natural := 16#009#;
    constant CSR_WO_PROG_STATUS_CONST   : natural := 16#00A#;
    constant CSR_WO_STAGED_WORDS_CONST  : natural := 16#00B#;
    constant CSR_WO_MAX10_STAT_CONST    : natural := 16#00C#;
    constant CSR_WO_MAX10_COUNT_CONST   : natural := 16#00D#;
    constant CSR_WO_LAST_ERROR_CONST    : natural := 16#00E#;
    constant CSR_WO_PAGE_BASE_CONST     : natural := 16#020#;
    constant CSR_WO_PAGE_END_CONST      : natural := 16#05F#;

    ---------------------------------------------------------------------------
    -- FEBSPI address constants toward MAX10 (SPEC section 2.4)
    ---------------------------------------------------------------------------
    constant FEBSPI_STATUS_CONST        : std_logic_vector(6 downto 0) := "0010000"; -- 0x10
    constant FEBSPI_COUNT_CONST         : std_logic_vector(6 downto 0) := "0010001"; -- 0x11
    constant FEBSPI_CTRL_CONST          : std_logic_vector(6 downto 0) := "0010010"; -- 0x12
    constant FEBSPI_ADDR_CONST          : std_logic_vector(6 downto 0) := "0010011"; -- 0x13
    constant FEBSPI_WFIFO_CONST         : std_logic_vector(6 downto 0) := "0010100"; -- 0x14

    ---------------------------------------------------------------------------
    -- Error code constants (SPEC section 5.9)
    ---------------------------------------------------------------------------
    constant ERR_NONE_CONST             : std_logic_vector(7 downto 0) := x"00";
    constant ERR_START_BUSY_CONST       : std_logic_vector(7 downto 0) := x"01";
    constant ERR_START_RESET_CONST      : std_logic_vector(7 downto 0) := x"02";
    constant ERR_ADDR_MISSING_CONST     : std_logic_vector(7 downto 0) := x"03";
    constant ERR_XFER_ZERO_CONST        : std_logic_vector(7 downto 0) := x"04";
    constant ERR_XFER_GT_256_CONST      : std_logic_vector(7 downto 0) := x"05";
    constant ERR_PAGE_UNDERRUN_CONST    : std_logic_vector(7 downto 0) := x"06";
    constant ERR_LINK_TIMEOUT_CONST     : std_logic_vector(7 downto 0) := x"07";
    constant ERR_MAX10_TIMEOUT_CONST    : std_logic_vector(7 downto 0) := x"08";
    constant ERR_MAX10_NSTATUS_CONST    : std_logic_vector(7 downto 0) := x"09";
    constant ERR_MAX10_CRCERROR_CONST   : std_logic_vector(7 downto 0) := x"0A";
    constant ERR_SW_RESET_CONST         : std_logic_vector(7 downto 0) := x"80";

    -- Timeout limit in link_clk cycles (~1 ms at 50 MHz)
    function pack_last_error_f(
        constant err_code_in            : std_logic_vector(7 downto 0);
        constant staged_words_in        : natural;
        constant max10_status_hi_in     : std_logic_vector(7 downto 0)
    ) return word_t is
        variable word_v                 : word_t := (others => '0');
    begin
        word_v(7 downto 0)              := err_code_in;
        word_v(23 downto 16)            := std_logic_vector(to_unsigned(staged_words_in, 8));
        word_v(31 downto 24)            := max10_status_hi_in;
        return word_v;
    end function pack_last_error_f;

    function prefix_len_f(
        constant group_bits_in          : page_group_valid_t
    ) return page_prefix_len_t is
    begin
        for bit_index_v in 0 to 7 loop
            if group_bits_in(bit_index_v) = '0' then
                return bit_index_v;
            end if;
        end loop;
        return 8;
    end function prefix_len_f;

    function advance_count_f(
        constant page_prefix_len_in     : page_prefix_len_array_t;
        constant start_group_in         : natural
    ) return staged_words_count_t is
        variable next_count_v           : staged_words_count_t;
    begin
        next_count_v                    := start_group_in * 8 + page_prefix_len_in(start_group_in);
        if page_prefix_len_in(start_group_in) /= 8 then
            return next_count_v;
        end if;
        for group_index_v in 0 to 7 loop
            if group_index_v > start_group_in then
                next_count_v                := group_index_v * 8 + page_prefix_len_in(group_index_v);
                if page_prefix_len_in(group_index_v) /= 8 then
                    return next_count_v;
                end if;
            end if;
        end loop;
        return 64;
    end function advance_count_f;

    ---------------------------------------------------------------------------
    -- Record types: csr_slave (proc_csr_slave owner, csr_clk domain)
    ---------------------------------------------------------------------------
    type csr_slave_config_reg_t is record
        flash_addr                  : std_logic_vector(23 downto 0);
        flash_addr_valid            : std_logic;
        xfer_bytes                  : unsigned(8 downto 0);
        scratch                     : word_t;
    end record csr_slave_config_reg_t;

    type csr_slave_status_reg_t is record
        ready                       : std_logic;
        busy                        : std_logic;
        resetting                   : std_logic;
        launch_accepted             : std_logic;
        launch_done                 : std_logic;
    end record csr_slave_status_reg_t;

    type csr_slave_error_reg_t is record
        err_flags                   : word_t;
        err_count                   : unsigned(31 downto 0);
        last_error                  : word_t;
    end record csr_slave_error_reg_t;

    type csr_slave_debug_reg_t is record
        max10_stat                  : word_t;
        max10_count                 : word_t;
    end record csr_slave_debug_reg_t;

    -- CDC sync chain from link domain into csr domain
    type csr_slave_cdc_reg_t is record
        done_toggle_meta            : std_logic;
        done_toggle_sync            : std_logic;
        done_toggle_prev            : std_logic;
        stat_meta                   : word_t;
        count_meta                  : word_t;
        err_flags_meta              : word_t;
        err_code_meta               : std_logic_vector(7 downto 0);
    end record csr_slave_cdc_reg_t;

    type csr_slave_reg_t is record
        config                      : csr_slave_config_reg_t;
        status                      : csr_slave_status_reg_t;
        error                       : csr_slave_error_reg_t;
        debug                       : csr_slave_debug_reg_t;
        cdc                         : csr_slave_cdc_reg_t;
    end record csr_slave_reg_t;

    type csr_error_pipe_reg_t is record
        count_inc_pending           : std_logic;
        start_busy_pending          : std_logic;
        start_reset_pending         : std_logic;
        addr_missing_pending        : std_logic;
        xfer_zero_pending           : std_logic;
        xfer_gt_256_pending         : std_logic;
        page_underrun_pending       : std_logic;
    end record csr_error_pipe_reg_t;

    ---------------------------------------------------------------------------
    -- Record types: stage_store (proc_stage_store owner, csr_clk domain)
    ---------------------------------------------------------------------------
    type stage_store_reg_t is record
        page_data                   : page_mem_array;
        page_valid_groups           : page_valid_group_array_t;
        page_prefix_len             : page_prefix_len_array_t;
        staged_words_count          : staged_words_count_t;
        launch_page_data            : page_mem_array;
    end record stage_store_reg_t;

    type stage_pipe_reg_t is record
        write_valid                 : std_logic;
        write_index                 : natural range 0 to 63;
        write_group_sel            : std_logic_vector(7 downto 0);
        write_mask                 : page_group_valid_t;
        write_data                  : word_t;
    end record stage_pipe_reg_t;

    type count_pipe_reg_t is record
        advance_valid               : std_logic;
    end record count_pipe_reg_t;

    type start_pipe_reg_t is record
        eval_pending                : std_logic;
        accept_pending              : std_logic;
        flash_addr                  : std_logic_vector(23 downto 0);
        flash_addr_valid            : std_logic;
        xfer_bytes                  : unsigned(8 downto 0);
        busy                        : std_logic;
        resetting                   : std_logic;
    end record start_pipe_reg_t;

    ---------------------------------------------------------------------------
    -- Record types: cdc_pusher (proc_cdc_pusher owner, csr_clk domain)
    ---------------------------------------------------------------------------
    type cdc_pusher_fsm_t is (
        CDC_PUSHER_STATE_RESETTING,
        CDC_PUSHER_STATE_IDLING,
        CDC_PUSHER_STATE_PUSHING_HEADER,
        CDC_PUSHER_STATE_PUSHING_PAYLOAD
    );

    type cdc_pusher_state_reg_t is record
        fsm                         : cdc_pusher_fsm_t;
        active                      : std_logic;
        word_index                  : natural range 0 to 63;
        words_required              : natural range 0 to 64;
        launch_flash_addr           : std_logic_vector(23 downto 0);
        launch_xfer_bytes           : unsigned(8 downto 0);
        launch_toggle               : std_logic;
    end record cdc_pusher_state_reg_t;

    type cdc_pusher_debug_reg_t is record
        last_fifo_word              : std_logic_vector(39 downto 0);
        last_pushed_index           : natural range 0 to 63;
    end record cdc_pusher_debug_reg_t;

    type cdc_pusher_reg_t is record
        state                       : cdc_pusher_state_reg_t;
        debug                       : cdc_pusher_debug_reg_t;
    end record cdc_pusher_reg_t;

    ---------------------------------------------------------------------------
    -- Record types: max_master (proc_max_master owner, link_clk domain)
    ---------------------------------------------------------------------------
    type max_master_state_t is (
        MAX_MASTER_STATE_RESETTING,
        MAX_MASTER_STATE_IDLING,
        MAX_MASTER_STATE_POPPING_HEADER,
        MAX_MASTER_STATE_PRIMING_WFIFO,
        MAX_MASTER_STATE_PUMPING_WFIFO,
        MAX_MASTER_STATE_WAITING_WFIFO,
        MAX_MASTER_STATE_WRITING_ADDR,
        MAX_MASTER_STATE_WAITING_ADDR,
        MAX_MASTER_STATE_WRITING_CTRL_START,
        MAX_MASTER_STATE_WAITING_CTRL_START,
        MAX_MASTER_STATE_POLLING_STATUS,
        MAX_MASTER_STATE_WAITING_STATUS,
        MAX_MASTER_STATE_CHECKING_STATUS,
        MAX_MASTER_STATE_WRITING_CTRL_STOP,
        MAX_MASTER_STATE_WAITING_CTRL_STOP,
        MAX_MASTER_STATE_READING_COUNT,
        MAX_MASTER_STATE_WAITING_COUNT,
        MAX_MASTER_STATE_NOTIFYING
    );

    type max_master_config_reg_t is record
        launch_toggle_sync          : std_logic_vector(2 downto 0);
        reset_sync                  : std_logic_vector(2 downto 0);
        launch_flash_addr           : std_logic_vector(23 downto 0);
        launch_xfer_bytes           : unsigned(8 downto 0);
    end record max_master_config_reg_t;

    type max_master_runtime_reg_t is record
        done_toggle                 : std_logic;
        ctrl_start_issued           : std_logic;
        cmd_valid                   : std_logic;
        cmd_addr                    : std_logic_vector(6 downto 0);
        cmd_write                   : std_logic;
        cmd_wdata                   : word_t;
        cmd_numbytes                : std_logic_vector(8 downto 0);
        payload_words_total         : natural range 0 to 64;
        payload_words_sent          : natural range 0 to 64;
        status_poll_count           : natural range 0 to 65535;
    end record max_master_runtime_reg_t;

    type max_master_debug_reg_t is record
        max10_stat                  : word_t;
        max10_count                 : word_t;
        err_flags                   : word_t;
        err_code                    : std_logic_vector(7 downto 0);
    end record max_master_debug_reg_t;

    type max_master_reg_t is record
        config                      : max_master_config_reg_t;
        state                       : max_master_state_t;
        runtime                     : max_master_runtime_reg_t;
        debug                       : max_master_debug_reg_t;
    end record max_master_reg_t;

    ---------------------------------------------------------------------------
    -- Reset image constants
    ---------------------------------------------------------------------------
    constant CSR_SLAVE_RESET_CONST : csr_slave_reg_t := (
        config => (
            flash_addr              => (others => '0'),
            flash_addr_valid        => '0',
            xfer_bytes              => to_unsigned(256, 9),
            scratch                 => (others => '0')
        ),
        status => (
            ready                   => '1',
            busy                    => '0',
            resetting               => '0',
            launch_accepted         => '0',
            launch_done             => '0'
        ),
        error => (
            err_flags               => (others => '0'),
            err_count               => (others => '0'),
            last_error              => (others => '0')
        ),
        debug => (
            max10_stat              => (others => '0'),
            max10_count             => (others => '0')
        ),
        cdc => (
            done_toggle_meta        => '0',
            done_toggle_sync        => '0',
            done_toggle_prev        => '0',
            stat_meta               => (others => '0'),
            count_meta              => (others => '0'),
            err_flags_meta          => (others => '0'),
            err_code_meta           => (others => '0')
        )
    );

    constant CSR_ERROR_PIPE_RESET_CONST : csr_error_pipe_reg_t := (
        count_inc_pending           => '0',
        start_busy_pending          => '0',
        start_reset_pending         => '0',
        addr_missing_pending        => '0',
        xfer_zero_pending           => '0',
        xfer_gt_256_pending         => '0',
        page_underrun_pending       => '0'
    );

    constant STAGE_STORE_RESET_CONST : stage_store_reg_t := (
        page_data                   => (others => (others => '0')),
        page_valid_groups           => (others => (others => '0')),
        page_prefix_len             => (others => 0),
        staged_words_count          => 0,
        launch_page_data            => (others => (others => '0'))
    );

    constant STAGE_PIPE_RESET_CONST : stage_pipe_reg_t := (
        write_valid                 => '0',
        write_index                 => 0,
        write_group_sel             => (others => '0'),
        write_mask                  => (others => '0'),
        write_data                  => (others => '0')
    );

    constant COUNT_PIPE_RESET_CONST : count_pipe_reg_t := (
        advance_valid               => '0'
    );

    constant START_PIPE_RESET_CONST : start_pipe_reg_t := (
        eval_pending                => '0',
        accept_pending              => '0',
        flash_addr                  => (others => '0'),
        flash_addr_valid            => '0',
        xfer_bytes                  => to_unsigned(256, 9),
        busy                        => '0',
        resetting                   => '0'
    );

    constant CDC_PUSHER_RESET_CONST : cdc_pusher_reg_t := (
        state => (
            fsm                     => CDC_PUSHER_STATE_RESETTING,
            active                  => '0',
            word_index              => 0,
            words_required          => 0,
            launch_flash_addr       => (others => '0'),
            launch_xfer_bytes       => to_unsigned(256, 9),
            launch_toggle           => '0'
        ),
        debug => (
            last_fifo_word          => (others => '0'),
            last_pushed_index       => 0
        )
    );

    constant MAX_MASTER_RESET_CONST : max_master_reg_t := (
        config => (
            launch_toggle_sync      => (others => '0'),
            reset_sync              => (others => '0'),
            launch_flash_addr       => (others => '0'),
            launch_xfer_bytes       => to_unsigned(256, 9)
        ),
        state => MAX_MASTER_STATE_RESETTING,
        runtime => (
            done_toggle             => '0',
            ctrl_start_issued       => '0',
            cmd_valid               => '0',
            cmd_addr                => (others => '0'),
            cmd_write               => '0',
            cmd_wdata               => (others => '0'),
            cmd_numbytes            => (others => '0'),
            payload_words_total     => 0,
            payload_words_sent      => 0,
            status_poll_count       => 0
        ),
        debug => (
            max10_stat              => (others => '0'),
            max10_count             => (others => '0'),
            err_flags               => (others => '0'),
            err_code                => (others => '0')
        )
    );

    ---------------------------------------------------------------------------
    -- Owner record signals
    ---------------------------------------------------------------------------
    signal csr_slave                : csr_slave_reg_t   := CSR_SLAVE_RESET_CONST;
    signal csr_error_pipe           : csr_error_pipe_reg_t := CSR_ERROR_PIPE_RESET_CONST;
    signal stage_store              : stage_store_reg_t  := STAGE_STORE_RESET_CONST;
    signal stage_pipe               : stage_pipe_reg_t  := STAGE_PIPE_RESET_CONST;
    signal count_pipe               : count_pipe_reg_t  := COUNT_PIPE_RESET_CONST;
    signal start_pipe               : start_pipe_reg_t := START_PIPE_RESET_CONST;
    signal cdc_pusher               : cdc_pusher_reg_t  := CDC_PUSHER_RESET_CONST;
    signal max_master               : max_master_reg_t  := MAX_MASTER_RESET_CONST;

    ---------------------------------------------------------------------------
    -- Inter-process command pulses (csr_clk, driven by proc_csr_slave)
    ---------------------------------------------------------------------------
    signal csr_cmd_clear_page       : std_logic := '0';
    signal csr_cmd_launch_snap      : std_logic := '0';
    signal csr_cmd_launch_accept    : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Registered contiguous valid prefix count mirrored out of stage_store
    ---------------------------------------------------------------------------
    signal staged_words_count       : staged_words_count_t;
    signal staged_words_count_preview : staged_words_count_t;

    ---------------------------------------------------------------------------
    -- CDC FIFO signals (40-bit: 8-bit tag + 32-bit data)
    ---------------------------------------------------------------------------
    signal cdc_fifo_wrreq           : std_logic := '0';
    signal cdc_fifo_wrdata          : std_logic_vector(39 downto 0) := (others => '0');
    signal cdc_fifo_wrfull          : std_logic;
    signal cdc_fifo_rdreq           : std_logic := '0';
    signal cdc_fifo_rddata          : std_logic_vector(39 downto 0);
    signal cdc_fifo_rdempty         : std_logic;

    ---------------------------------------------------------------------------
    -- max10_link interface signals
    ---------------------------------------------------------------------------
    signal max_link_cmd_ready       : std_logic;
    signal max_link_rsp_word        : word_t;
    signal max_link_rsp_word_valid  : std_logic;
    signal max_link_rsp_byte        : std_logic_vector(7 downto 0);
    signal max_link_rsp_byte_valid  : std_logic;
    signal max_link_busy            : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Concurrent assignments
    ---------------------------------------------------------------------------
    avs_csr_waitrequest             <= '0';
    avs_csr_readdatavalid           <= avs_csr_read;
    -- avs_csr_readdata driven by proc_csr_read

    coe_diag_summary(0)             <= csr_slave.status.ready;
    coe_diag_summary(1)             <= csr_slave.status.busy;
    coe_diag_summary(2)             <= '1' when csr_slave.error.err_flags /= x"00000000" else '0';
    coe_diag_summary(3)             <= csr_slave.status.resetting;
    coe_diag_summary(31 downto 4)   <= (others => '0');
    coe_diag_err_flags              <= csr_slave.error.err_flags;
    coe_diag_last_error             <= csr_slave.error.last_error;
    coe_diag_max10_stat             <= csr_slave.debug.max10_stat;
    coe_diag_max10_count            <= csr_slave.debug.max10_count;

    staged_words_count              <= stage_store.staged_words_count;

    proc_stage_count_preview : process (all)
    begin
        if csr_cmd_clear_page = '1' then
            staged_words_count_preview   <= 0;
        elsif count_pipe.advance_valid = '1' then
            staged_words_count_preview   <= advance_count_f(stage_store.page_prefix_len, 0);
        else
            staged_words_count_preview   <= staged_words_count;
        end if;
    end process proc_stage_count_preview;

    ---------------------------------------------------------------------------
    -- CDC dual-clock FIFO: csr_clk write side, link_clk read side
    -- 40-bit wide, showahead mode for simpler read sequencing
    ---------------------------------------------------------------------------
    u_cdc_fifo : entity work.dcfifo_40x128
        port map (
            aclr                    => rsi_csr_reset,
            wrclk                   => csi_csr_clk,
            wrreq                   => cdc_fifo_wrreq,
            data                    => cdc_fifo_wrdata,
            wrfull                  => cdc_fifo_wrfull,
            rdclk                   => csi_link_clk,
            rdreq                   => cdc_fifo_rdreq,
            q                      => cdc_fifo_rddata,
            rdempty                 => cdc_fifo_rdempty
        );

    ---------------------------------------------------------------------------
    -- L2 link layer instance
    ---------------------------------------------------------------------------
    max_link : entity work.max10_link
        generic map (
            ROLE                    => LINK_ROLE,
            DEBUG_LEVEL             => DEBUG_LEVEL
        )
        port map (
            csi_clk                 => csi_link_clk,
            rsi_reset               => rsi_link_reset,
            cmd_valid               => max_master.runtime.cmd_valid,
            cmd_ready               => max_link_cmd_ready,
            cmd_addr                => max_master.runtime.cmd_addr,
            cmd_write               => max_master.runtime.cmd_write,
            cmd_wdata               => max_master.runtime.cmd_wdata,
            cmd_numbytes            => max_master.runtime.cmd_numbytes,
            rsp_word                => max_link_rsp_word,
            rsp_word_valid          => max_link_rsp_word_valid,
            rsp_byte                => max_link_rsp_byte,
            rsp_byte_valid          => max_link_rsp_byte_valid,
            link_busy               => max_link_busy,
            coe_spi_csn             => coe_max10_spi_csn,
            coe_spi_clk             => coe_max10_spi_clk,
            coe_spi_mosi_in         => coe_max10_spi_mosi_in,
            coe_spi_mosi_out        => coe_max10_spi_mosi_out,
            coe_spi_mosi_oe         => coe_max10_spi_mosi_oe,
            coe_spi_miso_in         => coe_max10_spi_miso_in,
            coe_spi_miso_out        => coe_max10_spi_miso_out,
            coe_spi_miso_oe         => coe_max10_spi_miso_oe,
            coe_spi_d1_in           => coe_max10_spi_d1_in,
            coe_spi_d1_out          => coe_max10_spi_d1_out,
            coe_spi_d1_oe           => coe_max10_spi_d1_oe,
            coe_spi_d2_in           => coe_max10_spi_d2_in,
            coe_spi_d2_out          => coe_max10_spi_d2_out,
            coe_spi_d2_oe           => coe_max10_spi_d2_oe,
            coe_spi_d3_in           => coe_max10_spi_d3_in,
            coe_spi_d3_out          => coe_max10_spi_d3_out,
            coe_spi_d3_oe           => coe_max10_spi_d3_oe
        );

    ---------------------------------------------------------------------------
    -- proc_csr_slave owns the AVMM-facing software-visible control/state image.
    -- Drives inter-process command pulses: csr_cmd_clear_page, csr_cmd_launch_snap,
    -- csr_cmd_launch_accept.  Runs CDC sync chains for link-domain feedback.
    ---------------------------------------------------------------------------
    proc_csr_slave : process (csi_csr_clk, rsi_csr_reset)
        variable csr_addr_v         : natural range 0 to 1023;
        variable required_words_v   : natural range 0 to 128;
        variable page_ready_v       : boolean;
        variable done_edge_v        : boolean;
    begin
        if rsi_csr_reset = '1' then
            csr_slave               <= CSR_SLAVE_RESET_CONST;
            csr_error_pipe          <= CSR_ERROR_PIPE_RESET_CONST;
            start_pipe              <= START_PIPE_RESET_CONST;
            csr_cmd_clear_page      <= '0';
            csr_cmd_launch_snap     <= '0';
            csr_cmd_launch_accept   <= '0';
        elsif rising_edge(csi_csr_clk) then
            -- Default: one-cycle command pulses clear each cycle
            csr_cmd_clear_page      <= '0';
            csr_cmd_launch_snap     <= '0';
            csr_cmd_launch_accept   <= '0';
            csr_slave.status.ready  <= '1';
            csr_error_pipe.count_inc_pending <= '0';
            csr_error_pipe.start_busy_pending <= '0';
            csr_error_pipe.start_reset_pending <= '0';
            csr_error_pipe.addr_missing_pending <= '0';
            csr_error_pipe.xfer_zero_pending <= '0';
            csr_error_pipe.xfer_gt_256_pending <= '0';
            csr_error_pipe.page_underrun_pending <= '0';

            if csr_error_pipe.count_inc_pending = '1'
               and csr_slave.error.err_count /= x"FFFFFFFF" then
                csr_slave.error.err_count       <= csr_slave.error.err_count + 1;
            end if;

            if csr_error_pipe.start_busy_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_START_BUSY_CONST,
                    staged_words_count,
                    (others => '0')
                );
            elsif csr_error_pipe.start_reset_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_START_RESET_CONST,
                    staged_words_count,
                    (others => '0')
                );
            elsif csr_error_pipe.addr_missing_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_ADDR_MISSING_CONST,
                    staged_words_count,
                    (others => '0')
                );
            elsif csr_error_pipe.xfer_zero_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_XFER_ZERO_CONST,
                    staged_words_count,
                    (others => '0')
                );
            elsif csr_error_pipe.xfer_gt_256_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_XFER_GT_256_CONST,
                    staged_words_count,
                    (others => '0')
                );
            elsif csr_error_pipe.page_underrun_pending = '1' then
                csr_slave.error.last_error      <= pack_last_error_f(
                    ERR_PAGE_UNDERRUN_CONST,
                    staged_words_count,
                    (others => '0')
                );
            end if;

            if start_pipe.accept_pending = '1' then
                csr_slave.status.busy           <= '1';
                csr_slave.status.launch_accepted <= '1';
                csr_slave.status.launch_done    <= '0';
                csr_cmd_launch_snap             <= '1';
                csr_cmd_launch_accept           <= '1';
                start_pipe.accept_pending       <= '0';
            end if;

            -- CDC sync chains: link domain -> csr domain
            csr_slave.cdc.done_toggle_meta  <= max_master.runtime.done_toggle;
            csr_slave.cdc.done_toggle_sync  <= csr_slave.cdc.done_toggle_meta;
            csr_slave.cdc.done_toggle_prev  <= csr_slave.cdc.done_toggle_sync;
            csr_slave.cdc.stat_meta         <= max_master.debug.max10_stat;
            csr_slave.debug.max10_stat      <= csr_slave.cdc.stat_meta;
            csr_slave.cdc.count_meta        <= max_master.debug.max10_count;
            csr_slave.debug.max10_count     <= csr_slave.cdc.count_meta;
            csr_slave.cdc.err_flags_meta    <= max_master.debug.err_flags;
            csr_slave.cdc.err_code_meta     <= max_master.debug.err_code;

            -- Derived variables
            csr_addr_v              := to_integer(unsigned(avs_csr_address));
            required_words_v        := to_integer((csr_slave.config.xfer_bytes + 3) / 4);
            page_ready_v            := staged_words_count_preview >= required_words_v;

            -- Detect done_toggle edge from link domain
            done_edge_v             := csr_slave.cdc.done_toggle_sync /= csr_slave.cdc.done_toggle_prev;

            ---------------------------------------------------------------
            -- Done-toggle edge: transaction completed in link domain
            ---------------------------------------------------------------
            if done_edge_v and csr_slave.status.busy = '1' then
                csr_slave.status.busy               <= '0';
                if csr_slave.status.resetting = '1' then
                    csr_slave.config.flash_addr_valid   <= '0';
                    csr_slave.config.flash_addr         <= (others => '0');
                    csr_slave.config.xfer_bytes         <= to_unsigned(256, 9);
                    csr_slave.error.err_flags           <= (others => '0');
                    csr_slave.error.err_count           <= (others => '0');
                    csr_slave.error.last_error          <= pack_last_error_f(
                        ERR_SW_RESET_CONST,
                        staged_words_count,
                        csr_slave.debug.max10_stat(31 downto 24)
                    );
                    csr_slave.status.launch_accepted    <= '0';
                    csr_slave.status.launch_done        <= '0';
                    csr_cmd_clear_page                  <= '1';
                    csr_slave.status.resetting          <= '0';
                else
                    csr_slave.status.launch_done        <= '1';
                    -- Merge link-domain errors into local error image
                    if csr_slave.cdc.err_flags_meta /= x"00000000" then
                        csr_slave.error.err_flags           <= csr_slave.error.err_flags
                                                               or csr_slave.cdc.err_flags_meta;
                        csr_slave.error.last_error          <= pack_last_error_f(
                            csr_slave.cdc.err_code_meta,
                            staged_words_count,
                            csr_slave.debug.max10_stat(31 downto 24)
                        );
                        csr_error_pipe.count_inc_pending    <= '1';
                    elsif csr_slave.cdc.err_code_meta = ERR_SW_RESET_CONST then
                        csr_slave.error.last_error          <= pack_last_error_f(
                            csr_slave.cdc.err_code_meta,
                            staged_words_count,
                            csr_slave.debug.max10_stat(31 downto 24)
                        );
                    end if;
                end if;
            end if;

            -- Sw_reset when idle: immediate completion
            if csr_slave.status.resetting = '1' and csr_slave.status.busy = '0'
               and not done_edge_v then
                csr_slave.status.resetting          <= '0';
            end if;

            ---------------------------------------------------------------
            -- Deferred start evaluation: wait until any staged PAGE_DATA
            -- write has settled into the registered prefix state before
            -- deciding accept/reject.
            ---------------------------------------------------------------
            if start_pipe.eval_pending = '1'
               and stage_pipe.write_valid = '0' then
                required_words_v                := to_integer((start_pipe.xfer_bytes + 3) / 4);
                page_ready_v                    := staged_words_count_preview >= required_words_v;

                if start_pipe.busy = '1' then
                    csr_slave.error.err_flags(0)    <= '1';
                    csr_error_pipe.start_busy_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                elsif start_pipe.resetting = '1' then
                    csr_slave.error.err_flags(1)    <= '1';
                    csr_error_pipe.start_reset_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                elsif start_pipe.flash_addr_valid = '0' then
                    csr_slave.error.err_flags(2)    <= '1';
                    csr_error_pipe.addr_missing_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                elsif start_pipe.xfer_bytes = 0 then
                    csr_slave.error.err_flags(3)    <= '1';
                    csr_error_pipe.xfer_zero_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                elsif start_pipe.xfer_bytes > 256 then
                    csr_slave.error.err_flags(4)    <= '1';
                    csr_error_pipe.xfer_gt_256_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                elsif not page_ready_v then
                    csr_slave.error.err_flags(5)    <= '1';
                    csr_error_pipe.page_underrun_pending <= '1';
                    csr_error_pipe.count_inc_pending <= '1';
                else
                    start_pipe.accept_pending      <= '1';
                end if;

                start_pipe.eval_pending            <= '0';
            end if;

            ---------------------------------------------------------------
            -- AVMM write decode
            ---------------------------------------------------------------
            if avs_csr_write = '1' then
                case csr_addr_v is

                    when CSR_WO_CTRL_CONST =>
                        -- bit 0: sw_reset
                        if avs_csr_writedata(0) = '1' then
                            csr_slave.status.resetting          <= '1';
                            start_pipe.eval_pending             <= '0';
                            start_pipe.accept_pending           <= '0';
                            -- If idle, reset local state immediately
                            if csr_slave.status.busy = '0' then
                                csr_slave.config.flash_addr_valid   <= '0';
                                csr_slave.config.flash_addr         <= (others => '0');
                                csr_slave.config.xfer_bytes         <= to_unsigned(256, 9);
                                csr_slave.error.err_flags           <= (others => '0');
                                csr_slave.error.err_count           <= (others => '0');
                                csr_slave.error.last_error          <= pack_last_error_f(
                                    ERR_SW_RESET_CONST,
                                    0,
                                    (others => '0')
                                );
                                csr_slave.status.launch_accepted    <= '0';
                                csr_slave.status.launch_done        <= '0';
                                csr_cmd_clear_page                  <= '1';
                            end if;
                            -- If busy, link domain will drain; done_edge clears resetting
                        end if;

                    when CSR_WO_ERR_FLAGS_CONST =>
                        -- RW1C: write-1-to-clear
                        csr_slave.error.err_flags           <= csr_slave.error.err_flags
                                                               and not avs_csr_writedata;

                    when CSR_WO_SCRATCH_CONST =>
                        csr_slave.config.scratch            <= avs_csr_writedata;

                    when CSR_WO_FLASH_ADDR_CONST =>
                        csr_slave.config.flash_addr         <= avs_csr_writedata(23 downto 0);
                        csr_slave.config.flash_addr_valid   <= '1';

                    when CSR_WO_XFER_BYTES_CONST =>
                        csr_slave.config.xfer_bytes         <= unsigned(avs_csr_writedata(8 downto 0));

                    when CSR_WO_PROG_CTRL_CONST =>
                        -- bit 0: start
                        if avs_csr_writedata(0) = '1' then
                            if start_pipe.eval_pending = '1'
                               or start_pipe.accept_pending = '1' then
                                csr_slave.error.err_flags(0)        <= '1';
                                csr_error_pipe.start_busy_pending   <= '1';
                                csr_error_pipe.count_inc_pending    <= '1';
                            else
                                start_pipe.eval_pending             <= '1';
                                start_pipe.flash_addr               <= csr_slave.config.flash_addr;
                                start_pipe.flash_addr_valid         <= csr_slave.config.flash_addr_valid;
                                start_pipe.xfer_bytes               <= csr_slave.config.xfer_bytes;
                                if csr_slave.status.busy = '1'
                                   or start_pipe.accept_pending = '1' then
                                    start_pipe.busy                 <= '1';
                                else
                                    start_pipe.busy                 <= '0';
                                end if;
                                start_pipe.resetting                <= csr_slave.status.resetting;
                            end if;
                        end if;
                        -- bit 1: clear_page
                        if avs_csr_writedata(1) = '1' then
                            csr_cmd_clear_page                  <= '1';
                        end if;
                        -- bit 2: clear_status
                        if avs_csr_writedata(2) = '1' then
                            csr_slave.error.last_error          <= (others => '0');
                            csr_slave.status.launch_accepted    <= '0';
                            csr_slave.status.launch_done        <= '0';
                        end if;
                        -- bit 3: clear_addr
                        if avs_csr_writedata(3) = '1' then
                            csr_slave.config.flash_addr_valid   <= '0';
                            csr_slave.config.flash_addr         <= (others => '0');
                        end if;

                    when others =>
                        null; -- PAGE_DATA writes handled by proc_stage_store
                end case;
            end if;

        end if;
    end process proc_csr_slave;

    ---------------------------------------------------------------------------
    -- proc_stage_store owns the page aperture and launch snapshot storage.
    -- Independently decodes AVMM PAGE_DATA writes.  Responds to command
    -- pulses from proc_csr_slave for clear_page and launch_snap.
    ---------------------------------------------------------------------------
    proc_stage_store : process (csi_csr_clk, rsi_csr_reset)
        variable write_addr_v           : natural range 0 to 1023;
        variable page_index_v           : natural range 0 to 63;
        variable next_count_v           : staged_words_count_t;
        variable page_valid_groups_v    : page_valid_group_array_t;
        variable page_prefix_len_v      : page_prefix_len_array_t;
        variable group_bits_v           : page_group_valid_t;
    begin
        if rsi_csr_reset = '1' then
            stage_store                     <= STAGE_STORE_RESET_CONST;
            stage_pipe                      <= STAGE_PIPE_RESET_CONST;
            count_pipe                      <= COUNT_PIPE_RESET_CONST;
        elsif rising_edge(csi_csr_clk) then
            page_valid_groups_v             := stage_store.page_valid_groups;
            page_prefix_len_v               := stage_store.page_prefix_len;
            next_count_v                    := stage_store.staged_words_count;
            stage_pipe.write_valid          <= '0';
            count_pipe.advance_valid        <= '0';

            -- Clear page on command from proc_csr_slave. Otherwise, apply the
            -- previously captured PAGE_DATA write through a one-cycle pipe,
            -- then recompute the contiguous count one cycle later from the
            -- registered prefix array.
            if csr_cmd_clear_page = '1' then
                stage_store.page_data           <= (others => (others => '0'));
                page_valid_groups_v             := (others => (others => '0'));
                page_prefix_len_v               := (others => 0);
                next_count_v                    := 0;
                count_pipe                      <= COUNT_PIPE_RESET_CONST;
            else
                if count_pipe.advance_valid = '1' then
                    next_count_v                := advance_count_f(stage_store.page_prefix_len, 0);
                end if;

                if stage_pipe.write_valid = '1' then
                    page_index_v                    := stage_pipe.write_index;

                    stage_store.page_data(page_index_v)     <= stage_pipe.write_data;
                    for group_sel_index_v in 0 to 7 loop
                        if stage_pipe.write_group_sel(group_sel_index_v) = '1' then
                            group_bits_v                    := page_valid_groups_v(group_sel_index_v)
                                                              or stage_pipe.write_mask;
                            page_valid_groups_v(group_sel_index_v)  := group_bits_v;
                            page_prefix_len_v(group_sel_index_v)    := prefix_len_f(group_bits_v);
                        end if;
                    end loop;

                    count_pipe.advance_valid        <= '1';

                end if;
            end if;

            -- Snapshot page data on launch accept
            if csr_cmd_launch_snap = '1' then
                stage_store.launch_page_data    <= stage_store.page_data;
            end if;

            if avs_csr_write = '1' then
                write_addr_v                    := to_integer(unsigned(avs_csr_address));
                if write_addr_v >= CSR_WO_PAGE_BASE_CONST
                   and write_addr_v <= CSR_WO_PAGE_END_CONST then
                    page_index_v                    := write_addr_v - CSR_WO_PAGE_BASE_CONST;
                    stage_pipe.write_valid          <= '1';
                    stage_pipe.write_index          <= page_index_v;
                    stage_pipe.write_group_sel      <= (others => '0');
                    stage_pipe.write_group_sel(page_index_v / 8) <= '1';
                    stage_pipe.write_mask           <= (others => '0');
                    stage_pipe.write_mask(page_index_v mod 8) <= '1';
                    stage_pipe.write_data           <= avs_csr_writedata;
                end if;
            end if;

            stage_store.page_valid_groups   <= page_valid_groups_v;
            stage_store.page_prefix_len     <= page_prefix_len_v;
            stage_store.staged_words_count  <= next_count_v;
        end if;
    end process proc_stage_store;

    ---------------------------------------------------------------------------
    -- proc_cdc_pusher owns the CSR-to-link CDC queue launch push path.
    -- On csr_cmd_launch_accept, pushes a header word then payload words into
    -- the dcfifo.  Toggles launch_toggle when the push sequence completes.
    -- FIFO word format: [39:32]=tag, [31:0]=data.
    --   Header: tag=0x01, data={xfer_bytes[8:0], 23'b0 | flash_addr[22:0]}
    --   Payload: tag=0x00, data=page_data[word_index]
    ---------------------------------------------------------------------------
    proc_cdc_pusher : process (csi_csr_clk, rsi_csr_reset)
        variable fifo_word_v        : std_logic_vector(39 downto 0);
    begin
        if rsi_csr_reset = '1' then
            cdc_pusher              <= CDC_PUSHER_RESET_CONST;
            cdc_fifo_wrreq          <= '0';
            cdc_fifo_wrdata         <= (others => '0');
        elsif rising_edge(csi_csr_clk) then
            -- Defaults
            cdc_fifo_wrreq          <= '0';
            fifo_word_v             := (others => '0');

            case cdc_pusher.state.fsm is

                when CDC_PUSHER_STATE_RESETTING =>
                    cdc_pusher.state.fsm        <= CDC_PUSHER_STATE_IDLING;
                    cdc_pusher.state.active      <= '0';

                when CDC_PUSHER_STATE_IDLING =>
                    cdc_pusher.state.active      <= '0';
                    if csr_cmd_launch_accept = '1' then
                        -- Latch launch parameters
                        cdc_pusher.state.launch_flash_addr <= start_pipe.flash_addr;
                        cdc_pusher.state.launch_xfer_bytes <= start_pipe.xfer_bytes;
                        cdc_pusher.state.words_required
                            <= to_integer((start_pipe.xfer_bytes + 3) / 4);
                        cdc_pusher.state.word_index        <= 0;
                        cdc_pusher.state.active            <= '1';
                        cdc_pusher.state.fsm               <= CDC_PUSHER_STATE_PUSHING_HEADER;
                    end if;

                when CDC_PUSHER_STATE_PUSHING_HEADER =>
                    if cdc_fifo_wrfull = '0' then
                        -- Header word: tag=0x01, data={xfer_bytes[8:0], flash_addr[22:0]}
                        fifo_word_v(39 downto 32)   := x"01";
                        fifo_word_v(31 downto 23)   := std_logic_vector(
                                                           cdc_pusher.state.launch_xfer_bytes);
                        fifo_word_v(22 downto 0)    := cdc_pusher.state.launch_flash_addr(22 downto 0);
                        cdc_fifo_wrdata             <= fifo_word_v;
                        cdc_fifo_wrreq              <= '1';
                        cdc_pusher.debug.last_fifo_word <= fifo_word_v;
                        if cdc_pusher.state.words_required > 0 then
                            cdc_pusher.state.fsm    <= CDC_PUSHER_STATE_PUSHING_PAYLOAD;
                        else
                            -- No payload (xfer_bytes validated at CSR; should not happen)
                            cdc_pusher.state.launch_toggle
                                <= not cdc_pusher.state.launch_toggle;
                            cdc_pusher.state.fsm    <= CDC_PUSHER_STATE_IDLING;
                        end if;
                    end if;

                when CDC_PUSHER_STATE_PUSHING_PAYLOAD =>
                    if cdc_fifo_wrfull = '0' then
                        -- Payload word: tag=0x00, data=launch_page_data[word_index]
                        fifo_word_v(39 downto 32)   := x"00";
                        fifo_word_v(31 downto 0)    := stage_store.launch_page_data(
                                                           cdc_pusher.state.word_index);
                        cdc_fifo_wrdata             <= fifo_word_v;
                        cdc_fifo_wrreq              <= '1';
                        cdc_pusher.debug.last_fifo_word     <= fifo_word_v;
                        cdc_pusher.debug.last_pushed_index  <= cdc_pusher.state.word_index;

                        if cdc_pusher.state.word_index + 1 >= cdc_pusher.state.words_required then
                            -- All payload words pushed; toggle launch signal
                            cdc_pusher.state.launch_toggle
                                <= not cdc_pusher.state.launch_toggle;
                            cdc_pusher.state.fsm    <= CDC_PUSHER_STATE_IDLING;
                        else
                            cdc_pusher.state.word_index <= cdc_pusher.state.word_index + 1;
                        end if;
                    end if;

                when others =>
                    null;
            end case;

            -- Sw_reset while idle: immediate reset
            if csr_slave.status.resetting = '1'
               and cdc_pusher.state.fsm = CDC_PUSHER_STATE_IDLING then
                cdc_pusher          <= CDC_PUSHER_RESET_CONST;
                -- Preserve launch_toggle so link domain does not see spurious edge
                cdc_pusher.state.launch_toggle <= cdc_pusher.state.launch_toggle;
                cdc_pusher.state.fsm           <= CDC_PUSHER_STATE_IDLING;
            end if;

        end if;
    end process proc_cdc_pusher;

    ---------------------------------------------------------------------------
    -- proc_max_master owns the FEB-side L3 transaction engine toward max_link.
    -- Runs in link_clk domain.  Pops header+payload from dcfifo, sequences
    -- FEBSPI register writes/reads, polls MAX10 status, toggles done_toggle.
    ---------------------------------------------------------------------------
    proc_max_master : process (csi_link_clk, rsi_link_reset)
        variable launch_edge_v          : boolean;
        variable reset_req_v            : boolean;
        variable remaining_bytes_v      : natural range 0 to 256;
    begin
        if rsi_link_reset = '1' then
            max_master                      <= MAX_MASTER_RESET_CONST;
            cdc_fifo_rdreq                  <= '0';
        elsif rising_edge(csi_link_clk) then
            -- Defaults
            cdc_fifo_rdreq                  <= '0';

            -- CDC sync chains: csr domain -> link domain
            max_master.config.launch_toggle_sync(0)     <= cdc_pusher.state.launch_toggle;
            max_master.config.launch_toggle_sync(1)     <= max_master.config.launch_toggle_sync(0);
            max_master.config.launch_toggle_sync(2)     <= max_master.config.launch_toggle_sync(1);
            max_master.config.reset_sync(0)             <= csr_slave.status.resetting;
            max_master.config.reset_sync(1)             <= max_master.config.reset_sync(0);
            max_master.config.reset_sync(2)             <= max_master.config.reset_sync(1);

            -- Edge and level detection
            launch_edge_v                   := max_master.config.launch_toggle_sync(1)
                                               /= max_master.config.launch_toggle_sync(2);
            reset_req_v                     := max_master.config.reset_sync(1) = '1';

            case max_master.state is

                when MAX_MASTER_STATE_RESETTING =>
                    max_master.runtime.cmd_valid            <= '0';
                    max_master.runtime.ctrl_start_issued    <= '0';
                    max_master.state                        <= MAX_MASTER_STATE_IDLING;

                when MAX_MASTER_STATE_IDLING =>
                    max_master.runtime.cmd_valid            <= '0';
                    max_master.runtime.ctrl_start_issued    <= '0';
                    if launch_edge_v then
                        max_master.runtime.status_poll_count    <= 0;
                        max_master.debug.max10_stat             <= (others => '0');
                        max_master.debug.max10_count            <= (others => '0');
                        max_master.debug.err_flags              <= (others => '0');
                        max_master.debug.err_code               <= ERR_NONE_CONST;
                        max_master.state                        <= MAX_MASTER_STATE_POPPING_HEADER;
                    end if;

                -- Pop header word from dcfifo (showahead: data on q when rdempty=0)
                when MAX_MASTER_STATE_POPPING_HEADER =>
                    if reset_req_v then
                        max_master.debug.err_code               <= ERR_SW_RESET_CONST;
                        max_master.state                        <= MAX_MASTER_STATE_NOTIFYING;
                    elsif cdc_fifo_rdempty = '0' then
                        -- Parse header: [31:23]=xfer_bytes, [22:0]=flash_addr
                        max_master.config.launch_xfer_bytes
                                                                <= unsigned(cdc_fifo_rddata(31 downto 23));
                        max_master.config.launch_flash_addr(22 downto 0)
                                                                <= cdc_fifo_rddata(22 downto 0);
                        max_master.config.launch_flash_addr(23) 
                                                                <= '0';
                        max_master.runtime.payload_words_total
                                                                <= to_integer((unsigned(cdc_fifo_rddata(31 downto 23)) + 3) / 4);
                        max_master.runtime.payload_words_sent   <= 0;
                        max_master.runtime.status_poll_count    <= 0;
                        cdc_fifo_rdreq                          <= '1';
                        -- Showahead fifo q still reflects the header on this cycle.
                        -- Insert one link_clk bubble so the first payload word
                        -- becomes visible before issuing the first WFIFO write.
                        max_master.state                        <= MAX_MASTER_STATE_PRIMING_WFIFO;
                    end if;

                when MAX_MASTER_STATE_PRIMING_WFIFO =>
                    if reset_req_v then
                        max_master.debug.err_code               <= ERR_SW_RESET_CONST;
                        max_master.state                        <= MAX_MASTER_STATE_NOTIFYING;
                    else
                        max_master.state                        <= MAX_MASTER_STATE_PUMPING_WFIFO;
                    end if;

                -- Pop payload word from dcfifo and issue link write to WFIFO
                when MAX_MASTER_STATE_PUMPING_WFIFO =>
                    if reset_req_v then
                        max_master.debug.err_code               <= ERR_SW_RESET_CONST;
                        max_master.state                        <= MAX_MASTER_STATE_NOTIFYING;
                    elsif cdc_fifo_rdempty = '0' then
                        remaining_bytes_v                       := to_integer(max_master.config.launch_xfer_bytes)
                                                                   - max_master.runtime.payload_words_sent * 4;
                        if remaining_bytes_v > 4 then
                            remaining_bytes_v                   := 4;
                        end if;
                        max_master.runtime.cmd_addr         <= FEBSPI_WFIFO_CONST;
                        max_master.runtime.cmd_write        <= '1';
                        max_master.runtime.cmd_wdata        <= cdc_fifo_rddata(31 downto 0);
                        max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(remaining_bytes_v, 9));
                        max_master.runtime.cmd_valid        <= '1';
                        cdc_fifo_rdreq                      <= '1';
                        max_master.state                    <= MAX_MASTER_STATE_WAITING_WFIFO;
                    end if;

                -- Wait for link to accept WFIFO write
                when MAX_MASTER_STATE_WAITING_WFIFO =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid        <= '0';
                        max_master.runtime.payload_words_sent
                                                            <= max_master.runtime.payload_words_sent + 1;
                        if max_master.runtime.payload_words_sent + 1
                           >= max_master.runtime.payload_words_total then
                            max_master.state                    <= MAX_MASTER_STATE_WRITING_ADDR;
                        else
                            max_master.state                    <= MAX_MASTER_STATE_PUMPING_WFIFO;
                        end if;
                    end if;

                -- Issue link write: flash_addr -> PROGRAMMING_ADDR
                when MAX_MASTER_STATE_WRITING_ADDR =>
                    max_master.runtime.cmd_addr         <= FEBSPI_ADDR_CONST;
                    max_master.runtime.cmd_write        <= '1';
                    max_master.runtime.cmd_wdata        <= x"00" & max_master.config.launch_flash_addr;
                    max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(4, 9));
                    max_master.runtime.cmd_valid        <= '1';
                    max_master.state                    <= MAX_MASTER_STATE_WAITING_ADDR;

                when MAX_MASTER_STATE_WAITING_ADDR =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid        <= '0';
                        max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_START;
                    end if;

                -- Issue link write: 1 -> PROGRAMMING_CTRL (start MAX10 page program)
                when MAX_MASTER_STATE_WRITING_CTRL_START =>
                    max_master.runtime.cmd_addr         <= FEBSPI_CTRL_CONST;
                    max_master.runtime.cmd_write        <= '1';
                    max_master.runtime.cmd_wdata        <= x"00000001";
                    max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(4, 9));
                    max_master.runtime.cmd_valid        <= '1';
                    max_master.state                    <= MAX_MASTER_STATE_WAITING_CTRL_START;

                when MAX_MASTER_STATE_WAITING_CTRL_START =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid            <= '0';
                        max_master.runtime.ctrl_start_issued    <= '1';
                        max_master.runtime.status_poll_count    <= 0;
                        max_master.state                        <= MAX_MASTER_STATE_POLLING_STATUS;
                    end if;

                -- Issue link read: PROGRAMMING_STATUS
                when MAX_MASTER_STATE_POLLING_STATUS =>
                    max_master.runtime.cmd_addr         <= FEBSPI_STATUS_CONST;
                    max_master.runtime.cmd_write        <= '0';
                    max_master.runtime.cmd_wdata        <= (others => '0');
                    max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(4, 9));
                    max_master.runtime.cmd_valid        <= '1';
                    max_master.state                    <= MAX_MASTER_STATE_WAITING_STATUS;

                -- Wait for link read response
                when MAX_MASTER_STATE_WAITING_STATUS =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid        <= '0';
                    end if;
                    if max_link_rsp_word_valid = '1' then
                        max_master.debug.max10_stat         <= max_link_rsp_word;
                        max_master.state                    <= MAX_MASTER_STATE_CHECKING_STATUS;
                    end if;

                -- Evaluate MAX10 programming status
                when MAX_MASTER_STATE_CHECKING_STATUS =>
                    if max_master.debug.max10_stat(18) = '1' then
                        max_master.debug.err_code           <= ERR_MAX10_TIMEOUT_CONST;
                        max_master.debug.err_flags(7)       <= '1';
                        max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_STOP;
                    elsif max_master.debug.max10_stat(19) = '1' then
                        max_master.debug.err_code           <= ERR_MAX10_CRCERROR_CONST;
                        max_master.debug.err_flags(9)       <= '1';
                        max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_STOP;
                    elsif max_master.debug.max10_stat(17) = '0' then
                        max_master.debug.err_code           <= ERR_MAX10_NSTATUS_CONST;
                        max_master.debug.err_flags(8)       <= '1';
                        max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_STOP;
                    elsif max_master.debug.max10_stat(0) = '0'
                       and max_master.debug.max10_stat(1) = '0' then
                        if reset_req_v then
                            max_master.debug.err_code           <= ERR_SW_RESET_CONST;
                        end if;
                        -- MAX10 done
                        max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_STOP;
                    else
                        -- Still busy: poll again or timeout
                        max_master.runtime.status_poll_count
                                                            <= max_master.runtime.status_poll_count + 1;
                        if max_master.runtime.status_poll_count >= STATUS_POLL_LIMIT then
                            max_master.debug.err_code           <= ERR_LINK_TIMEOUT_CONST;
                            max_master.debug.err_flags(6)       <= '1';
                            max_master.state                    <= MAX_MASTER_STATE_WRITING_CTRL_STOP;
                        else
                            max_master.state                    <= MAX_MASTER_STATE_POLLING_STATUS;
                        end if;
                    end if;

                -- Issue link write: 0 -> PROGRAMMING_CTRL (stop)
                when MAX_MASTER_STATE_WRITING_CTRL_STOP =>
                    max_master.runtime.cmd_addr         <= FEBSPI_CTRL_CONST;
                    max_master.runtime.cmd_write        <= '1';
                    max_master.runtime.cmd_wdata        <= x"00000000";
                    max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(4, 9));
                    max_master.runtime.cmd_valid        <= '1';
                    max_master.state                    <= MAX_MASTER_STATE_WAITING_CTRL_STOP;

                when MAX_MASTER_STATE_WAITING_CTRL_STOP =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid        <= '0';
                        max_master.state                    <= MAX_MASTER_STATE_READING_COUNT;
                    end if;

                -- Issue link read: PROGRAMMING_COUNT (debug)
                when MAX_MASTER_STATE_READING_COUNT =>
                    max_master.runtime.cmd_addr         <= FEBSPI_COUNT_CONST;
                    max_master.runtime.cmd_write        <= '0';
                    max_master.runtime.cmd_wdata        <= (others => '0');
                    max_master.runtime.cmd_numbytes     <= std_logic_vector(to_unsigned(4, 9));
                    max_master.runtime.cmd_valid        <= '1';
                    max_master.state                    <= MAX_MASTER_STATE_WAITING_COUNT;

                when MAX_MASTER_STATE_WAITING_COUNT =>
                    if max_link_cmd_ready = '1' and max_master.runtime.cmd_valid = '1' then
                        max_master.runtime.cmd_valid        <= '0';
                    end if;
                    if max_link_rsp_word_valid = '1' then
                        max_master.debug.max10_count        <= max_link_rsp_word;
                        max_master.state                    <= MAX_MASTER_STATE_NOTIFYING;
                    end if;

                -- Toggle done_toggle to signal CSR domain, return to idle
                when MAX_MASTER_STATE_NOTIFYING =>
                    max_master.runtime.done_toggle      <= not max_master.runtime.done_toggle;
                    max_master.runtime.cmd_valid        <= '0';
                    max_master.state                    <= MAX_MASTER_STATE_IDLING;

                when others =>
                    null;
            end case;
        end if;
    end process proc_max_master;

    ---------------------------------------------------------------------------
    -- proc_csr_read owns only the AVMM read mux (combinational).
    -- Maps csr_slave, stage_store, and derived status into the CSR window.
    ---------------------------------------------------------------------------
    proc_csr_read : process (all)
        variable addr_v                 : natural range 0 to 1023;
        variable readdata_v             : word_t;
        variable required_words_v       : natural range 0 to 128;
        variable page_ready_v           : boolean;
        variable len_valid_v            : boolean;
    begin
        addr_v                          := to_integer(unsigned(avs_csr_address));
        readdata_v                      := (others => '0');
        required_words_v                := to_integer((csr_slave.config.xfer_bytes + 3) / 4);
        page_ready_v                    := staged_words_count_preview >= required_words_v;
        len_valid_v                     := csr_slave.config.xfer_bytes >= 1
                                           and csr_slave.config.xfer_bytes <= 256;

        case addr_v is

            when CSR_WO_ID_CONST =>
                readdata_v                  := std_logic_vector(to_unsigned(IP_ID, 32));

            when CSR_WO_VERSION_CONST =>
                readdata_v(31 downto 24)    := std_logic_vector(to_unsigned(VERSION_MAJOR, 8));
                readdata_v(23 downto 16)    := std_logic_vector(to_unsigned(VERSION_MINOR, 8));
                readdata_v(15 downto 12)    := std_logic_vector(to_unsigned(VERSION_PATCH, 4));
                readdata_v(11 downto 0)     := std_logic_vector(to_unsigned(BUILD, 12));

            when CSR_WO_CTRL_CONST =>
                readdata_v(0)               := csr_slave.status.resetting;

            when CSR_WO_STATUS_CONST =>
                readdata_v(0)               := csr_slave.status.ready;
                readdata_v(1)               := csr_slave.status.busy;
                if csr_slave.error.err_flags /= x"00000000" then
                    readdata_v(2)               := '1';
                end if;
                readdata_v(3)               := csr_slave.status.resetting;

            when CSR_WO_ERR_FLAGS_CONST =>
                readdata_v                  := csr_slave.error.err_flags;

            when CSR_WO_ERR_COUNT_CONST =>
                readdata_v                  := std_logic_vector(csr_slave.error.err_count);

            when CSR_WO_SCRATCH_CONST =>
                readdata_v                  := csr_slave.config.scratch;

            when CSR_WO_FLASH_ADDR_CONST =>
                readdata_v(23 downto 0)     := csr_slave.config.flash_addr;

            when CSR_WO_XFER_BYTES_CONST =>
                readdata_v(8 downto 0)      := std_logic_vector(csr_slave.config.xfer_bytes);

            when CSR_WO_PROG_CTRL_CONST =>
                readdata_v                  := (others => '0'); -- write-only

            when CSR_WO_PROG_STATUS_CONST =>
                readdata_v(0)               := not csr_slave.status.busy and csr_slave.status.ready;
                readdata_v(1)               := csr_slave.status.busy;
                if page_ready_v then
                    readdata_v(2)               := '1';
                end if;
                readdata_v(3)               := csr_slave.config.flash_addr_valid;
                if len_valid_v then
                    readdata_v(4)               := '1';
                end if;
                readdata_v(5)               := cdc_pusher.state.active;
                readdata_v(6)               := csr_slave.status.launch_accepted;
                readdata_v(7)               := csr_slave.status.launch_done;
                -- MAX10 raw status mirrors (from debug mirror)
                readdata_v(8)               := csr_slave.debug.max10_stat(0);   -- arria_writing
                readdata_v(9)               := csr_slave.debug.max10_stat(1);   -- spi_busy
                readdata_v(10)              := csr_slave.debug.max10_stat(14);  -- fifo_empty
                readdata_v(11)              := csr_slave.debug.max10_stat(15);  -- fifo_full
                readdata_v(12)              := csr_slave.debug.max10_stat(16);  -- conf_done
                readdata_v(13)              := csr_slave.debug.max10_stat(17);  -- nstatus
                readdata_v(14)              := csr_slave.debug.max10_stat(18);  -- timeout
                readdata_v(15)              := csr_slave.debug.max10_stat(19);  -- crcerror

            when CSR_WO_STAGED_WORDS_CONST =>
                readdata_v(6 downto 0)      := std_logic_vector(to_unsigned(staged_words_count_preview, 7));

            when CSR_WO_MAX10_STAT_CONST =>
                readdata_v                  := csr_slave.debug.max10_stat;

            when CSR_WO_MAX10_COUNT_CONST =>
                readdata_v                  := csr_slave.debug.max10_count;

            when CSR_WO_LAST_ERROR_CONST =>
                readdata_v                  := csr_slave.error.last_error;

            when others =>
                -- PAGE_DATA readback (WO 0x020..0x05F)
                if addr_v >= CSR_WO_PAGE_BASE_CONST
                   and addr_v <= CSR_WO_PAGE_END_CONST then
                    readdata_v              := stage_store.page_data(addr_v - CSR_WO_PAGE_BASE_CONST);
                end if;
        end case;

        avs_csr_readdata                <= readdata_v;
    end process proc_csr_read;

end architecture rtl;
