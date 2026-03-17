# `feb_max10_comm` RTL Plan

- status   : implemented for current FEB programming stage
- author   : Yifeng Wang (yifenwan@phys.ethz.ch)
- created  : 2026-03-16
- spec-ref : `max10_prog_avmm/SPEC.md`
- style-ref: `~/.codex/skills/rtl-writing/SKILL.md`

---

## 0. Overview

This plan defines the process ownership, record sub-partitions, and variable
scope for every file in the `feb_max10_comm` IP.

Implementation note: the RTL in this directory now matches this ownership split
for the current programming-only stage, and the associated `tb/sim` and
`tb/uvm` environments both pass on the 2026-03-16 verification closure.

Design intent: the FEB-side Arria writes CSR registers (FLASH_ADDR, XFER_BYTES,
PAGE_DATA) through AVMM, pulses START, and the L3 controller snapshots the page,
pushes it across a CDC FIFO into the link-clock domain, where the L3 master
sequences FEBSPI register writes toward MAX10 via the L2 link layer. MAX10
writes the data to SPI flash.

### Hierarchy

```
feb_max10_comm.vhd          (top wrapper, structural only)
  └── max10_controller.vhd  (L3 controller master, two clock domains)
        └── max10_link.vhd  (L2 custom SPI link layer, link_clk only)
```

### Clock Domains

| Domain     | Source            | Processes                                       |
|:-----------|:------------------|:------------------------------------------------|
| `csr_clk`  | sc_hub (~156 MHz) | proc_csr_slave, proc_stage_store, proc_cdc_pusher, proc_csr_read (comb) |
| `link_clk` | MAX10 (~50 MHz)   | proc_max_master (in max10_controller), proc_tx_engine (in max10_link) |

### CDC Boundary

| Direction    | Mechanism                          | Payload                                |
|:-------------|:-----------------------------------|:---------------------------------------|
| CSR → Link   | dcfifo (40-bit wide)               | header word + page payload words       |
| CSR → Link   | toggle handshake (launch_toggle)   | edge = new launch available in FIFO    |
| CSR → Link   | 3-stage sync (reset_sync)          | sw_reset request                       |
| Link → CSR   | toggle handshake (done_toggle)     | edge = launch completed                |
| Link → CSR   | async mirror via 3-stage sync      | debug status (max10_stat, max10_count) |

---

## 1. File: `feb_max10_comm.vhd` (Top Wrapper)

### 1.1 Purpose

Thin structural wrapper for IP packaging and Qsys integration. No logic, no
records, no processes. Only generic/port passthrough to `max10_controller`.

### 1.2 Instances

| Instance         | Entity             |
|:-----------------|:-------------------|
| `u_controller`   | `max10_controller` |

### 1.3 Processes

None.

---

## 2. File: `max10_controller.vhd` (L3 Controller Master)

### 2.0 Types and Constants

```
subtype word_t is std_logic_vector(31 downto 0);
type page_mem_array is array (0 to 63) of word_t;
```

### 2.1 Instance: `max_link`

| Instance    | Entity       |
|:------------|:-------------|
| `max_link`  | `max10_link` |

Port wiring: `max_master.runtime.cmd_*` → `max_link.cmd_*`,
`max_link.rsp_*` → local signals consumed by `proc_max_master`.

### 2.2 Instance: `u_cdc_fifo` (dcfifo, 40-bit × 2^CDC_FIFO_ADDR_W)

Internal dual-clock FIFO for CSR→link payload transfer.

- Write side: `csi_csr_clk`, driven by `proc_cdc_pusher`
- Read side: `csi_link_clk`, driven by `proc_max_master`

---

### 2.3 Proc: `proc_csr_slave`

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | sequential                                     |
| Clock      | `csi_csr_clk`                                  |
| Reset      | `rsi_csr_reset` (async high)                   |
| Owner      | `csr_slave : csr_slave_reg_t`                  |
| Reset img  | `CSR_SLAVE_RESET_CONST`                        |

Function: AVMM write/read decode. Updates config registers on write, updates
status/error from CDC feedback, implements pulse commands (PROG_CTRL),
implements sw_reset flush handshake.

#### Owner record: `csr_slave_reg_t`

