library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package feb_max10_comm_tb_pkg is

    constant CSR_ADDR_W_CONST           : natural := 10;
    constant BURSTCOUNT_W_CONST         : natural := 9;
    constant DEFAULT_BUILD_CONST        : natural := 16#123#;

    constant REG_ID_CONST               : natural := 16#000#;
    constant REG_VERSION_CONST          : natural := 16#001#;
    constant REG_CTRL_CONST             : natural := 16#002#;
    constant REG_STATUS_CONST           : natural := 16#003#;
    constant REG_ERR_FLAGS_CONST        : natural := 16#004#;
    constant REG_ERR_COUNT_CONST        : natural := 16#005#;
    constant REG_SCRATCH_CONST          : natural := 16#006#;
    constant REG_FLASH_ADDR_CONST       : natural := 16#007#;
    constant REG_XFER_BYTES_CONST       : natural := 16#008#;
    constant REG_PROG_CTRL_CONST        : natural := 16#009#;
    constant REG_PROG_STATUS_CONST      : natural := 16#00A#;
    constant REG_STAGED_WORDS_CONST     : natural := 16#00B#;
    constant REG_MAX10_STAT_CONST       : natural := 16#00C#;
    constant REG_MAX10_COUNT_CONST      : natural := 16#00D#;
    constant REG_LAST_ERROR_CONST       : natural := 16#00E#;
    constant REG_PAGE_BASE_CONST        : natural := 16#020#;

    constant CODE_START_WHILE_BUSY_CONST   : std_logic_vector(7 downto 0) := x"01";
    constant CODE_START_DURING_RESET_CONST : std_logic_vector(7 downto 0) := x"02";
    constant CODE_ADDR_MISSING_CONST       : std_logic_vector(7 downto 0) := x"03";
    constant CODE_XFER_ZERO_CONST          : std_logic_vector(7 downto 0) := x"04";
    constant CODE_XFER_GT_256_CONST        : std_logic_vector(7 downto 0) := x"05";
    constant CODE_PAGE_UNDERRUN_CONST      : std_logic_vector(7 downto 0) := x"06";
    constant CODE_LINK_TIMEOUT_CONST       : std_logic_vector(7 downto 0) := x"07";
    constant CODE_MAX10_TIMEOUT_CONST      : std_logic_vector(7 downto 0) := x"08";
    constant CODE_MAX10_NSTATUS_LOW_CONST  : std_logic_vector(7 downto 0) := x"09";
    constant CODE_MAX10_CRCERROR_CONST     : std_logic_vector(7 downto 0) := x"0A";
    constant CODE_ABORTED_SW_RESET_CONST   : std_logic_vector(7 downto 0) := x"80";
    constant POLL_LAUNCH_DONE_MAX_POLLS_CONST : natural := 40000;

    subtype word_t is std_logic_vector(31 downto 0);
    subtype byte_t is std_logic_vector(7 downto 0);
    type word_array_t is array (natural range <>) of word_t;

    function packed_version_f(build_value : natural := DEFAULT_BUILD_CONST) return word_t;
    function pack_word_f(byte0 : natural; byte1 : natural; byte2 : natural; byte3 : natural) return word_t;
    function pattern_word_f(base_byte : natural; word_index : natural) return word_t;
    function pattern_byte_f(base_byte : natural; byte_index : natural) return byte_t;

    procedure csr_idle_proc(
        signal avs_csr_address   : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read      : out std_logic;
        signal avs_csr_write     : out std_logic;
        signal avs_csr_writedata : out std_logic_vector(31 downto 0)
    );

    procedure clear_injections_proc(
        signal inj_hold_arriawriting : out std_logic;
        signal inj_force_timeout     : out std_logic;
        signal inj_force_crcerror    : out std_logic;
        signal inj_force_nstatus_low : out std_logic
    );

    procedure apply_reset_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_write         : out std_logic;
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_mon_addr        : out std_logic_vector(23 downto 0);
        signal inj_hold_arriawriting : out std_logic;
        signal inj_force_timeout     : out std_logic;
        signal inj_force_crcerror    : out std_logic;
        signal inj_force_nstatus_low : out std_logic;
        signal rsi_csr_reset         : out std_logic;
        signal rsi_link_reset        : out std_logic;
        signal rsi_max10_reset_n     : out std_logic;
        signal csi_csr_clk           : in  std_logic;
        signal csi_max10_clk         : in  std_logic
    );

    procedure csr_write_proc(
        constant avmm_addr           : in  natural;
        constant avmm_data           : in  std_logic_vector(31 downto 0);
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    );

    procedure csr_read_proc(
        constant avmm_addr           : in  natural;
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable readback_v          : out std_logic_vector(31 downto 0)
    );

    procedure clear_err_flags_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    );

    procedure poll_ready_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable status_v            : out std_logic_vector(31 downto 0)
    );

    procedure poll_launch_done_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable status_v            : out std_logic_vector(31 downto 0)
    );

    procedure wait_arriawriting_start_proc(
        signal csi_max10_clk         : in  std_logic;
        signal dbg_status            : in  std_logic_vector(31 downto 0);
        variable seen_v              : out boolean
    );

    procedure flash_dbg_read_proc(
        constant flash_addr          : in  natural;
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_dbg_data        : in  std_logic_vector(7 downto 0);
        variable flash_data_v        : out std_logic_vector(7 downto 0)
    );

    procedure flash_mon_read_proc(
        constant flash_addr          : in  natural;
        signal flash_mon_addr        : out std_logic_vector(23 downto 0);
        signal flash_mon_data        : in  std_logic_vector(7 downto 0);
        variable flash_data_v        : out std_logic_vector(7 downto 0)
    );

    procedure stage_pattern_words_proc(
        constant word_count          : in  natural;
        constant base_byte           : in  natural;
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    );

    procedure expect_flash_byte_proc(
        constant label_text          : in  string;
        constant flash_addr          : in  natural;
        constant exp_data            : in  std_logic_vector(7 downto 0);
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_dbg_data        : in  std_logic_vector(7 downto 0)
    );

    procedure expect_last_error_proc(
        constant exp_code            : in  std_logic_vector(7 downto 0);
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic
    );

