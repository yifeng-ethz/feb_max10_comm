-- File name : max10_link.vhd
-- Author    : Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision  : 0.2.1 (wrapper around proven split-port engine)
-- Date      : 20260316
-- =========
-- Description : [FEB/MAX-side L2 custom link adapter]
--
-- Function
--   This wrapper presents the new controller-side `cmd_valid/cmd_ready`
--   handshake while delegating FEBSPI serialization to the proven
--   `max10_spi_split` engine. One accepted command maps to one legacy link
--   transaction carrying up to four bytes.
--
-- Notes
--   1) ROLE is currently informational only; only the FEB role is supported.
--   2) The wrapper intentionally does not use `next_data` because the new
--      controller issues one command per word rather than one streamed burst.
--
-- ================ synthesizer configuration ==================
-- altera vhdl_input_version vhdl_2008
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity max10_link is
    generic (
        ROLE                        : string  := "FEB";
        DEBUG_LEVEL                 : natural := 0
    );
    port (
        csi_clk                     : in    std_logic;
        rsi_reset                   : in    std_logic;

        cmd_valid                   : in    std_logic;
        cmd_ready                   : out   std_logic;
        cmd_addr                    : in    std_logic_vector(6 downto 0);
        cmd_write                   : in    std_logic;
        cmd_wdata                   : in    std_logic_vector(31 downto 0);
        cmd_numbytes                : in    std_logic_vector(8 downto 0);

        rsp_word                    : out   std_logic_vector(31 downto 0);
        rsp_word_valid              : out   std_logic;
        rsp_byte                    : out   std_logic_vector(7 downto 0);
        rsp_byte_valid              : out   std_logic;
        link_busy                   : out   std_logic;

        coe_spi_csn                 : out   std_logic;
        coe_spi_clk                 : out   std_logic;
        coe_spi_mosi_in             : in    std_logic;
        coe_spi_mosi_out            : out   std_logic;
        coe_spi_mosi_oe             : out   std_logic;
        coe_spi_miso_in             : in    std_logic;
        coe_spi_miso_out            : out   std_logic;
        coe_spi_miso_oe             : out   std_logic;
        coe_spi_d1_in               : in    std_logic;
        coe_spi_d1_out              : out   std_logic;
        coe_spi_d1_oe               : out   std_logic;
        coe_spi_d2_in               : in    std_logic;
        coe_spi_d2_out              : out   std_logic;
        coe_spi_d2_oe               : out   std_logic;
        coe_spi_d3_in               : in    std_logic;
        coe_spi_d3_out              : out   std_logic;
        coe_spi_d3_oe               : out   std_logic
    );
end entity max10_link;

architecture rtl of max10_link is

    type cmd_adapter_state_t is (
        CMD_ADAPTER_STATE_RESETTING,
        CMD_ADAPTER_STATE_IDLING,
        CMD_ADAPTER_STATE_STROBING,
        CMD_ADAPTER_STATE_WAIT_BUSY,
        CMD_ADAPTER_STATE_WAIT_DONE
    );

    signal adapter_state            : cmd_adapter_state_t := CMD_ADAPTER_STATE_RESETTING;
    signal cmd_addr_r               : std_logic_vector(6 downto 0) := (others => '0');
    signal cmd_write_r              : std_logic := '0';
    signal cmd_wdata_r              : std_logic_vector(31 downto 0) := (others => '0');
    signal cmd_numbytes_r           : std_logic_vector(8 downto 0) := (others => '0');
    signal spi_strobe               : std_logic := '0';
    signal spi_next_data            : std_logic;
    signal spi_word_from_max        : std_logic_vector(31 downto 0);
    signal spi_word_en              : std_logic;
    signal spi_byte_from_max        : std_logic_vector(7 downto 0);
    signal spi_byte_en              : std_logic;
    signal spi_busy                 : std_logic;