```
csr_slave_reg_t
├── config : csr_slave_config_reg_t
│     ├── flash_addr              : std_logic_vector(23 downto 0)
│     ├── flash_addr_valid        : std_logic
│     ├── xfer_bytes              : unsigned(8 downto 0)    -- reset = 256
│     ├── scratch                 : word_t
│     └── sw_reset_req            : std_logic
├── status : csr_slave_status_reg_t
│     ├── ready                   : std_logic               -- reset = '1'
│     ├── busy                    : std_logic
│     ├── resetting               : std_logic
│     ├── launch_accepted         : std_logic               -- sticky
│     └── launch_done             : std_logic               -- sticky
├── error : csr_slave_error_reg_t
│     ├── err_flags               : word_t                  -- sticky RW1C
│     ├── err_count               : unsigned(31 downto 0)   -- saturating
│     └── last_error              : word_t
└── debug : csr_slave_debug_reg_t
      ├── max10_stat              : word_t
      └── max10_count             : word_t
```

#### Variables (process-local, single-cycle intermediates)

| Name               | Type                         | Purpose                              |
|:-------------------|:-----------------------------|:-------------------------------------|
| `csr_addr_v`       | `natural range 0 to 1023`   | decoded word offset                  |
| `staged_words_v`   | `natural range 0 to 64`     | contiguous valid prefix length       |
| `required_words_v` | `natural range 0 to 64`     | ceil(xfer_bytes/4)                   |
| `page_ready_v`     | `boolean`                    | staged_words >= required_words       |
| `start_reject_v`   | `boolean`                    | any rejection condition active       |
| `err_code_v`       | `std_logic_vector(7 downto 0)` | error code to latch             |

#### Responsibilities

1. Decode AVMM write to WO addresses per SPEC §4–§5.
2. On write to FLASH_ADDR: latch `config.flash_addr`, set `config.flash_addr_valid`.
3. On write to XFER_BYTES: latch `config.xfer_bytes`.
4. On write to PROG_CTRL:
   - bit 0 (start): validate preconditions → accept or reject with error.
   - bit 1 (clear_page): pulse to `proc_stage_store`.
   - bit 2 (clear_status): clear `last_error`, `launch_accepted`, `launch_done`.
   - bit 3 (clear_addr): clear `flash_addr_valid`, zero `flash_addr`.
5. On write to SCRATCH: latch `config.scratch`.
6. On write to ERR_FLAGS: RW1C clear masked bits.
7. On write to CTRL.sw_reset: assert `config.sw_reset_req`, set `status.resetting`.
8. Consume done_toggle edge from link domain: clear `status.busy`, set `launch_done`.
9. Consume debug mirror updates from link domain: update `debug.max10_stat/count`.

---

### 2.4 Proc: `proc_stage_store`

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | sequential                                     |
| Clock      | `csi_csr_clk`                                  |
| Reset      | `rsi_csr_reset` (async high)                   |
| Owner      | `stage_store : stage_store_reg_t`              |
| Reset img  | `STAGE_STORE_RESET_CONST`                      |

Function: page aperture storage with per-word valid tracking. Snapshots
launch data when START is accepted.

#### Owner record: `stage_store_reg_t`

```
stage_store_reg_t
├── page_data           : page_mem_array          -- array(0..63) of word_t
├── page_valid          : std_logic_vector(63 downto 0)  -- per-word valid mask
└── launch_page_data    : page_mem_array          -- snapshot copy for CDC push
```

#### Variables (process-local)

| Name              | Type                       | Purpose                         |
|:------------------|:---------------------------|:--------------------------------|
| `write_index_v`   | `natural range 0 to 63`   | page aperture write index       |
| `clear_page_v`    | `boolean`                  | clear pulse from proc_csr_slave |

#### Responsibilities

1. On AVMM write to PAGE_DATA[0..63] (WO 0x020..0x05F): store word, set `page_valid(index)`.
2. On clear_page pulse: zero `page_data`, clear `page_valid`.
3. On launch_accept pulse: snapshot `page_data` → `launch_page_data`.
4. Allow AVMM readback of `page_data` words.

#### Inter-process communication (inputs from `proc_csr_slave`)

- `csr_slave` write decode → page write index + writedata (shared via AVMM signals, not cross-record)
- `csr_slave` clear_page pulse → one-cycle flag
- `csr_slave` launch_accept pulse → one-cycle flag to snapshot