end package feb_max10_comm_tb_pkg;

package body feb_max10_comm_tb_pkg is

    function packed_version_f(build_value : natural := DEFAULT_BUILD_CONST) return word_t is
        variable value_v : unsigned(31 downto 0);
    begin
        value_v := (others => '0');
        value_v(23 downto 16) := to_unsigned(1, 8);
        value_v(11 downto 0)  := to_unsigned(build_value, 12);
        return std_logic_vector(value_v);
    end function packed_version_f;

    function pack_word_f(byte0 : natural; byte1 : natural; byte2 : natural; byte3 : natural) return word_t is
        variable value_v : word_t;
    begin
        value_v(7 downto 0)    := std_logic_vector(to_unsigned(byte0 mod 256, 8));
        value_v(15 downto 8)   := std_logic_vector(to_unsigned(byte1 mod 256, 8));
        value_v(23 downto 16)  := std_logic_vector(to_unsigned(byte2 mod 256, 8));
        value_v(31 downto 24)  := std_logic_vector(to_unsigned(byte3 mod 256, 8));
        return value_v;
    end function pack_word_f;

    function pattern_word_f(base_byte : natural; word_index : natural) return word_t is
        constant byte_offset_const : natural := word_index * 4;
    begin
        return pack_word_f(
            base_byte + byte_offset_const,
            base_byte + byte_offset_const + 1,
            base_byte + byte_offset_const + 2,
            base_byte + byte_offset_const + 3
        );
    end function pattern_word_f;

    function pattern_byte_f(base_byte : natural; byte_index : natural) return byte_t is
    begin
        return std_logic_vector(to_unsigned((base_byte + byte_index) mod 256, 8));
    end function pattern_byte_f;

    procedure csr_idle_proc(
        signal avs_csr_address   : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read      : out std_logic;
        signal avs_csr_write     : out std_logic;
        signal avs_csr_writedata : out std_logic_vector(31 downto 0)
    ) is
    begin
        avs_csr_address          <= (others => '0');
        avs_csr_read             <= '0';
        avs_csr_write            <= '0';
        avs_csr_writedata        <= (others => '0');
    end procedure csr_idle_proc;

    procedure clear_injections_proc(
        signal inj_hold_arriawriting : out std_logic;
        signal inj_force_timeout     : out std_logic;
        signal inj_force_crcerror    : out std_logic;
        signal inj_force_nstatus_low : out std_logic
    ) is
    begin
        inj_hold_arriawriting    <= '0';
        inj_force_timeout        <= '0';
        inj_force_crcerror       <= '0';
        inj_force_nstatus_low    <= '0';
    end procedure clear_injections_proc;

    procedure apply_reset_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_write         : out std_logic;
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_mon_addr        : out std_logic_vector(23 downto 0);
        signal inj_hold_arriawriting : out std_logic;
        signal inj_force_timeout     : out std_logic;
        signal inj_force_crcerror    : out std_logic;
        signal inj_force_nstatus_low : out std_logic;
        signal rsi_csr_reset         : out std_logic;
        signal rsi_link_reset        : out std_logic;
        signal rsi_max10_reset_n     : out std_logic;
        signal csi_csr_clk           : in  std_logic;
        signal csi_max10_clk         : in  std_logic
    ) is
    begin
        csr_idle_proc(avs_csr_address, avs_csr_read, avs_csr_write, avs_csr_writedata);
        clear_injections_proc(inj_hold_arriawriting, inj_force_timeout, inj_force_crcerror, inj_force_nstatus_low);
        flash_dbg_addr           <= (others => '0');
        flash_mon_addr           <= (others => '0');
        rsi_csr_reset            <= '1';
        rsi_link_reset           <= '1';
        rsi_max10_reset_n        <= '0';
        for idx in 0 to 7 loop
            wait until rising_edge(csi_max10_clk);
        end loop;
        rsi_csr_reset            <= '0';
        rsi_link_reset           <= '0';
        rsi_max10_reset_n        <= '1';
        for idx in 0 to 3 loop
            wait until rising_edge(csi_csr_clk);
        end loop;
    end procedure apply_reset_proc;

    procedure csr_write_proc(
        constant avmm_addr           : in  natural;
        constant avmm_data           : in  std_logic_vector(31 downto 0);
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    ) is
    begin
        avs_csr_address             <= std_logic_vector(to_unsigned(avmm_addr, CSR_ADDR_W_CONST));
        avs_csr_writedata           <= avmm_data;
        avs_csr_write               <= '1';
        wait until rising_edge(csi_csr_clk);
        avs_csr_write               <= '0';
        wait until rising_edge(csi_csr_clk);
    end procedure csr_write_proc;

    procedure csr_read_proc(
        constant avmm_addr           : in  natural;
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable readback_v          : out std_logic_vector(31 downto 0)
    ) is
    begin
        avs_csr_address             <= std_logic_vector(to_unsigned(avmm_addr, CSR_ADDR_W_CONST));
        avs_csr_read                <= '1';
        wait until rising_edge(csi_csr_clk);
        while avs_csr_readdatavalid /= '1' loop
            wait until rising_edge(csi_csr_clk);
        end loop;
        readback_v                  := avs_csr_readdata;
        avs_csr_read                <= '0';
        wait until rising_edge(csi_csr_clk);
    end procedure csr_read_proc;

    procedure clear_err_flags_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    ) is
    begin
        csr_write_proc(REG_ERR_FLAGS_CONST, x"FFFF_FFFF", avs_csr_address, avs_csr_writedata, avs_csr_write, csi_csr_clk);
    end procedure clear_err_flags_proc;

    procedure poll_ready_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable status_v            : out std_logic_vector(31 downto 0)
    ) is
    begin
        for poll_idx in 0 to 3999 loop
            csr_read_proc(REG_STATUS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
            if status_v(0) = '1' and status_v(3) = '0' then
                return;
            end if;
            for wait_idx in 0 to 9 loop
                wait until rising_edge(csi_csr_clk);
            end loop;
        end loop;
        assert false report "poll_ready timeout" severity failure;
    end procedure poll_ready_proc;

    procedure poll_launch_done_proc(
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic;
        variable status_v            : out std_logic_vector(31 downto 0)
    ) is
        variable seen_busy_v         : boolean;
    begin
        seen_busy_v                  := false;
        for poll_idx in 0 to POLL_LAUNCH_DONE_MAX_POLLS_CONST - 1 loop
            csr_read_proc(REG_PROG_STATUS_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, status_v);
            if status_v(1) = '1' then
                seen_busy_v := true;
            end if;
            if seen_busy_v and status_v(1) = '0' and status_v(7) = '1' then
                return;
            end if;
            for wait_idx in 0 to 9 loop
                wait until rising_edge(csi_csr_clk);
            end loop;
        end loop;
        assert false report "poll_launch_done timeout" severity failure;
    end procedure poll_launch_done_proc;

    procedure wait_arriawriting_start_proc(
        signal csi_max10_clk         : in  std_logic;
        signal dbg_status            : in  std_logic_vector(31 downto 0);
        variable seen_v              : out boolean
    ) is
    begin
        seen_v                       := false;
        for poll_idx in 0 to 3999 loop
            wait until rising_edge(csi_max10_clk);
            if dbg_status(0) = '1' then
                seen_v := true;
                return;
            end if;
        end loop;
    end procedure wait_arriawriting_start_proc;

    procedure flash_dbg_read_proc(
        constant flash_addr          : in  natural;
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_dbg_data        : in  std_logic_vector(7 downto 0);
        variable flash_data_v        : out std_logic_vector(7 downto 0)
    ) is
    begin
        flash_dbg_addr               <= std_logic_vector(to_unsigned(flash_addr, 24));
        wait for 1 ns;
        flash_data_v                 := flash_dbg_data;
    end procedure flash_dbg_read_proc;

    procedure flash_mon_read_proc(
        constant flash_addr          : in  natural;
        signal flash_mon_addr        : out std_logic_vector(23 downto 0);
        signal flash_mon_data        : in  std_logic_vector(7 downto 0);
        variable flash_data_v        : out std_logic_vector(7 downto 0)
    ) is
    begin
        flash_mon_addr               <= std_logic_vector(to_unsigned(flash_addr, 24));
        wait for 1 ns;
        flash_data_v                 := flash_mon_data;
    end procedure flash_mon_read_proc;

    procedure stage_pattern_words_proc(
        constant word_count          : in  natural;
        constant base_byte           : in  natural;
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_writedata     : out std_logic_vector(31 downto 0);
        signal avs_csr_write         : out std_logic;
        signal csi_csr_clk           : in  std_logic
    ) is
    begin
        for word_idx in 0 to word_count - 1 loop
            csr_write_proc(
                REG_PAGE_BASE_CONST + word_idx,
                pattern_word_f(base_byte, word_idx),
                avs_csr_address,
                avs_csr_writedata,
                avs_csr_write,
                csi_csr_clk
            );
        end loop;
    end procedure stage_pattern_words_proc;

    procedure expect_flash_byte_proc(
        constant label_text          : in  string;
        constant flash_addr          : in  natural;
        constant exp_data            : in  std_logic_vector(7 downto 0);
        signal flash_dbg_addr        : out std_logic_vector(23 downto 0);
        signal flash_dbg_data        : in  std_logic_vector(7 downto 0)
    ) is
        variable got_data_v          : std_logic_vector(7 downto 0);
    begin
        flash_dbg_read_proc(flash_addr, flash_dbg_addr, flash_dbg_data, got_data_v);
        assert got_data_v = exp_data
            report label_text & ": flash byte mismatch at 0x" & to_hstring(std_logic_vector(to_unsigned(flash_addr, 24))) &
                   " expected=0x" & to_hstring(exp_data) & " got=0x" & to_hstring(got_data_v)
            severity failure;
    end procedure expect_flash_byte_proc;

    procedure expect_last_error_proc(
        constant exp_code            : in  std_logic_vector(7 downto 0);
        signal avs_csr_address       : out std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
        signal avs_csr_read          : out std_logic;
        signal avs_csr_readdata      : in  std_logic_vector(31 downto 0);
        signal avs_csr_readdatavalid : in  std_logic;
        signal csi_csr_clk           : in  std_logic
    ) is
        variable readback_v          : std_logic_vector(31 downto 0);
    begin
        csr_read_proc(REG_LAST_ERROR_CONST, avs_csr_address, avs_csr_read, avs_csr_readdata, avs_csr_readdatavalid, csi_csr_clk, readback_v);
        assert readback_v(7 downto 0) = exp_code
            report "last_error mismatch expected=0x" & to_hstring(exp_code) &
                   " got=0x" & to_hstring(readback_v(7 downto 0))
            severity failure;
    end procedure expect_last_error_proc;

end package body feb_max10_comm_tb_pkg;
