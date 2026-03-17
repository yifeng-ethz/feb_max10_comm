library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity feb_max10_comm_syn_top is
    port (
        csr_clk                 : in    std_logic;
        link_clk                : in    std_logic;
        reset_n                 : in    std_logic;
        probe_out               : out   std_logic_vector(31 downto 0)
    );
end entity feb_max10_comm_syn_top;

architecture rtl of feb_max10_comm_syn_top is

    constant CSR_ADDR_W_CONST          : natural := 10;
    constant BURSTCOUNT_W_CONST        : natural := 9;
    constant CSR_WO_STATUS_CONST       : natural := 16#003#;
    constant CSR_WO_FLASH_ADDR_CONST   : natural := 16#007#;
    constant CSR_WO_XFER_BYTES_CONST   : natural := 16#008#;
    constant CSR_WO_PROG_CTRL_CONST    : natural := 16#009#;
    constant CSR_WO_PROG_STATUS_CONST  : natural := 16#00A#;
    constant CSR_WO_LAST_ERROR_CONST   : natural := 16#00E#;
    constant CSR_WO_PAGE_BASE_CONST    : natural := 16#020#;

    signal csr_reset                   : std_logic;
    signal link_reset                  : std_logic;

    signal avs_csr_address             : std_logic_vector(CSR_ADDR_W_CONST-1 downto 0);
    signal avs_csr_read                : std_logic;
    signal avs_csr_write               : std_logic;
    signal avs_csr_writedata           : std_logic_vector(31 downto 0);
    signal avs_csr_readdata            : std_logic_vector(31 downto 0);
    signal avs_csr_readdatavalid       : std_logic;
    signal avs_csr_waitrequest         : std_logic;
    signal avs_csr_burstcount          : std_logic_vector(BURSTCOUNT_W_CONST-1 downto 0);

    signal spi_csn                     : std_logic;
    signal spi_clk                     : std_logic;
    signal spi_mosi_in                 : std_logic;
    signal spi_mosi_out                : std_logic;
    signal spi_mosi_oe                 : std_logic;
    signal spi_miso_in                 : std_logic;
    signal spi_miso_out                : std_logic;
    signal spi_miso_oe                 : std_logic;
    signal spi_d1_in                   : std_logic;
    signal spi_d1_out                  : std_logic;
    signal spi_d1_oe                   : std_logic;
    signal spi_d2_in                   : std_logic;
    signal spi_d2_out                  : std_logic;
    signal spi_d2_oe                   : std_logic;
    signal spi_d3_in                   : std_logic;
    signal spi_d3_out                  : std_logic;
    signal spi_d3_oe                   : std_logic;

    signal diag_summary                : std_logic_vector(31 downto 0);
    signal diag_err_flags              : std_logic_vector(31 downto 0);
    signal diag_last_error             : std_logic_vector(31 downto 0);
    signal diag_max10_stat             : std_logic_vector(31 downto 0);
    signal diag_max10_count            : std_logic_vector(31 downto 0);

    signal flash_seed                  : unsigned(23 downto 0);
    signal csr_cycle                   : unsigned(31 downto 0);
    signal link_cycle                  : unsigned(15 downto 0);
    signal stim_step                   : natural range 0 to 71;
    signal spi_feedback                : std_logic_vector(7 downto 0);