---

### 2.5 Proc: `proc_cdc_pusher`

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | sequential                                     |
| Clock      | `csi_csr_clk`                                  |
| Reset      | `rsi_csr_reset` (async high)                   |
| Owner      | `cdc_pusher : cdc_pusher_reg_t`                |
| Reset img  | `CDC_PUSHER_RESET_CONST`                       |

Function: after launch acceptance, pushes a header word + payload words into
the dcfifo for consumption by the link-domain `proc_max_master`.

#### Owner record: `cdc_pusher_reg_t`

```
cdc_pusher_reg_t
├── state : cdc_pusher_state_reg_t
│     ├── fsm                   : cdc_pusher_fsm_t
│     │     (RESETTING, IDLING, PUSHING_HEADER, PUSHING_PAYLOAD)
│     ├── active                : std_logic
│     ├── header_pending        : std_logic
│     ├── word_index            : natural range 0 to 63
│     ├── launch_flash_addr     : std_logic_vector(23 downto 0)
│     ├── launch_xfer_bytes     : unsigned(8 downto 0)
│     └── launch_toggle         : std_logic             -- toggle to link domain
└── debug : cdc_pusher_debug_reg_t
      ├── last_fifo_word        : std_logic_vector(39 downto 0)
      └── last_pushed_index     : natural range 0 to 63
```

#### Variables (process-local)

| Name               | Type                       | Purpose                        |
|:-------------------|:---------------------------|:-------------------------------|
| `required_words_v` | `natural range 0 to 64`   | ceil(xfer_bytes/4)             |
| `push_header_v`    | `boolean`                  | push header word this cycle    |
| `push_payload_v`   | `boolean`                  | push payload word this cycle   |

#### FIFO word format (40 bits)

| Bits      | Field      | Header word                   | Payload word                |
|:----------|:-----------|:------------------------------|:----------------------------|
| `[39:32]` | tag        | `0x01` (header marker)        | `0x00` (payload marker)     |
| `[31:0]`  | data       | `{xfer_bytes[8:0], flash_addr[22:0]}` | `page_data[word_index]` |

#### Responsibilities

1. On launch_accept: latch flash_addr + xfer_bytes, start PUSHING_HEADER.
2. Push header word into dcfifo wrreq.
3. Push payload words `[0..required_words-1]` from `stage_store.launch_page_data`.
4. After last payload word: toggle `launch_toggle`, return to IDLING.
5. On sw_reset while IDLING: immediate reset. While active: complete current push, then reset.

---

### 2.6 Proc: `proc_max_master`

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | sequential                                     |
| Clock      | `csi_link_clk`                                 |
| Reset      | `rsi_link_reset` (async high)                  |
| Owner      | `max_master : max_master_reg_t`                |
| Reset img  | `MAX_MASTER_RESET_CONST`                       |

Function: L3 transaction engine in the link domain. Pops header + payload from
dcfifo, sequences FEBSPI register writes/reads toward `max10_link`, polls
MAX10 programming status, reports completion back to CSR domain.

#### Owner record: `max_master_reg_t`

