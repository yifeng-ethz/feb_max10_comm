library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity feb_max10_comm_model_wrapper is
    generic (
        CSR_ADDR_W      : natural := 10;
        BURSTCOUNT_W    : natural := 9;
        DEBUG_LEVEL     : natural := 1;
        BUILD           : natural := 16#123#
    );
    port (
        csi_csr_clk             : in    std_logic;
        csi_link_clk            : in    std_logic;
        csi_max10_clk           : in    std_logic;
        rsi_csr_reset           : in    std_logic;
        rsi_link_reset          : in    std_logic;
        rsi_max10_reset_n       : in    std_logic;

        avs_csr_address         : in    std_logic_vector(CSR_ADDR_W-1 downto 0);
        avs_csr_read            : in    std_logic;
        avs_csr_write           : in    std_logic;
        avs_csr_writedata       : in    std_logic_vector(31 downto 0);
        avs_csr_readdata        : out   std_logic_vector(31 downto 0);
        avs_csr_readdatavalid   : out   std_logic;
        avs_csr_waitrequest     : out   std_logic;
        avs_csr_burstcount      : in    std_logic_vector(BURSTCOUNT_W-1 downto 0);

        inj_hold_arriawriting   : in    std_logic;
        inj_force_timeout       : in    std_logic;
        inj_force_crcerror      : in    std_logic;
        inj_force_nstatus_low   : in    std_logic;

        diag_summary            : out   std_logic_vector(31 downto 0);
        diag_err_flags          : out   std_logic_vector(31 downto 0);
        diag_last_error         : out   std_logic_vector(31 downto 0);
        diag_max10_stat         : out   std_logic_vector(31 downto 0);
        diag_max10_count        : out   std_logic_vector(31 downto 0);

        mon_link_csn            : out   std_logic;
        mon_link_clk            : out   std_logic;
        mon_link_mosi           : out   std_logic;
        mon_link_miso           : out   std_logic;
        mon_link_d1             : out   std_logic;
        mon_link_d2             : out   std_logic;
        mon_link_d3             : out   std_logic;

        dbg_status              : out   std_logic_vector(31 downto 0);
        dbg_flash_w_cnt         : out   std_logic_vector(31 downto 0);
        dbg_control             : out   std_logic_vector(31 downto 0);
        dbg_addr_from_arria     : out   std_logic_vector(23 downto 0);
        dbg_arria_addr          : out   std_logic_vector(6 downto 0);
        dbg_arria_rw            : out   std_logic;
        dbg_arria_next_data     : out   std_logic;
        dbg_arria_word_from_arria : out std_logic_vector(31 downto 0);
        dbg_arria_word_en       : out   std_logic;
        dbg_arria_byte_from_arria : out std_logic_vector(7 downto 0);
        dbg_arria_byte_en       : out   std_logic;

        flash_dbg_addr          : in    std_logic_vector(23 downto 0);
        flash_dbg_data          : out   std_logic_vector(7 downto 0);
        flash_mon_addr          : in    std_logic_vector(23 downto 0);
        flash_mon_data          : out   std_logic_vector(7 downto 0);
        flash_dbg_wip           : out   std_logic;
        flash_dbg_wel           : out   std_logic
    );
end entity feb_max10_comm_model_wrapper;

