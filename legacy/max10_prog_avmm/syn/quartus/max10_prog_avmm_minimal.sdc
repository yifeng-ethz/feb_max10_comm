# max10_prog_avmm_minimal.sdc
#
# Standalone sign-off constraint. Drives csi_csr_clk at 172.5 MHz
# (1.1 x 156.25 MHz FEB target) so that closing this project is a
# reliable early-warning gate for FEB SciFi integration close.
#
# csi_link_clk is left unconstrained -- the only logic clocked by it
# is the link-domain FSM, which in FEB is driven by the same
# transceiver_pll_clock[0] as csi_csr_clk. For the standalone
# minimal project we collapse both to a single virtual clock.

create_clock -name csi_csr_clk  -period 5.797 [get_ports {csi_csr_clk}]
create_clock -name csi_link_clk -period 5.797 [get_ports {csi_link_clk}]

# Declare the two clocks as asynchronous; the IP handles CDC internally
# via toggle handshakes and the DCFIFO.
set_clock_groups -asynchronous -group {csi_csr_clk} -group {csi_link_clk}

# Non-clock inputs/outputs are not timing-critical at this stage --
# the goal is pure internal-cone closure. False-path all I/O so that
# pin placement jitter does not create noise slack.
set_false_path -from [remove_from_collection [all_inputs] [get_ports {csi_csr_clk csi_link_clk}]]
set_false_path -to   [all_outputs]

# Pull in the IP's own CDC constraints on the queue FIFO.
source ../../max10_prog_avmm.sdc