```
max_master_reg_t
├── config : max_master_config_reg_t
│     ├── launch_toggle_sync        : std_logic_vector(2 downto 0)   -- CDC sync chain
│     ├── reset_sync                : std_logic_vector(2 downto 0)   -- CDC sync chain
│     ├── launch_flash_addr         : std_logic_vector(23 downto 0)  -- from FIFO header
│     └── launch_xfer_bytes         : unsigned(8 downto 0)           -- from FIFO header
├── state : max_master_state_t
│     (RESETTING,
│      IDLING,
│      DRAINING_FIFO,
│      PUMPING_WFIFO,
│      WRITING_ADDR,
│      WAITING_ADDR,
│      WRITING_CTRL_START,
│      WAITING_CTRL_START,
│      POLLING_STATUS,
│      WAITING_STATUS_WORD,
│      CHECKING_STATUS,
│      WRITING_CTRL_STOP,
│      WAITING_CTRL_STOP,
│      READING_COUNT,
│      WAITING_COUNT_WORD,
│      NOTIFYING)
├── runtime : max_master_runtime_reg_t
│     ├── done_toggle               : std_logic                      -- CDC back to csr
│     ├── cmd_valid                 : std_logic                      -- to max10_link
│     ├── cmd_addr                  : std_logic_vector(6 downto 0)   -- FEBSPI address
│     ├── cmd_write                 : std_logic                      -- '1'=write, '0'=read
│     ├── cmd_wdata                 : word_t                         -- write payload
│     ├── cmd_numbytes              : std_logic_vector(8 downto 0)   -- byte count for link
│     ├── payload_words_total       : natural range 0 to 64
│     ├── payload_words_sent        : natural range 0 to 64
│     ├── fifo_word_index           : natural range 0 to 64          -- dcfifo pop position
│     ├── status_poll_count         : natural range 0 to 65535
│     ├── txn_timeout_count         : natural range 0 to 65535
│     └── flash_busy                : std_logic
└── debug : max_master_debug_reg_t
      ├── max10_stat                : word_t
      ├── max10_count               : word_t
      ├── err_flags                 : word_t
      └── err_code                  : std_logic_vector(7 downto 0)
```

#### State machine flow

```
RESETTING
    → IDLING                     (after soft-reset cleanup)

IDLING
    → DRAINING_FIFO              (launch_toggle edge detected, start popping dcfifo)

DRAINING_FIFO
    → PUMPING_WFIFO              (header parsed, begin streaming payload bytes to WFIFO)

PUMPING_WFIFO
    → WRITING_ADDR               (all payload bytes sent to FEBSPI_ADDR_PROGRAMMING_WFIFO)

WRITING_ADDR
    → WAITING_ADDR               (issue link cmd: write flash_addr to FEBSPI_ADDR_PROGRAMMING_ADDR)

WAITING_ADDR
    → WRITING_CTRL_START         (link cmd accepted)

WRITING_CTRL_START
    → WAITING_CTRL_START         (issue link cmd: write 1 to FEBSPI_ADDR_PROGRAMMING_CTRL)

WAITING_CTRL_START
    → POLLING_STATUS             (link cmd accepted)

POLLING_STATUS
    → WAITING_STATUS_WORD        (issue link cmd: read FEBSPI_ADDR_PROGRAMMING_STATUS)

WAITING_STATUS_WORD
    → CHECKING_STATUS            (rsp_word_valid from link)

CHECKING_STATUS
    → POLLING_STATUS             (MAX10 still busy, poll again)
    → WRITING_CTRL_STOP          (MAX10 done or error)

WRITING_CTRL_STOP
    → WAITING_CTRL_STOP          (issue link cmd: write 0 to FEBSPI_ADDR_PROGRAMMING_CTRL)

WAITING_CTRL_STOP
    → READING_COUNT              (link cmd accepted)

READING_COUNT
    → WAITING_COUNT_WORD         (issue link cmd: read FEBSPI_ADDR_PROGRAMMING_COUNT)

WAITING_COUNT_WORD
    → NOTIFYING                  (rsp_word_valid, latch count)

NOTIFYING
    → IDLING                     (toggle done_toggle, clear runtime)
```

#### Variables (process-local)

| Name               | Type                       | Purpose                          |
|:-------------------|:---------------------------|:---------------------------------|
| `soft_reset_req_v` | `boolean`                  | CDC-synced sw_reset edge         |
| `must_drain_v`     | `boolean`                  | in-flight work needs safe stop   |
| `required_words_v` | `natural range 0 to 64`   | ceil(xfer_bytes/4)               |
| `fifo_rdata_v`     | `std_logic_vector(39 downto 0)` | dcfifo read word            |

#### FEBSPI address constants

| Name                                    | Value  | Direction | Purpose               |
|:----------------------------------------|:-------|:----------|:----------------------|
| `FEBSPI_ADDR_PROGRAMMING_STATUS_CONST`  | `0x10` | read      | MAX10 prog status     |
| `FEBSPI_ADDR_PROGRAMMING_COUNT_CONST`   | `0x11` | read      | MAX10 prog count      |
| `FEBSPI_ADDR_PROGRAMMING_CTRL_CONST`    | `0x12` | write     | MAX10 page-program trigger |
| `FEBSPI_ADDR_PROGRAMMING_ADDR_CONST`    | `0x13` | write     | flash byte address    |
| `FEBSPI_ADDR_PROGRAMMING_WFIFO_CONST`   | `0x14` | write     | programming payload   |

