create_clock -name csr_clk -period 6.400 [get_ports {csr_clk}]
create_clock -name link_clk -period 20.000 [get_ports {link_clk}]
