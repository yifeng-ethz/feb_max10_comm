-- File name : feb_max10_comm.vhd
-- Author    : Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision  : 0.1.0 (skeleton created)
-- Date      : 20260316
-- =========
-- Description : [Top-level FEB-side MAX10 communication IP wrapper]
--
-- Function
--   Thin top-level wrapper intended for IP packaging and Qsys integration.
--   It instantiates the L3 controller, which in turn owns the L2 link layer.
--
-- ================ synthesizer configuration ==================
-- altera vhdl_input_version vhdl_2008
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;

entity feb_max10_comm is
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
end entity feb_max10_comm;

architecture rtl of feb_max10_comm is
begin

    u_controller : entity work.max10_controller
        generic map (
            CSR_ADDR_W              => CSR_ADDR_W,
            BURSTCOUNT_W            => BURSTCOUNT_W,
            CDC_FIFO_ADDR_W         => CDC_FIFO_ADDR_W,
            BOOT_HIST_AUTO_REFRESH  => BOOT_HIST_AUTO_REFRESH,
            DEBUG_LEVEL             => DEBUG_LEVEL,
            STATUS_POLL_LIMIT       => STATUS_POLL_LIMIT,
            BUILD                   => BUILD,
            VERSION_MAJOR           => VERSION_MAJOR,
            VERSION_MINOR           => VERSION_MINOR,
            VERSION_PATCH           => VERSION_PATCH,
            IP_ID                   => IP_ID,
            LINK_ROLE               => LINK_ROLE
        )
        port map (
            avs_csr_address         => avs_csr_address,
            avs_csr_read            => avs_csr_read,
            avs_csr_write           => avs_csr_write,
            avs_csr_writedata       => avs_csr_writedata,
            avs_csr_readdata        => avs_csr_readdata,
            avs_csr_readdatavalid   => avs_csr_readdatavalid,
            avs_csr_waitrequest     => avs_csr_waitrequest,
            avs_csr_burstcount      => avs_csr_burstcount,
            csi_csr_clk             => csi_csr_clk,
            rsi_csr_reset           => rsi_csr_reset,
            csi_link_clk            => csi_link_clk,
            rsi_link_reset          => rsi_link_reset,
            coe_max10_spi_csn       => coe_max10_spi_csn,
            coe_max10_spi_clk       => coe_max10_spi_clk,
            coe_max10_spi_mosi_in   => coe_max10_spi_mosi_in,
            coe_max10_spi_mosi_out  => coe_max10_spi_mosi_out,
            coe_max10_spi_mosi_oe   => coe_max10_spi_mosi_oe,
            coe_max10_spi_miso_in   => coe_max10_spi_miso_in,
            coe_max10_spi_miso_out  => coe_max10_spi_miso_out,
            coe_max10_spi_miso_oe   => coe_max10_spi_miso_oe,
            coe_max10_spi_d1_in     => coe_max10_spi_d1_in,
            coe_max10_spi_d1_out    => coe_max10_spi_d1_out,
            coe_max10_spi_d1_oe     => coe_max10_spi_d1_oe,
            coe_max10_spi_d2_in     => coe_max10_spi_d2_in,
            coe_max10_spi_d2_out    => coe_max10_spi_d2_out,
            coe_max10_spi_d2_oe     => coe_max10_spi_d2_oe,
            coe_max10_spi_d3_in     => coe_max10_spi_d3_in,
            coe_max10_spi_d3_out    => coe_max10_spi_d3_out,
            coe_max10_spi_d3_oe     => coe_max10_spi_d3_oe,
            coe_diag_summary        => coe_diag_summary,
            coe_diag_err_flags      => coe_diag_err_flags,
            coe_diag_last_error     => coe_diag_last_error,
            coe_diag_max10_stat     => coe_diag_max10_stat,
            coe_diag_max10_count    => coe_diag_max10_count
        );

end architecture rtl;