#### Responsibilities

1. Synchronize `launch_toggle` and `reset_sync` from CSR domain (3-stage).
2. On launch_toggle edge: pop dcfifo header, parse flash_addr + xfer_bytes.
3. Pop dcfifo payload words, stream bytes to MAX10 WFIFO via link cmd.
4. After payload complete: write flash_addr to PROGRAMMING_ADDR.
5. Write 1 to PROGRAMMING_CTRL (start).
6. Poll PROGRAMMING_STATUS until MAX10 done (bit 0 = arria_writing, bit 1 = spi_busy).
7. Write 0 to PROGRAMMING_CTRL (stop).
8. Read PROGRAMMING_COUNT for debug.
9. Toggle `done_toggle` back to CSR domain.
10. On sw_reset: if idle, immediate reset. If in-flight after CTRL_START issued, drain to CTRL_STOP before reset.

---

### 2.7 Proc: `proc_csr_read` (combinational)

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | combinational                                  |
| Sensitivity| `process(all)`                                 |
| Owner      | none (read-only mux)                           |

Function: pure AVMM read multiplexer. Maps `csr_slave`, `stage_store`,
and derived status into `avs_csr_readdata`.

#### Variables (process-local)

| Name              | Type     | Purpose              |
|:------------------|:---------|:---------------------|
| `csr_readdata_v`  | `word_t` | readdata accumulator |

#### Read mux map (from SPEC §4–§5)

| WO Range       | Source                                                         |
|:---------------|:---------------------------------------------------------------|
| `0x000`        | IP_ID generic                                                  |
| `0x001`        | VERSION packed from generics                                   |
| `0x002`        | CTRL (sw_reset readback)                                       |
| `0x003`        | STATUS from `csr_slave.status`                                 |
| `0x004`        | ERR_FLAGS from `csr_slave.error.err_flags`                     |
| `0x005`        | ERR_COUNT from `csr_slave.error.err_count`                     |
| `0x006`        | SCRATCH from `csr_slave.config.scratch`                        |
| `0x007`        | FLASH_ADDR from `csr_slave.config.flash_addr`                  |
| `0x008`        | XFER_BYTES from `csr_slave.config.xfer_bytes`                  |
| `0x009`        | PROG_CTRL reads as 0 (write-only)                              |
| `0x00A`        | PROG_STATUS (composed from status + debug fields)              |
| `0x00B`        | STAGED_WORDS (contiguous valid prefix count, derived)          |
| `0x00C`        | MAX10_STAT from `csr_slave.debug.max10_stat`                   |
| `0x00D`        | MAX10_COUNT from `csr_slave.debug.max10_count`                 |
| `0x00E`        | LAST_ERROR from `csr_slave.error.last_error`                   |
| `0x020..0x05F` | PAGE_DATA from `stage_store.page_data`                         |
| others         | `0x00000000`                                                   |

#### STAGED_WORDS derivation (combinational)

Count contiguous '1' bits in `stage_store.page_valid` starting from bit 0.
This is a priority-encoder style scan. Output range 0..64.

#### PROG_STATUS composition (combinational)

| Bit      | Source                                                  |
|:---------|:--------------------------------------------------------|
| `[0]`    | `not csr_slave.status.busy and csr_slave.status.ready`  |
| `[1]`    | `csr_slave.status.busy`                                 |
| `[2]`    | page_ready (staged_words >= required_words)             |
| `[3]`    | `csr_slave.config.flash_addr_valid`                     |
| `[4]`    | xfer_bytes in 1..256                                    |
| `[5]`    | `cdc_pusher.state.active`                               |
| `[6]`    | `csr_slave.status.launch_accepted`                      |
| `[7]`    | `csr_slave.status.launch_done`                          |
| `[15:8]` | MAX10 raw status bits (from debug mirror)               |
| `[23:16]`| engine state encoding (FSM enum to slv)                 |

---

### 2.8 Concurrent Assignments (max10_controller)

