library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.feb_max10_comm_tb_pkg.all;

entity feb_max10_comm_case_tb is
    generic (
        CASE_ID_G                   : natural := 1
    );
end entity feb_max10_comm_case_tb;

architecture sim of feb_max10_comm_case_tb is

    constant CSR_CLK_PERIOD_CONST   : time := 20 ns;
    constant MAX10_CLK_PERIOD_CONST : time := 10 ns;

    signal csi_csr_clk              : std_logic := '0';
    signal csi_link_clk             : std_logic := '0';
    signal csi_max10_clk            : std_logic := '0';
    signal rsi_csr_reset            : std_logic := '1';
    signal rsi_link_reset           : std_logic := '1';
    signal rsi_max10_reset_n        : std_logic := '0';

    signal avs_csr_address          : std_logic_vector(CSR_ADDR_W_CONST-1 downto 0) := (others => '0');
    signal avs_csr_read             : std_logic := '0';
    signal avs_csr_write            : std_logic := '0';
    signal avs_csr_writedata        : std_logic_vector(31 downto 0) := (others => '0');
    signal avs_csr_readdata         : std_logic_vector(31 downto 0);
    signal avs_csr_readdatavalid    : std_logic;
    signal avs_csr_waitrequest      : std_logic;
    signal avs_csr_burstcount       : std_logic_vector(BURSTCOUNT_W_CONST-1 downto 0) := (others => '0');

    signal inj_hold_arriawriting    : std_logic := '0';
    signal inj_force_timeout        : std_logic := '0';
    signal inj_force_crcerror       : std_logic := '0';
    signal inj_force_nstatus_low    : std_logic := '0';

    signal diag_summary             : std_logic_vector(31 downto 0);
    signal diag_err_flags           : std_logic_vector(31 downto 0);
    signal diag_last_error          : std_logic_vector(31 downto 0);
    signal diag_max10_stat          : std_logic_vector(31 downto 0);
    signal diag_max10_count         : std_logic_vector(31 downto 0);

    signal mon_link_csn             : std_logic;
    signal mon_link_clk             : std_logic;
    signal mon_link_mosi            : std_logic;
    signal mon_link_miso            : std_logic;
    signal mon_link_d1              : std_logic;
    signal mon_link_d2              : std_logic;
    signal mon_link_d3              : std_logic;

    signal dbg_status               : std_logic_vector(31 downto 0);
    signal dbg_flash_w_cnt          : std_logic_vector(31 downto 0);
    signal dbg_control              : std_logic_vector(31 downto 0);
    signal dbg_addr_from_arria      : std_logic_vector(23 downto 0);
    signal dbg_arria_addr           : std_logic_vector(6 downto 0);
    signal dbg_arria_rw             : std_logic;
    signal dbg_arria_next_data      : std_logic;
    signal dbg_arria_word_from_arria: std_logic_vector(31 downto 0);
    signal dbg_arria_word_en        : std_logic;
    signal dbg_arria_byte_from_arria: std_logic_vector(7 downto 0);
    signal dbg_arria_byte_en        : std_logic;

    signal flash_dbg_addr           : std_logic_vector(23 downto 0) := (others => '0');
    signal flash_dbg_data           : std_logic_vector(7 downto 0);
    signal flash_mon_addr           : std_logic_vector(23 downto 0) := (others => '0');
    signal flash_mon_data           : std_logic_vector(7 downto 0);
    signal flash_dbg_wip            : std_logic;
    signal flash_dbg_wel            : std_logic;

