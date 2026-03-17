library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dcfifo_40x128 is
    port (
        aclr                    : in    std_logic;
        wrclk                   : in    std_logic;
        wrreq                   : in    std_logic;
        data                    : in    std_logic_vector(39 downto 0);
        wrfull                  : out   std_logic;
        rdclk                   : in    std_logic;
        rdreq                   : in    std_logic;
        q                       : out   std_logic_vector(39 downto 0);
        rdempty                 : out   std_logic
    );
end entity dcfifo_40x128;

architecture rtl of dcfifo_40x128 is
begin

    u_fifo : dcfifo
        generic map (
            intended_device_family => "Arria V",
            lpm_numwords           => 128,
            lpm_showahead          => "ON",
            lpm_type               => "dcfifo",
            lpm_width              => 40,
            lpm_widthu             => 7,
            overflow_checking      => "ON",
            underflow_checking     => "ON",
            use_eab                => "ON"
        )
        port map (
            aclr                   => aclr,
            data                   => data,
            rdclk                  => rdclk,
            rdreq                  => rdreq,
            wrclk                  => wrclk,
            wrreq                  => wrreq,
            q                      => q,
            rdempty                => rdempty,
            rdfull                 => open,
            wrempty                => open,
            wrfull                 => wrfull
        );

end architecture rtl;