begin

    csr_reset                          <= not reset_n;
    link_reset                         <= not reset_n;
    avs_csr_burstcount                 <= std_logic_vector(to_unsigned(1, BURSTCOUNT_W_CONST));
    probe_out(7 downto 0)              <= diag_summary(7 downto 0);
    probe_out(15 downto 8)             <= diag_err_flags(7 downto 0)
                                          xor diag_max10_stat(7 downto 0);
    probe_out(23 downto 16)            <= diag_last_error(7 downto 0)
                                          xor diag_max10_count(7 downto 0);
    probe_out(31 downto 24)            <= avs_csr_readdata(7 downto 0);

    proc_csr_stimulus : process (csr_clk, csr_reset)
        variable page_index_v          : natural range 0 to 63;
        variable write_data_v          : std_logic_vector(31 downto 0);
    begin
        if csr_reset = '1' then
            avs_csr_address            <= (others => '0');
            avs_csr_read               <= '0';
            avs_csr_write              <= '0';
            avs_csr_writedata          <= (others => '0');
            flash_seed                 <= to_unsigned(16#001200#, 24);
            csr_cycle                  <= (others => '0');
            stim_step                  <= 0;
        elsif rising_edge(csr_clk) then
            csr_cycle                  <= csr_cycle + 1;
            avs_csr_read               <= '0';
            avs_csr_write              <= '0';
            avs_csr_address            <= (others => '0');
            avs_csr_writedata          <= (others => '0');

            if avs_csr_waitrequest = '0' then
                case stim_step is
                    when 0 =>
                        avs_csr_write      <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_FLASH_ADDR_CONST, CSR_ADDR_W_CONST));
                        avs_csr_writedata  <= x"00" & std_logic_vector(flash_seed);
                        stim_step          <= 1;

                    when 1 =>
                        avs_csr_write      <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_XFER_BYTES_CONST, CSR_ADDR_W_CONST));
                        avs_csr_writedata  <= x"00000100";
                        stim_step          <= 2;

                    when 2 to 65 =>
                        page_index_v       := stim_step - 2;
                        write_data_v       := std_logic_vector(resize(flash_seed, 32))
                                              xor std_logic_vector(to_unsigned(page_index_v, 32));
                        avs_csr_write      <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_PAGE_BASE_CONST + page_index_v, CSR_ADDR_W_CONST));
                        avs_csr_writedata  <= write_data_v;
                        stim_step          <= stim_step + 1;

                    when 66 =>
                        avs_csr_write      <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_PROG_CTRL_CONST, CSR_ADDR_W_CONST));
                        avs_csr_writedata  <= x"00000001";
                        stim_step          <= 67;

                    when 67 =>
                        avs_csr_read       <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_STATUS_CONST, CSR_ADDR_W_CONST));
                        stim_step          <= 68;

                    when 68 =>
                        avs_csr_read       <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_PROG_STATUS_CONST, CSR_ADDR_W_CONST));
                        stim_step          <= 69;

                    when 69 =>
                        avs_csr_read       <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_LAST_ERROR_CONST, CSR_ADDR_W_CONST));
                        stim_step          <= 70;

                    when 70 =>
                        avs_csr_write      <= '1';
                        avs_csr_address    <= std_logic_vector(to_unsigned(CSR_WO_PROG_CTRL_CONST, CSR_ADDR_W_CONST));
                        avs_csr_writedata  <= x"00000004";
                        stim_step          <= 71;

                    when others =>
                        flash_seed         <= flash_seed + to_unsigned(16#000100#, 24);
                        stim_step          <= 0;
                end case;
            end if;
        end if;
    end process;

    proc_link_feedback : process (link_clk, link_reset)
        variable feedback_bit_v        : std_logic;
    begin
        if link_reset = '1' then
            link_cycle                 <= (others => '0');
            spi_feedback               <= x"A5";
        elsif rising_edge(link_clk) then
            link_cycle                 <= link_cycle + 1;
            feedback_bit_v             := link_cycle(0)
                                          xor spi_clk
                                          xor spi_csn
                                          xor spi_mosi_out
                                          xor spi_miso_out
                                          xor spi_d1_out
                                          xor spi_d2_out
                                          xor spi_d3_out
                                          xor spi_mosi_oe
                                          xor spi_miso_oe
                                          xor spi_d1_oe
                                          xor spi_d2_oe
                                          xor spi_d3_oe;
            spi_feedback               <= spi_feedback(6 downto 0) & feedback_bit_v;
        end if;
    end process;

    spi_mosi_in                        <= spi_feedback(0);
    spi_miso_in                        <= spi_feedback(1);
    spi_d1_in                          <= spi_feedback(2);
    spi_d2_in                          <= spi_feedback(3);
    spi_d3_in                          <= spi_feedback(4);

    u_dut : entity work.feb_max10_comm
        generic map (
            CSR_ADDR_W                 => CSR_ADDR_W_CONST,
            BURSTCOUNT_W               => BURSTCOUNT_W_CONST,
            CDC_FIFO_ADDR_W            => 7,
            BOOT_HIST_AUTO_REFRESH     => 0,
            DEBUG_LEVEL                => 0,
            STATUS_POLL_LIMIT          => 50000,
            BUILD                      => 0,
            VERSION_MAJOR              => 0,
            VERSION_MINOR              => 1,
            VERSION_PATCH              => 0,
            IP_ID                      => 16#4D313050#,
            LINK_ROLE                  => "FEB"
        )
        port map (
            avs_csr_address            => avs_csr_address,
            avs_csr_read               => avs_csr_read,
            avs_csr_write              => avs_csr_write,
            avs_csr_writedata          => avs_csr_writedata,
            avs_csr_readdata           => avs_csr_readdata,
            avs_csr_readdatavalid      => avs_csr_readdatavalid,
            avs_csr_waitrequest        => avs_csr_waitrequest,
            avs_csr_burstcount         => avs_csr_burstcount,
            csi_csr_clk                => csr_clk,
            rsi_csr_reset              => csr_reset,
            csi_link_clk               => link_clk,
            rsi_link_reset             => link_reset,
            coe_max10_spi_csn          => spi_csn,
            coe_max10_spi_clk          => spi_clk,
            coe_max10_spi_mosi_in      => spi_mosi_in,
            coe_max10_spi_mosi_out     => spi_mosi_out,
            coe_max10_spi_mosi_oe      => spi_mosi_oe,
            coe_max10_spi_miso_in      => spi_miso_in,
            coe_max10_spi_miso_out     => spi_miso_out,
            coe_max10_spi_miso_oe      => spi_miso_oe,
            coe_max10_spi_d1_in        => spi_d1_in,
            coe_max10_spi_d1_out       => spi_d1_out,
            coe_max10_spi_d1_oe        => spi_d1_oe,
            coe_max10_spi_d2_in        => spi_d2_in,
            coe_max10_spi_d2_out       => spi_d2_out,
            coe_max10_spi_d2_oe        => spi_d2_oe,
            coe_max10_spi_d3_in        => spi_d3_in,
            coe_max10_spi_d3_out       => spi_d3_out,
            coe_max10_spi_d3_oe        => spi_d3_oe,
            coe_diag_summary           => diag_summary,
            coe_diag_err_flags         => diag_err_flags,
            coe_diag_last_error        => diag_last_error,
            coe_diag_max10_stat        => diag_max10_stat,
            coe_diag_max10_count       => diag_max10_count
        );

end architecture rtl;