```vhdl
avs_csr_waitrequest             <= '0';
avs_csr_readdatavalid           <= avs_csr_read;
-- avs_csr_readdata driven by proc_csr_read

coe_diag_summary                <= <composed from status>;
coe_diag_err_flags              <= csr_slave.error.err_flags;
coe_diag_last_error             <= csr_slave.error.last_error;
coe_diag_max10_stat             <= csr_slave.debug.max10_stat;
coe_diag_max10_count            <= csr_slave.debug.max10_count;
```

---

### 2.9 Inter-Process Communication Summary (max10_controller)

| From              | To                | Signal / Mechanism           | Domain    |
|:------------------|:------------------|:-----------------------------|:----------|
| `proc_csr_slave`  | `proc_stage_store`| AVMM write signals (shared)  | csr_clk   |
| `proc_csr_slave`  | `proc_stage_store`| clear_page pulse, launch pulse| csr_clk  |
| `proc_csr_slave`  | `proc_cdc_pusher` | launch_accept pulse          | csr_clk   |
| `proc_stage_store`| `proc_cdc_pusher` | `stage_store.launch_page_data` (read) | csr_clk |
| `proc_cdc_pusher` | `proc_max_master` | dcfifo (write→read)          | CDC       |
| `proc_cdc_pusher` | `proc_max_master` | `launch_toggle` (3-stage sync)| CDC      |
| `proc_max_master` | `proc_csr_slave`  | `done_toggle` (3-stage sync)  | CDC      |
| `proc_max_master` | `proc_csr_slave`  | debug mirrors (3-stage sync)  | CDC      |
| `proc_max_master` | `max10_link`      | cmd_valid/addr/write/wdata/numbytes | link_clk |
| `max10_link`      | `proc_max_master` | rsp_word/valid, rsp_byte/valid, busy | link_clk |

---

## 3. File: `max10_link.vhd` (L2 Custom SPI Link Layer)

### 3.0 Purpose

Accepts abstract link commands (address, direction, data, byte count) from the
L3 controller and serializes/deserializes them onto the custom 4+1 bit
split-port FEBSPI bus toward MAX10. This is a direct record-based
reimplementation of the proven `max10_spi_split.vhd` protocol.

### 3.1 Entity Interface

| Group         | Signals                                                |
|:--------------|:-------------------------------------------------------|
| Clock/Reset   | `csi_clk`, `rsi_reset`                                |
| Command in    | `cmd_valid`, `cmd_ready`, `cmd_addr[6:0]`, `cmd_write`, `cmd_wdata[31:0]`, `cmd_numbytes[8:0]` |
| Response out  | `rsp_word[31:0]`, `rsp_word_valid`, `rsp_byte[7:0]`, `rsp_byte_valid`, `link_busy` |
| SPI conduit   | `coe_spi_csn`, `coe_spi_clk`, `coe_spi_{mosi,miso,d1,d2,d3}_{in,out,oe}` |

---

### 3.2 Proc: `proc_tx_engine`

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | sequential                                     |
| Clock      | `csi_clk`                                      |
| Reset      | `rsi_reset` (async high)                       |
| Owner      | `tx_engine : tx_engine_reg_t`                  |
| Reset img  | `TX_ENGINE_RESET_CONST`                        |
| Soft reset | `tx_engine_soft_reset_func(tx_engine)`         |

Function: nibble-serial FEBSPI master. Serializes address phase, write data
phase, bus turnaround, and read data phase on the split-port lanes.

#### Owner record: `tx_engine_reg_t`