architecture sim of feb_max10_comm_model_wrapper is
    constant SIM_STATUS_POLL_LIMIT_CONST : natural := 1024;

    signal coe_max10_spi_csn       : std_logic;
    signal coe_max10_spi_clk       : std_logic;
    signal coe_max10_spi_mosi_in   : std_logic;
    signal coe_max10_spi_mosi_out  : std_logic;
    signal coe_max10_spi_mosi_oe   : std_logic;
    signal coe_max10_spi_miso_in   : std_logic;
    signal coe_max10_spi_miso_out  : std_logic;
    signal coe_max10_spi_miso_oe   : std_logic;
    signal coe_max10_spi_d1_in     : std_logic;
    signal coe_max10_spi_d1_out    : std_logic;
    signal coe_max10_spi_d1_oe     : std_logic;
    signal coe_max10_spi_d2_in     : std_logic;
    signal coe_max10_spi_d2_out    : std_logic;
    signal coe_max10_spi_d2_oe     : std_logic;
    signal coe_max10_spi_d3_in     : std_logic;
    signal coe_max10_spi_d3_out    : std_logic;
    signal coe_max10_spi_d3_oe     : std_logic;

    signal link_mosi               : std_logic := 'Z';
    signal link_miso               : std_logic := 'Z';
    signal link_d1                 : std_logic := 'Z';
    signal link_d2                 : std_logic := 'Z';
    signal link_d3                 : std_logic := 'Z';

    signal flash_csn               : std_logic;
    signal flash_sck               : std_logic;
    signal flash_io0               : std_logic := 'Z';
    signal flash_io1               : std_logic := 'Z';
    signal flash_io2               : std_logic := 'Z';
    signal flash_io3               : std_logic := 'Z';