begin

    -- The retained split-port engine remains the FEBSPI protocol authority.
    legacy_link : entity work.max10_spi_split
        port map (
            csi_clk                 => csi_clk,
            rsi_reset_n             => not rsi_reset,
            strobe                  => spi_strobe,
            addr                    => cmd_addr_r,
            rw                      => cmd_write_r,
            data_to_max             => cmd_wdata_r,
            numbytes                => cmd_numbytes_r,
            next_data               => spi_next_data,
            word_from_max           => spi_word_from_max,
            word_en                 => spi_word_en,
            byte_from_max           => spi_byte_from_max,
            byte_en                 => spi_byte_en,
            busy                    => spi_busy,
            coe_spi_csn             => coe_spi_csn,
            coe_spi_clk             => coe_spi_clk,
            coe_spi_mosi_in         => coe_spi_mosi_in,
            coe_spi_mosi_out        => coe_spi_mosi_out,
            coe_spi_mosi_oe         => coe_spi_mosi_oe,
            coe_spi_miso_in         => coe_spi_miso_in,
            coe_spi_miso_out        => coe_spi_miso_out,
            coe_spi_miso_oe         => coe_spi_miso_oe,
            coe_spi_d1_in           => coe_spi_d1_in,
            coe_spi_d1_out          => coe_spi_d1_out,
            coe_spi_d1_oe           => coe_spi_d1_oe,
            coe_spi_d2_in           => coe_spi_d2_in,
            coe_spi_d2_out          => coe_spi_d2_out,
            coe_spi_d2_oe           => coe_spi_d2_oe,
            coe_spi_d3_in           => coe_spi_d3_in,
            coe_spi_d3_out          => coe_spi_d3_out,
            coe_spi_d3_oe           => coe_spi_d3_oe
        );

    rsp_word                        <= spi_word_from_max;
    rsp_word_valid                  <= spi_word_en;
    rsp_byte                        <= spi_byte_from_max;
    rsp_byte_valid                  <= spi_byte_en;
    cmd_ready                       <= '1' when adapter_state = CMD_ADAPTER_STATE_IDLING else '0';
    link_busy                       <= '1' when adapter_state /= CMD_ADAPTER_STATE_IDLING or spi_busy = '1' else '0';

    proc_cmd_adapter : process (csi_clk, rsi_reset)
    begin
        if rsi_reset = '1' then
            adapter_state               <= CMD_ADAPTER_STATE_RESETTING;
            cmd_addr_r                  <= (others => '0');
            cmd_write_r                 <= '0';
            cmd_wdata_r                 <= (others => '0');
            cmd_numbytes_r              <= (others => '0');
            spi_strobe                  <= '0';
        elsif rising_edge(csi_clk) then
            spi_strobe                  <= '0';

            case adapter_state is
                when CMD_ADAPTER_STATE_RESETTING =>
                    adapter_state           <= CMD_ADAPTER_STATE_IDLING;

                when CMD_ADAPTER_STATE_IDLING =>
                    if cmd_valid = '1' then
                        cmd_addr_r              <= cmd_addr;
                        cmd_write_r             <= cmd_write;
                        cmd_wdata_r             <= cmd_wdata;
                        cmd_numbytes_r          <= cmd_numbytes;
                        adapter_state           <= CMD_ADAPTER_STATE_STROBING;
                    end if;

                when CMD_ADAPTER_STATE_STROBING =>
                    spi_strobe              <= '1';
                    adapter_state           <= CMD_ADAPTER_STATE_WAIT_BUSY;

                when CMD_ADAPTER_STATE_WAIT_BUSY =>
                    if spi_busy = '1' then
                        adapter_state           <= CMD_ADAPTER_STATE_WAIT_DONE;
                    end if;

                when CMD_ADAPTER_STATE_WAIT_DONE =>
                    if spi_busy = '0' then
                        adapter_state           <= CMD_ADAPTER_STATE_IDLING;
                    end if;
            end case;
        end if;
    end process proc_cmd_adapter;

end architecture rtl;