```
tx_engine_reg_t
├── config : tx_engine_config_reg_t
│     ├── cmd_addr              : std_logic_vector(6 downto 0)   -- latched command address
│     ├── cmd_write             : std_logic                      -- latched R/W direction
│     ├── cmd_wdata             : word_t                         -- latched write data word
│     └── cmd_numbytes          : unsigned(8 downto 0)           -- latched byte count
├── state : tx_engine_state_t
│     (RESETTING,
│      IDLING,
│      ADDRESSING,
│      WRITING_DATA,
│      WAITING_TURN,
│      READING_DATA)
├── runtime : tx_engine_runtime_reg_t
│     ├── busy                  : std_logic
│     ├── cmd_ready             : std_logic
│     ├── toggle                : std_logic                      -- half-clock divider
│     ├── nibble_count          : natural range 0 to 511
│     ├── addr_shift            : std_logic_vector(7 downto 0)   -- {rw, addr[6:0]} shift reg
│     ├── data_shift            : word_t                         -- TX shift register
│     ├── data_read_shift       : word_t                         -- RX shift register
│     ├── have_read             : std_logic                      -- read nibble captured
│     ├── rsp_word_valid        : std_logic                      -- one-cycle pulse
│     └── rsp_byte_valid        : std_logic                      -- one-cycle pulse
├── spi_out : tx_engine_spi_out_reg_t
│     ├── csn                   : std_logic                      -- reset = '1'
│     ├── clk                   : std_logic                      -- reset = '0'
│     ├── mosi_out              : std_logic
│     ├── mosi_oe               : std_logic
│     ├── miso_out              : std_logic
│     ├── miso_oe               : std_logic
│     ├── d1_out                : std_logic
│     ├── d1_oe                 : std_logic
│     ├── d2_out                : std_logic
│     ├── d2_oe                 : std_logic
│     ├── d3_out                : std_logic
│     └── d3_oe                 : std_logic
└── debug : tx_engine_debug_reg_t
      ├── last_rsp_word         : word_t
      ├── last_rsp_byte         : std_logic_vector(7 downto 0)
      ├── sampled_mosi          : std_logic
      ├── sampled_miso          : std_logic
      ├── sampled_d1            : std_logic
      ├── sampled_d2            : std_logic
      └── sampled_d3            : std_logic
```

#### Variables (process-local)

| Name              | Type      | Purpose                            |
|:------------------|:----------|:-----------------------------------|
| `accept_cmd_v`    | `boolean` | command acceptance this cycle       |
| `emit_byte_v`     | `boolean` | byte boundary reached              |
| `emit_word_v`     | `boolean` | word boundary reached              |

#### State machine flow

```
RESETTING
    → IDLING                 (soft reset complete, cmd_ready = '1')

IDLING
    → ADDRESSING             (cmd_valid = '1': latch cmd, load addr_shift, assert csn='0')

ADDRESSING
    → WRITING_DATA           (2 nibbles sent, cmd_write = '1': load data_shift)
    → WAITING_TURN           (2 nibbles sent, cmd_write = '0': bus turnaround)

WRITING_DATA
    → IDLING                 (all bytes sent: deassert csn, cmd_ready = '1')

WAITING_TURN
    → READING_DATA           (3 turnaround cycles elapsed)

READING_DATA
    → IDLING                 (all bytes read: deassert csn, cmd_ready = '1')
```

#### SPI protocol timing (from proven max10_spi_split)

- `toggle` alternates 0/1 each clock cycle, giving SPI_CLK = link_clk/2.
- `toggle = '0'`: setup phase — drive data lanes, shift register, increment nibble_count.
- `toggle = '1'`: capture phase — assert SPI_CLK high, sample input lanes on reads.
- Address phase: 2 nibbles (8 bits: {rw, addr[6:0]}) on {d3, d2, d1, mosi}.
- Write phase: data nibbles on {d3, d2, d1, mosi}, OE active, MSB-first per nibble.
- Read phase: sample {d3, d2, d1, mosi} from MAX10 side, OE inactive.
- Byte boundary: every 2 nibbles → `rsp_byte_valid` pulse.
- Word boundary: every 8 nibbles → `rsp_word_valid` pulse.

---

### 3.3 Proc: `proc_tx_engine_output` (combinational)

| Property   | Value                                          |
|:-----------|:-----------------------------------------------|
| Type       | combinational                                  |
| Sensitivity| `process(all)`                                 |
| Owner      | none (output wiring only)                      |

Function: wires registered record fields to entity output ports.

#### Assignments