begin

    link_mosi                  <= coe_max10_spi_mosi_out when coe_max10_spi_mosi_oe = '1' else 'Z';
    link_miso                  <= coe_max10_spi_miso_out when coe_max10_spi_miso_oe = '1' else 'Z';
    link_d1                    <= coe_max10_spi_d1_out   when coe_max10_spi_d1_oe   = '1' else 'Z';
    link_d2                    <= coe_max10_spi_d2_out   when coe_max10_spi_d2_oe   = '1' else 'Z';
    link_d3                    <= coe_max10_spi_d3_out   when coe_max10_spi_d3_oe   = '1' else 'Z';

    coe_max10_spi_mosi_in      <= link_mosi;
    coe_max10_spi_miso_in      <= link_miso;
    coe_max10_spi_d1_in        <= link_d1;
    coe_max10_spi_d2_in        <= link_d2;
    coe_max10_spi_d3_in        <= link_d3;

    mon_link_csn               <= coe_max10_spi_csn;
    mon_link_clk               <= coe_max10_spi_clk;
    mon_link_mosi              <= link_mosi;
    mon_link_miso              <= link_miso;
    mon_link_d1                <= link_d1;
    mon_link_d2                <= link_d2;
    mon_link_d3                <= link_d3;

    dut : entity work.feb_max10_comm
        generic map (
            CSR_ADDR_W           => CSR_ADDR_W,
            BURSTCOUNT_W         => BURSTCOUNT_W,
            DEBUG_LEVEL          => DEBUG_LEVEL,
            STATUS_POLL_LIMIT    => SIM_STATUS_POLL_LIMIT_CONST,
            VERSION_MAJOR        => 0,
            VERSION_MINOR        => 1,
            VERSION_PATCH        => 0,
            BUILD                => BUILD
        )
        port map (
            avs_csr_address           => avs_csr_address,
            avs_csr_read              => avs_csr_read,
            avs_csr_write             => avs_csr_write,
            avs_csr_writedata         => avs_csr_writedata,
            avs_csr_readdata          => avs_csr_readdata,
            avs_csr_readdatavalid     => avs_csr_readdatavalid,
            avs_csr_waitrequest       => avs_csr_waitrequest,
            avs_csr_burstcount        => avs_csr_burstcount,
            csi_csr_clk               => csi_csr_clk,
            rsi_csr_reset             => rsi_csr_reset,
            csi_link_clk              => csi_link_clk,
            rsi_link_reset            => rsi_link_reset,
            coe_max10_spi_csn         => coe_max10_spi_csn,
            coe_max10_spi_clk         => coe_max10_spi_clk,
            coe_max10_spi_mosi_in     => coe_max10_spi_mosi_in,
            coe_max10_spi_mosi_out    => coe_max10_spi_mosi_out,
            coe_max10_spi_mosi_oe     => coe_max10_spi_mosi_oe,
            coe_max10_spi_miso_in     => coe_max10_spi_miso_in,
            coe_max10_spi_miso_out    => coe_max10_spi_miso_out,
            coe_max10_spi_miso_oe     => coe_max10_spi_miso_oe,
            coe_max10_spi_d1_in       => coe_max10_spi_d1_in,
            coe_max10_spi_d1_out      => coe_max10_spi_d1_out,
            coe_max10_spi_d1_oe       => coe_max10_spi_d1_oe,
            coe_max10_spi_d2_in       => coe_max10_spi_d2_in,
            coe_max10_spi_d2_out      => coe_max10_spi_d2_out,
            coe_max10_spi_d2_oe       => coe_max10_spi_d2_oe,
            coe_max10_spi_d3_in       => coe_max10_spi_d3_in,
            coe_max10_spi_d3_out      => coe_max10_spi_d3_out,
            coe_max10_spi_d3_oe       => coe_max10_spi_d3_oe,
            coe_diag_summary          => diag_summary,
            coe_diag_err_flags        => diag_err_flags,
            coe_diag_last_error       => diag_last_error,
            coe_diag_max10_stat       => diag_max10_stat,
            coe_diag_max10_count      => diag_max10_count
        );

    max10_chain : entity work.max10_prog_downstream_wrapper
        port map (
            csi_max10_clk             => csi_max10_clk,
            rsi_max10_reset_n         => rsi_max10_reset_n,
            spi_csn                   => coe_max10_spi_csn,
            spi_clk                   => coe_max10_spi_clk,
            spi_mosi                  => link_mosi,
            spi_miso                  => link_miso,
            spi_d1                    => link_d1,
            spi_d2                    => link_d2,
            spi_d3                    => link_d3,
            flash_csn                 => flash_csn,
            flash_sck                 => flash_sck,
            flash_io0                 => flash_io0,
            flash_io1                 => flash_io1,
            flash_io2                 => flash_io2,
            flash_io3                 => flash_io3,
            inj_hold_arriawriting     => inj_hold_arriawriting,
            inj_force_timeout         => inj_force_timeout,
            inj_force_crcerror        => inj_force_crcerror,
            inj_force_nstatus_low     => inj_force_nstatus_low,
            inj_reboot_start          => '0',
            inj_reboot_addr           => (others => '0'),
            fpga_conf_done_in         => '0',
            fpga_nstatus_in           => '1',
            dbg_status                => dbg_status,
            dbg_flash_w_cnt           => dbg_flash_w_cnt,
            dbg_control               => dbg_control,
            dbg_addr_from_arria       => dbg_addr_from_arria,
            dbg_arria_addr            => dbg_arria_addr,
            dbg_arria_rw              => dbg_arria_rw,
            dbg_arria_next_data       => dbg_arria_next_data,
            dbg_arria_word_from_arria => dbg_arria_word_from_arria,
            dbg_arria_word_en         => dbg_arria_word_en,
            dbg_arria_byte_from_arria => dbg_arria_byte_from_arria,
            dbg_arria_byte_en         => dbg_arria_byte_en,
            dbg_fpga_nconfig          => open,
            dbg_fpga_data             => open,
            dbg_fpga_clk              => open,
            dbg_fpp_crclocation       => open
        );

    flash_model : entity work.max10_prog_flash_model
        port map (
            flash_csn                 => flash_csn,
            flash_sck                 => flash_sck,
            flash_io0                 => flash_io0,
            flash_io1                 => flash_io1,
            flash_io2                 => flash_io2,
            flash_io3                 => flash_io3,
            dbg_addr                  => flash_dbg_addr,
            dbg_data                  => flash_dbg_data,
            dbg_mon_addr              => flash_mon_addr,
            dbg_mon_data              => flash_mon_data,
            dbg_wip                   => flash_dbg_wip,
            dbg_wel                   => flash_dbg_wel
        );

end architecture sim;