begin

    csi_csr_clk                     <= not csi_csr_clk after CSR_CLK_PERIOD_CONST / 2;
    csi_link_clk                    <= csi_csr_clk;
    csi_max10_clk                   <= not csi_max10_clk after MAX10_CLK_PERIOD_CONST / 2;

    dut : entity work.feb_max10_comm_model_wrapper
        generic map (
            CSR_ADDR_W              => CSR_ADDR_W_CONST,
            BURSTCOUNT_W            => BURSTCOUNT_W_CONST,
            DEBUG_LEVEL             => 1,
            BUILD                   => DEFAULT_BUILD_CONST
        )
        port map (
            csi_csr_clk             => csi_csr_clk,
            csi_link_clk            => csi_link_clk,
            csi_max10_clk           => csi_max10_clk,
            rsi_csr_reset           => rsi_csr_reset,
            rsi_link_reset          => rsi_link_reset,
            rsi_max10_reset_n       => rsi_max10_reset_n,
            avs_csr_address         => avs_csr_address,
            avs_csr_read            => avs_csr_read,
            avs_csr_write           => avs_csr_write,
            avs_csr_writedata       => avs_csr_writedata,
            avs_csr_readdata        => avs_csr_readdata,
            avs_csr_readdatavalid   => avs_csr_readdatavalid,
            avs_csr_waitrequest     => avs_csr_waitrequest,
            avs_csr_burstcount      => avs_csr_burstcount,
            inj_hold_arriawriting   => inj_hold_arriawriting,
            inj_force_timeout       => inj_force_timeout,
            inj_force_crcerror      => inj_force_crcerror,
            inj_force_nstatus_low   => inj_force_nstatus_low,
            diag_summary            => diag_summary,
            diag_err_flags          => diag_err_flags,
            diag_last_error         => diag_last_error,
            diag_max10_stat         => diag_max10_stat,
            diag_max10_count        => diag_max10_count,
            mon_link_csn            => mon_link_csn,
            mon_link_clk            => mon_link_clk,
            mon_link_mosi           => mon_link_mosi,
            mon_link_miso           => mon_link_miso,
            mon_link_d1             => mon_link_d1,
            mon_link_d2             => mon_link_d2,
            mon_link_d3             => mon_link_d3,
            dbg_status              => dbg_status,
            dbg_flash_w_cnt         => dbg_flash_w_cnt,
            dbg_control             => dbg_control,
            dbg_addr_from_arria     => dbg_addr_from_arria,
            dbg_arria_addr          => dbg_arria_addr,
            dbg_arria_rw            => dbg_arria_rw,
            dbg_arria_next_data     => dbg_arria_next_data,
            dbg_arria_word_from_arria => dbg_arria_word_from_arria,
            dbg_arria_word_en       => dbg_arria_word_en,
            dbg_arria_byte_from_arria => dbg_arria_byte_from_arria,
            dbg_arria_byte_en       => dbg_arria_byte_en,
            flash_dbg_addr          => flash_dbg_addr,
            flash_dbg_data          => flash_dbg_data,
            flash_mon_addr          => flash_mon_addr,
            flash_mon_data          => flash_mon_data,
            flash_dbg_wip           => flash_dbg_wip,
            flash_dbg_wel           => flash_dbg_wel
        );

    tb_stim : process
        variable readback_v         : std_logic_vector(31 downto 0);
        variable status_v           : std_logic_vector(31 downto 0);
        variable flash_byte_v       : std_logic_vector(7 downto 0);
        variable seen_arriawriting_v: boolean;
    begin
        avs_csr_burstcount          <= std_logic_vector(to_unsigned(1, BURSTCOUNT_W_CONST));
        apply_reset_proc(
            avs_csr_address,
            avs_csr_read,
            avs_csr_write,
            avs_csr_writedata,
            flash_dbg_addr,
            flash_mon_addr,
            inj_hold_arriawriting,
            inj_force_timeout,
            inj_force_crcerror,
            inj_force_nstatus_low,
            rsi_csr_reset,
            rsi_link_reset,
            rsi_max10_reset_n,
            csi_csr_clk,
            csi_max10_clk
        );

        case CASE_ID_G is
            when 1 =>
                csr_read_proc(REG_ID_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v = x"4D31_3050"
                    report "reset defaults: ID register mismatch"
                    severity failure;
                csr_read_proc(REG_VERSION_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v = packed_version_f
                    report "reset defaults: VERSION register mismatch"
                    severity failure;
                csr_read_proc(REG_XFER_BYTES_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v = x"0000_0100"
                    report "reset defaults: XFER_BYTES register mismatch"
                    severity failure;
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v = x"0000_0000"
                    report "reset defaults: ERR_FLAGS not cleared"
                    severity failure;
                csr_read_proc(REG_STATUS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(0) = '1'
                    report "reset defaults: STATUS.ready is not set"
                    severity failure;
                assert readback_v(3) = '0'
                    report "reset defaults: STATUS fault/reset state is unexpectedly set"
                    severity failure;
                report "SIM_001_RESET_DEFAULTS_PASS";

            when 2 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0012_3456", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_000C", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"0403_0201", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 2, x"0C0B_0A09", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_STAGED_WORDS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(6 downto 0) = std_logic_vector(to_unsigned(1, 7))
                    report "csr staging: contiguous prefix did not stop at missing PAGE_DATA[1]"
                    severity failure;
                csr_write_proc(REG_PAGE_BASE_CONST + 1, x"0807_0605", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_STAGED_WORDS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(6 downto 0) = std_logic_vector(to_unsigned(3, 7))
                    report "csr staging: contiguous prefix did not extend after PAGE_DATA[1] write"
                    severity failure;
                csr_read_proc(REG_PROG_STATUS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(4 downto 2) = "111"
                    report "csr staging: PROG_STATUS addr/len/page bits mismatch"
                    severity failure;
                report "SIM_002_CSR_STAGE_PREFIX_PASS";

            when 3 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0100", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(64, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                for byte_idx in 0 to 255 loop
                    expect_flash_byte_proc("full_page", byte_idx, pattern_byte_f(1, byte_idx), flash_dbg_addr, flash_dbg_data);
                end loop;
                expect_flash_byte_proc("full_page_tail", 256, x"FF", flash_dbg_addr, flash_dbg_data);
                report "SIM_003_FULL_PAGE_PROGRAM_PASS";

            when 4 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0040", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0007", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"4433_2211", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 1, x"8877_6655", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                expect_flash_byte_proc("odd_len", 16#0040#, x"11", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0041#, x"22", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0042#, x"33", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0043#, x"44", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0044#, x"55", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0045#, x"66", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len", 16#0046#, x"77", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("odd_len_tail", 16#0047#, x"FF", flash_dbg_addr, flash_dbg_data);

                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0002", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0060", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0003", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"CCBB_AA99", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                expect_flash_byte_proc("short_len", 16#0060#, x"99", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("short_len", 16#0061#, x"AA", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("short_len", 16#0062#, x"BB", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("short_len_tail", 16#0063#, x"FF", flash_dbg_addr, flash_dbg_data);
                report "SIM_004_PARTIAL_ODD_PASS";

            when 5 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0100", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_000B", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"4433_2211", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 1, x"8877_6655", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 2, x"00BB_AA99", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                wait_arriawriting_start_proc(csi_max10_clk, dbg_status, seen_arriawriting_v);
                assert seen_arriawriting_v
                    report "snapshot isolation: launch never reached ARRIAWRITING"
                    severity failure;
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"DDCC_BBAA", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 1, x"1100_FFEE", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                expect_flash_byte_proc("snap_gen1", 16#0100#, x"11", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0101#, x"22", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0102#, x"33", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0103#, x"44", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0104#, x"55", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0105#, x"66", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0106#, x"77", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0107#, x"88", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0108#, x"99", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#0109#, x"AA", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen1", 16#010A#, x"BB", flash_dbg_addr, flash_dbg_data);

                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0100", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0007", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                expect_flash_byte_proc("snap_gen2", 16#0100#, x"AA", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0101#, x"BB", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0102#, x"CC", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0103#, x"DD", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0104#, x"EE", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0105#, x"FF", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2", 16#0106#, x"00", flash_dbg_addr, flash_dbg_data);
                expect_flash_byte_proc("snap_gen2_tail", 16#0107#, x"88", flash_dbg_addr, flash_dbg_data);
                report "SIM_005_BACK_TO_BACK_SNAPSHOT_PASS";

            when 6 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(0) = '1'
                    report "rejects: START_WHILE_BUSY flag not set"
                    severity failure;
                expect_last_error_proc(CODE_START_WHILE_BUSY_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(2) = '1'
                    report "rejects: ADDR_MISSING flag not set"
                    severity failure;
                expect_last_error_proc(CODE_ADDR_MISSING_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"0403_0201", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(3) = '1'
                    report "rejects: XFER_ZERO flag not set"
                    severity failure;
                expect_last_error_proc(CODE_XFER_ZERO_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0101", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(4) = '1'
                    report "rejects: XFER_GT_256 flag not set"
                    severity failure;
                expect_last_error_proc(CODE_XFER_GT_256_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 0, x"0403_0201", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PAGE_BASE_CONST + 2, x"0C0B_0A09", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(5) = '1'
                    report "rejects: PAGE_UNDERRUN flag not set"
                    severity failure;
                expect_last_error_proc(CODE_PAGE_UNDERRUN_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);
                report "SIM_006_LAUNCH_REJECTS_PASS";

            when 7 =>
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0040", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_ready_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                csr_read_proc(REG_STAGED_WORDS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(6 downto 0) = std_logic_vector(to_unsigned(0, 7))
                    report "flush paths: staged words not cleared by prelaunch software reset"
                    severity failure;
                csr_read_proc(REG_FLASH_ADDR_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(23 downto 0) = x"000000"
                    report "flush paths: flash address not cleared by prelaunch software reset"
                    severity failure;
                expect_last_error_proc(CODE_ABORTED_SW_RESET_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);
                expect_flash_byte_proc("flush_prelaunch_tail", 16#0040#, x"FF", flash_dbg_addr, flash_dbg_data);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                wait_arriawriting_start_proc(csi_max10_clk, dbg_status, seen_arriawriting_v);
                assert seen_arriawriting_v
                    report "flush paths: downstream launch never reached ARRIAWRITING before reset"
                    severity failure;
                csr_write_proc(REG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_ready_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                expect_last_error_proc(CODE_ABORTED_SW_RESET_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);
                for byte_idx in 0 to 15 loop
                    expect_flash_byte_proc("flush_during_program", byte_idx, pattern_byte_f(1, byte_idx), flash_dbg_addr, flash_dbg_data);
                end loop;
                csr_read_proc(REG_STAGED_WORDS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(6 downto 0) = std_logic_vector(to_unsigned(0, 7))
                    report "flush paths: staged words not cleared after drained reset"
                    severity failure;
                report "SIM_007_SW_RESET_FLUSH_PASS";

            when 8 =>
                inj_force_timeout      <= '1';
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0000", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(7) = '1'
                    report "fault paths: MAX10_TIMEOUT flag not set"
                    severity failure;
                expect_last_error_proc(CODE_MAX10_TIMEOUT_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                inj_force_crcerror     <= '1';
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0020", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(9) = '1'
                    report "fault paths: MAX10_CRCERROR flag not set"
                    severity failure;
                expect_last_error_proc(CODE_MAX10_CRCERROR_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);

                apply_reset_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata, flash_dbg_addr, flash_mon_addr,
                                 inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low,
                                 rsi_csr_reset, rsi_link_reset, rsi_max10_reset_n, csi_csr_clk, csi_max10_clk);
                inj_force_nstatus_low  <= '1';
                csr_write_proc(REG_FLASH_ADDR_CONST, x"0000_0040", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_XFER_BYTES_CONST, x"0000_0010", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                stage_pattern_words_proc(4, 1, avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                csr_write_proc(REG_PROG_CTRL_CONST, x"0000_0001", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
                poll_launch_done_proc(avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
                csr_read_proc(REG_ERR_FLAGS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
                assert readback_v(8) = '1'
                    report "fault paths: MAX10_NSTATUS_LOW flag not set"
                    severity failure;
                expect_last_error_proc(CODE_MAX10_NSTATUS_LOW_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk);
                report "SIM_008_FAULT_INJECTION_PASS";

            when others =>
                assert false report "unsupported CASE_ID_G value" severity failure;
        end case;

        report "Time: " & time'image(now);
        finish;
    end process tb_stim;

end architecture sim;