```vhdl
cmd_ready           <= tx_engine.runtime.cmd_ready;
link_busy           <= tx_engine.runtime.busy;
rsp_word            <= tx_engine.debug.last_rsp_word;
rsp_word_valid      <= tx_engine.runtime.rsp_word_valid;
rsp_byte            <= tx_engine.debug.last_rsp_byte;
rsp_byte_valid      <= tx_engine.runtime.rsp_byte_valid;

coe_spi_csn         <= tx_engine.spi_out.csn;
coe_spi_clk         <= tx_engine.spi_out.clk;
coe_spi_mosi_out    <= tx_engine.spi_out.mosi_out;
coe_spi_mosi_oe     <= tx_engine.spi_out.mosi_oe;
coe_spi_miso_out    <= tx_engine.spi_out.miso_out;
coe_spi_miso_oe     <= tx_engine.spi_out.miso_oe;
coe_spi_d1_out      <= tx_engine.spi_out.d1_out;
coe_spi_d1_oe       <= tx_engine.spi_out.d1_oe;
coe_spi_d2_out      <= tx_engine.spi_out.d2_out;
coe_spi_d2_oe       <= tx_engine.spi_out.d2_oe;
coe_spi_d3_out      <= tx_engine.spi_out.d3_out;
coe_spi_d3_oe       <= tx_engine.spi_out.d3_oe;
```

---

## 4. CSR Address Decode Constants

Per SPEC §4–§5, word offsets for `proc_csr_slave` and `proc_csr_read`:

```
CSR_WO_ID_CONST              := 16#000#;
CSR_WO_VERSION_CONST         := 16#001#;
CSR_WO_CTRL_CONST            := 16#002#;
CSR_WO_STATUS_CONST          := 16#003#;
CSR_WO_ERR_FLAGS_CONST       := 16#004#;
CSR_WO_ERR_COUNT_CONST       := 16#005#;
CSR_WO_SCRATCH_CONST         := 16#006#;
CSR_WO_FLASH_ADDR_CONST      := 16#007#;
CSR_WO_XFER_BYTES_CONST      := 16#008#;
CSR_WO_PROG_CTRL_CONST       := 16#009#;
CSR_WO_PROG_STATUS_CONST     := 16#00A#;
CSR_WO_STAGED_WORDS_CONST    := 16#00B#;
CSR_WO_MAX10_STAT_CONST      := 16#00C#;
CSR_WO_MAX10_COUNT_CONST     := 16#00D#;
CSR_WO_LAST_ERROR_CONST      := 16#00E#;
CSR_WO_PAGE_DATA_BASE_CONST  := 16#020#;
CSR_WO_PAGE_DATA_END_CONST   := 16#05F#;
```

---

## 5. Error Code Constants

Per SPEC §5.9:

```
ERR_CODE_NONE_CONST               := x"00";
ERR_CODE_START_WHILE_BUSY_CONST   := x"01";
ERR_CODE_START_DURING_RESET_CONST := x"02";
ERR_CODE_ADDR_MISSING_CONST       := x"03";
ERR_CODE_XFER_ZERO_CONST          := x"04";
ERR_CODE_XFER_GT_256_CONST        := x"05";
ERR_CODE_PAGE_UNDERRUN_CONST      := x"06";
ERR_CODE_LINK_TIMEOUT_CONST       := x"07";
ERR_CODE_MAX10_TIMEOUT_CONST      := x"08";
ERR_CODE_MAX10_NSTATUS_CONST      := x"09";
ERR_CODE_MAX10_CRCERROR_CONST     := x"0A";
ERR_CODE_SW_RESET_ABORT_CONST     := x"80";
```

---

## 6. Open Items

1. Confirm dcfifo IP name and instantiation template for Quartus (altera_dcfifo or scfifo+CDC?).
2. Confirm whether `proc_tx_engine_output` should be a named process or concurrent assignments.
   PROPOSAL: use concurrent assignments (simpler, same effect). The plan shows a process for clarity.
3. Confirm FIFO word width: 40 bits sufficient? The header packs 9+23=32 data bits + 8-bit tag.
4. Confirm whether boot history readback states should be included in Rev A or deferred.
   PROPOSAL: defer boot history to Rev B. Keep FSM lean for initial bring-up.
5. Confirm `next_data` handshake for multi-word writes: the legacy max10_spi_split uses
   `next_data` to request the next 32-bit word from the caller during WRITINGDATA. In the new
   design, `proc_max_master` feeds words via `cmd_wdata`. Need to decide if link does single-word
   or multi-word per command.
   PROPOSAL: one link command = one 32-bit word (4 bytes). `proc_max_master` issues N sequential
   link commands for N payload words, each with `cmd_numbytes = "000000100"` (4 bytes).
   For the last partial word: `cmd_numbytes = remaining bytes`.
