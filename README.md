# `feb_max10_comm` — FEB MAX10 Communication Bridge

**Version**: 0.1.0
**Author**: Yifeng Wang (yifenwan@phys.ethz.ch)
**Date**: 2026-03-17
**Device**: Intel Arria V (5AGXBA7D4F31C5)
**Category**: Mu3e Control Plane / Modules

---

## 1. Overview

`feb_max10_comm` is the FEB (Front-End Board) side Arria V to MAX10 flash
programming bridge. It replaces the legacy `max10_prog_avmm` module with a
clean, layered architecture while maintaining full protocol compatibility with
the downstream MAX10 firmware contract (FEBSPI).

The legacy `max10_prog_avmm` packaging tree is kept under
`legacy/max10_prog_avmm/` so older Platform Designer systems can still resolve
the historical component kind while the newer implementation remains the
primary maintained IP.

**What it does:**

1. Accepts standard AVMM CSR transactions from the `sc_hub` controller
2. Stages one 256-byte flash page in local register RAM
3. Crosses the page payload from the CSR clock domain (~156 MHz) to the link
   clock domain (~50 MHz) via a dual-clock FIFO
4. Sequences FEBSPI register writes toward the MAX10 microcontroller
5. Polls MAX10 programming status until completion or error
6. Reports status and error codes back to the CSR bus

---

## 2. Block Diagram

```
                          CSR Clock Domain (~156 MHz)
  ┌──────────────────────────────────────────────────────────────────────┐
  │                                                                      │
  │  ┌────────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
  │  │  proc_csr_slave    │──▶│ proc_stage_store │──▶│ proc_cdc_pusher│  │
  │  │  (AVMM decode,     │   │ (PAGE_DATA[0:63] │   │ (header +      │  │
  │  │   config, status,  │   │  valid tracking, │   │  payload into  │  │
  │  │   error, sw_reset) │   │  snapshot on     │   │  dcfifo)       │  │
  │  └────────▲───────────┘   │  START)          │   └───────┬────────┘  │
  │           │               └──────────────────┘           │           │
  │     AVMM Slave                                           │           │
  │     (sc_hub)                              ┌──────────────▼────────┐  │
  │                                           │   dcfifo_40x128       │  │
  │           ┌───────────────────────────────│   (40-bit x 128-deep  │  │
  │           │  done_toggle (3-stage sync)   │   Gray-code CDC FIFO) │  │
  │           │  + debug mirrors              └───────────────┬───────┘  │
  └───────────┼───────────────────────────────────────────────┼──────────┘
              │                                               │
  ┌───────────┼───────────────────────────────────────────────┼──────────┐
  │           │              Link Clock Domain (~50 MHz)      │          │
  │  ┌────────┴───────────┐                                   │          │
  │  │  proc_max_master   │◀──────────────────────────────────┘          │
  │  │  (L3 transaction   │       launch_toggle (3-stage sync)           │
  │  │   engine: WFIFO,   │                                              │
  │  │   ADDR, CTRL,      │                                              │
  │  │   status poll,     │                                              │
  │  │   count readback)  │                                              │
  │  └─────────┬──────────┘                                              │
  │            │ cmd_valid/cmd_ready                                     │
  │  ┌─────────▼──────────┐                                              │
  │  │   max10_link       │  (L2 command adapter)                        │
  │  │   cmd ─▶ strobe    │                                              │
  │  └─────────┬──────────┘                                              │
  │            │                                                         │
  │  ┌─────────▼──────────┐     ┌──────────────────────────────────┐     │
  │  │  max10_spi_split   │────▶│  SPI Conduit (split-port)        │     │
  │  │  (nibble-serial    │     │  CSN, CLK, MOSI, MISO, D1..D3    │     │
  │  │   FEBSPI protocol) │     │  {*_in, *_out, *_oe} per lane    │     │
  │  └────────────────────┘     └──────────────────────────────────┘     │
  └──────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
                                    MAX10 Device
                                  (SPI Flash Prog)
```

---

## 3. File Hierarchy and Block Partitioning

### 3.1 Source Tree

```
feb_max10_comm/
├── feb_max10_comm_hw.tcl           Qsys/Platform Designer IP definition
├── feb_max10_comm.sdc              CDC timing constraints
├── README.md                       This file
├── rtl/
│   ├── feb_max10_comm.vhd          Top-level structural wrapper
│   ├── max10_controller.vhd        L3 controller (two clock domains)
│   ├── max10_link.vhd              L2 custom SPI link adapter
│   ├── max10_spi_split.vhd         FEBSPI nibble-serial protocol engine
│   └── dcfifo_40x128.vhd           Dual-clock FIFO wrapper (Altera dcfifo)
├── doc/
│   ├── RTL_PLAN.md                 Detailed RTL design specification
│   └── rtl_note.md                 Implementation notes and sign-off status
├── syn/quartus/                    Standalone synthesis harness
│   ├── feb_max10_comm_syn.qsf
│   ├── feb_max10_comm_syn_top.vhd
│   ├── feb_max10_comm_syn.sdc
│   └── output_files/
├── feb_max10_comm_presets.qprs     Platform Designer presets
├── legacy/
│   └── max10_prog_avmm/            Legacy 0.2.0 Platform Designer packaging
└── tb/
    ├── sim/                        8 deterministic SIM_* testcases
    └── uvm/                        128 randomized UVM_* testcases
```

### 3.2 Per-File Descriptions

| File | Layer | Clock Domain | Purpose |
|:-----|:------|:-------------|:--------|
| `feb_max10_comm.vhd` | Top | — | Thin structural wrapper for Qsys integration. No logic, no records, no processes. Passes all generics and ports to `max10_controller`. |
| `max10_controller.vhd` | L3 | `csr_clk` + `link_clk` | The main controller with four processes and one combinational read mux. Owns the CSR slave, page staging, CDC push, and link-domain master FSM. ~1300 lines. |
| `max10_link.vhd` | L2 | `link_clk` | Command adapter presenting `cmd_valid/cmd_ready` handshake to L3. Delegates actual SPI serialization to the proven `max10_spi_split` engine. 5-state FSM. |
| `max10_spi_split.vhd` | L1 | `link_clk` | Nibble-serial FEBSPI master on the 4+1 split-port SPI lanes. Faithful translation of the legacy `max10_spi.vhd` with explicit `*_in/*_out/*_oe` signals instead of `inout`. |
| `dcfifo_40x128.vhd` | Infra | CDC | Wrapper around Altera `dcfifo` IP. 40-bit wide (8-bit tag + 32-bit data), 128-deep, showahead mode, Gray-code pointer synchronization. |
| `feb_max10_comm.sdc` | Timing | CDC | Constrains all CDC paths: FIFO Gray pointers, launch/done toggle synchronizers, reset sync, and debug mirror buses. |

### 3.3 Process Map (`max10_controller.vhd`)

| Process | Type | Clock | Owner Record | Function |
|:--------|:-----|:------|:-------------|:---------|
| `proc_csr_slave` | Sequential | `csr_clk` | `csr_slave_reg_t` | AVMM write decode, config registers, START validation, error handling, sw_reset, CDC feedback consumption |
| `proc_stage_store` | Sequential | `csr_clk` | `stage_store_reg_t` | PAGE_DATA[0..63] storage, per-word valid tracking, contiguous prefix counting, snapshot on launch |
| `proc_cdc_pusher` | Sequential | `csr_clk` | `cdc_pusher_reg_t` | Pushes header + payload words into dcfifo after launch acceptance |
| `proc_max_master` | Sequential | `link_clk` | `max_master_reg_t` | L3 transaction FSM: pops FIFO, streams WFIFO writes, sets ADDR, triggers CTRL START, polls STATUS, reads COUNT, notifies CSR domain |
| `proc_csr_read` | Combinational | — | — | Pure AVMM read multiplexer |

---

## 4. CSR Register Map

All registers are 32-bit, word-addressed. The AVMM slave does not use
byteenables.

| Word | Byte | Name | Access | Description |
|:-----|:-----|:-----|:-------|:------------|
| `0x000` | `0x0000` | ID | RO | Software-visible IP identifier (default ASCII `"M10P"` = `0x4D313050`) |
| `0x001` | `0x0004` | VERSION | RO | Packed `MAJOR[31:24].MINOR[23:16].PATCH[15:12].BUILD[11:0]` |
| `0x002` | `0x0008` | CTRL | WO/RO | Bit 0: software reset. Reads return reset-pending ack. |
| `0x003` | `0x000C` | STATUS | RO | Common ready / busy / fault status |
| `0x004` | `0x0010` | ERR_FLAGS | RW1C | Sticky error flags (write 1 to clear) |
| `0x005` | `0x0014` | ERR_COUNT | RO | Saturating error counter |
| `0x006` | `0x0018` | SCRATCH | RW | Software scratch register |
| `0x007` | `0x001C` | FLASH_ADDR | RW | 24-bit flash byte address for next launch |
| `0x008` | `0x0020` | XFER_BYTES | RW | Byte count for next page launch (1..256) |
| `0x009` | `0x0024` | PROG_CTRL | WO | Bit 0: START, Bit 1: CLEAR_PAGE, Bit 2: CLEAR_STATUS, Bit 3: CLEAR_ADDR |
| `0x00A` | `0x0028` | PROG_STATUS | RO | Composed local + MAX10 programming status |
| `0x00B` | `0x002C` | STAGED_WORDS | RO | Contiguous valid prefix count in PAGE_DATA (0..64) |
| `0x00C` | `0x0030` | MAX10_STAT | RO | CDC mirror of downstream MAX10 programming status |
| `0x00D` | `0x0034` | MAX10_COUNT | RO | CDC mirror of downstream MAX10 programming count |
| `0x00E` | `0x0038` | LAST_ERROR | RO | Most recent error record |
| `0x020`..`0x05F` | `0x0080`..`0x017C` | PAGE_DATA[0..63] | RW | Staging aperture for one 256-byte flash page |

### 4.1 PROG_STATUS Bit Map

| Bit(s) | Field | Description |
|:-------|:------|:------------|
| `[0]` | ready | `not busy AND ready` |
| `[1]` | busy | Transaction in progress |
| `[2]` | page_ready | `staged_words >= ceil(xfer_bytes / 4)` |
| `[3]` | addr_valid | FLASH_ADDR has been written |
| `[4]` | xfer_valid | XFER_BYTES in legal range 1..256 |
| `[5]` | cdc_active | CDC pusher currently streaming |
| `[6]` | launch_accepted | Sticky: most recent START was accepted |
| `[7]` | launch_done | Sticky: most recent launch completed |
| `[15:8]` | max10_raw | Raw MAX10 programming status bits |
| `[23:16]` | fsm_state | Link-domain FSM state encoding |

### 4.2 Error Codes

| Code | Name | Description |
|:-----|:-----|:------------|
| `0x00` | ERR_NONE | No error |
| `0x01` | ERR_START_BUSY | START rejected: transaction already in progress |
| `0x02` | ERR_START_RESET | START rejected: reset pending |
| `0x03` | ERR_ADDR_MISSING | START rejected: FLASH_ADDR not set |
| `0x04` | ERR_XFER_ZERO | START rejected: XFER_BYTES = 0 |
| `0x05` | ERR_XFER_GT_256 | START rejected: XFER_BYTES > 256 |
| `0x06` | ERR_PAGE_UNDERRUN | START rejected: insufficient staged data |
| `0x07` | ERR_LINK_TIMEOUT | STATUS_POLL_LIMIT exceeded |
| `0x08` | ERR_MAX10_TIMEOUT | MAX10 reported timeout |
| `0x09` | ERR_MAX10_NSTATUS | MAX10 nSTATUS low (configuration failure) |
| `0x0A` | ERR_MAX10_CRCERROR | MAX10 CRC error |
| `0x80` | ERR_SW_RESET | Software reset aborted in-flight transaction |

---

## 5. CDC Architecture

| Direction | Mechanism | Payload |
|:----------|:----------|:--------|
| CSR -> Link | `dcfifo_40x128` (Gray-code FIFO) | Header word + N payload words |
| CSR -> Link | `launch_toggle` (3-stage sync) | Edge = new launch available in FIFO |
| CSR -> Link | `reset_sync` (3-stage sync) | Software reset request |
| Link -> CSR | `done_toggle` (3-stage sync) | Edge = launch completed |
| Link -> CSR | Async mirror (3-stage sync) | Debug: `max10_stat`, `max10_count`, `err_flags`, `err_code` |

**FIFO word format** (40 bits):

| Bits | Header Word | Payload Word |
|:-----|:------------|:-------------|
| `[39:32]` tag | `0x01` | `0x00` |
| `[31:0]` data | `{xfer_bytes[8:0], flash_addr[22:0]}` | `page_data[word_index]` |

---

## 6. Standard Programming Workflow

### 6.1 Single-Page Program Sequence (Software Driver)

```
Step 1: Check readiness
    Read PROG_STATUS[0] (ready bit) — must be '1'

Step 2: Set flash address
    Write FLASH_ADDR = target 24-bit byte address

Step 3: Set transfer size
    Write XFER_BYTES = number of valid bytes (1..256)

Step 4: Stage page data
    Burst-write PAGE_DATA[0..N-1] where N = ceil(XFER_BYTES / 4)

Step 5: Verify staging
    Read STAGED_WORDS — must be >= N

Step 6: Launch
    Write PROG_CTRL = 0x1 (START bit)

Step 7: Poll for completion
    Poll PROG_STATUS[1] (busy) until '0'
    — OR poll PROG_STATUS[7] (launch_done) until '1'

Step 8: Check result
    Read PROG_STATUS for error indicators
    Read LAST_ERROR if ERR_FLAGS != 0
    Read MAX10_STAT / MAX10_COUNT for debug

Step 9: Clear for next page
    Write PROG_CTRL = 0x6 (CLEAR_PAGE | CLEAR_STATUS)
    Return to Step 2 for next page
```

### 6.2 Multi-Page Flash Programming Loop

```c
for (page = 0; page < total_pages; page++) {
    // Set target address
    csr_write(FLASH_ADDR, base_addr + page * 256);
    csr_write(XFER_BYTES, 256);

    // Stage one page (burst of 64 words)
    csr_burst_write(PAGE_DATA_BASE, &firmware_image[page * 64], 64);

    // Launch and wait
    csr_write(PROG_CTRL, 0x1);
    while (csr_read(PROG_STATUS) & 0x2)  // busy
        ;

    // Error check
    if (csr_read(ERR_FLAGS) != 0) {
        error_code = csr_read(LAST_ERROR) & 0xFF;
        handle_error(error_code);
        break;
    }

    // Clear for next iteration
    csr_write(PROG_CTRL, 0x6);
}
```

### 6.3 Software Reset

```
Write CTRL[0] = 1

If idle:    immediate reset, registers return to defaults
If in-flight: link domain completes current CTRL_STOP
              before draining — safe for MAX10 state
```

---

## 7. Platform Designer Integration

### 7.1 Interfaces

| Interface | Type | Clock Association | Description |
|:----------|:-----|:------------------|:------------|
| `csr_avmm` | Avalon-MM Slave | `csr_clock` | 32-bit, word-addressed, 0-latency read, burst-aware |
| `csr_clock` | Clock Sink | — | CSR domain clock input (~156 MHz from sc_hub) |
| `csr_reset` | Reset Sink | `csr_clock` | Asynchronous active-high reset |
| `link_clock` | Clock Sink | — | Link domain clock input (~50 MHz toward MAX10) |
| `link_reset` | Reset Sink | `link_clock` | Asynchronous active-high reset |
| `max10_link` | Conduit | `link_clock` | Split-port SPI: CSN, CLK, {MOSI,MISO,D1,D2,D3} x {in,out,oe} |
| `diagnostic` | Conduit | `csr_clock` | Optional (enabled when DEBUG_LEVEL > 0): summary, err_flags, last_error, max10_stat, max10_count |

### 7.2 Parameters

| Parameter | Default | Range | Description |
|:----------|:--------|:------|:------------|
| `CSR_ADDR_W` | 10 | 7..32 | AVMM address width in bits. Must cover PAGE_DATA aperture through word `0x5F`. |
| `BURSTCOUNT_W` | 9 | 1..16 | Burstcount width. Match the upstream `sc_hub` master configuration. |
| `CDC_FIFO_ADDR_W` | 7 | 7..10 | FIFO depth = `2^CDC_FIFO_ADDR_W`. Minimum 128 entries (7 bits) for header + 64 payload words. |
| `DEBUG_LEVEL` | 1 | 0..4 | Nonzero enables the optional `diagnostic` conduit. Set to 0 for production builds. |
| `VERSION_MAJOR` | 0 | 0..255 | Firmware version major number |
| `VERSION_MINOR` | 1 | 0..255 | Firmware version minor number |
| `VERSION_PATCH` | 0 | 0..15 | Firmware version patch number |
| `BUILD` | 0 | 0..4095 | 12-bit build stamp |
| `IP_ID` | `0x4D313050` | 0..2^31-1 | Software-visible ID register. Default = ASCII `"M10P"`. |

### 7.3 Derived Values (Read-Only, shown in GUI)

| Derived Parameter | Formula |
|:------------------|:--------|
| `PAGE_WORDS_DERIVED` | 64 (fixed) |
| `PAGE_BYTES_DERIVED` | 256 (fixed) |
| `PAGE_RAM_BITS_DERIVED` | 2048 (fixed) |
| `CDC_FIFO_DEPTH_DERIVED` | `2^CDC_FIFO_ADDR_W` |
| `CDC_FIFO_BITS_DERIVED` | `CDC_FIFO_DEPTH * 40` |
| `TOTAL_RAM_BITS_DERIVED` | `PAGE_RAM_BITS + CDC_FIFO_BITS` |
| `CSR_SPAN_WORDS_DERIVED` | `2^CSR_ADDR_W` |

### 7.4 Platform Designer GUI Tabs

The `_hw.tcl` organizes parameters into four tabs. When opening the component
in Platform Designer, the following layout is presented:

```
┌────────────────────────────────────────────────────────────────────────┐
│  FEB MAX10 Communication Bridge                                  v0.1.0│
├──────────┬──────────┬────────────┬──────────────┐                      │
│ Configu- │ Identity │ Interfaces │ Register Map │                      │
│ ration   │          │            │              │                      │
├──────────┴──────────┴────────────┴──────────────┴──────────────────────┤
│                                                                        │
│  ┌─ Overview ────────────────────────────────────────────────────────┐ │
│  │ Function: This IP accepts standard incrementing AVMM bursts from  │ │
│  │ sc_hub, stages one 256-byte flash page, and forwards it onto the  │ │
│  │ existing MAX10 FEBSPI programming chain.                          │ │
│  │                                                                   │ │
│  │ Clocking: CSR and page staging live in csr_clock. The downstream  │ │
│  │ FEBSPI master lives in link_clock. Launch metadata and payload    │ │
│  │ cross domains through a dedicated dual-clock FIFO.                │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌─ Sizing ──────────────────────────────────────────────────────────┐ │
│  │ CSR Address Width ............. [10] bits                         │ │
│  │ Burstcount Width ..............  [9] bits                         │ │
│  │ CDC FIFO Address Width ........  [7] bits                         │ │
│  │                                                                   │ │
│  │ Derived storage:                                                  │ │
│  │   PAGE_DATA RAM:  256 bytes (2048 bits)                           │ │
│  │   CDC FIFO depth: 128 entries of 40 bits                          │ │
│  │   CDC FIFO:       5120 bits                                       │ │
│  │   Total staging:  896 bytes (7168 bits)                           │ │
│  │   CSR aperture:   1024 words                                      │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  ┌─ Advanced ────────────────────────────────────────────────────────┐ │
│  │ Integration notes:                                                │ │
│  │ 1. PAGE_DATA occupies words 0x020..0x05F                          │ │
│  │ 2. FIFO must hold 1 header + 64 payload words                     │ │
│  │ 3. Conduit exports split in/out/oe — board owns tri-state buffers │ │
│  │                                                                   │ │
│  │ Debug Level ...................  [1]                              │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                        │
│  [Identity Tab] ── VERSION_MAJOR/MINOR/PATCH, BUILD, IP_ID             │
│  [Interfaces Tab] ── HTML descriptions of csr_avmm, max10_link, diag   │
│  [Register Map Tab] ── Full CSR address table (HTML)                   │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**To capture screenshots in Platform Designer:**

1. Open the Quartus project containing this IP
2. Launch Platform Designer (Tools > Platform Designer)
3. Double-click the `feb_max10_comm` instance (or Add > Mu3e Control Plane > Modules)
4. Screenshot each of the four tabs: **Configuration**, **Identity**, **Interfaces**, **Register Map**
5. For the system view: show the IP instance with its connected interfaces (csr_avmm, clocks, resets, conduits)

### 7.5 Presets

Two presets are provided:

| Preset | Use Case | Key Differences |
|:-------|:---------|:----------------|
| **FEB Standard** | Default FEB integration with sc_hub. Matches current board build. | `CSR_ADDR_W=10`, `BURSTCOUNT_W=9`, `DEBUG_LEVEL=1` (diagnostic conduit enabled) |
| **Production Minimal** | Production builds with reduced resource usage. No diagnostic conduit. | `CSR_ADDR_W=7`, `BURSTCOUNT_W=1`, `DEBUG_LEVEL=0` (diagnostic conduit disabled) |

Presets can be loaded from:
- The **Presets** dropdown in Platform Designer (Quartus/Platform Designer 18.1 discovers the `.qprs` file when it sits next to `_hw.tcl`)
- Or applied manually using the parameter values above

---

## 8. Timing and Resource Summary

### 8.1 Clock Domains

| Domain | Frequency | Period | WNS Margin Target |
|:-------|:----------|:-------|:------------------|
| `csr_clk` | 156.25 MHz | 6.400 ns | >= +1.280 ns (20%) |
| `link_clk` | 50 MHz | 20.000 ns | >= +4.000 ns (20%) |

### 8.2 Standalone Timing (Arria V, current `syn/quartus` build)

The current standalone build in `syn/quartus/output_files/` meets the 20%
positive-slack requirement on both sign-off clocks.

| Clock | Worst Setup Corner | WNS | TNS | 20% Gate | Status |
|:------|:-------------------|:----|:----|:---------|:-------|
| `csr_clk` | Slow 1100mV 85C | +1.290 ns | 0.000 ns | >= +1.280 ns | Pass (+0.010 ns headroom) |
| `link_clk` | Slow 1100mV 0C | +13.370 ns | 0.000 ns | >= +4.000 ns | Pass |

Worst hold slack is +0.147 ns at the Fast 1100mV 0C corner on `link_clk`.
Minimum pulse width is clean at all reported corners.

### 8.3 Resource Usage (Standalone)

| Resource | Count |
|:---------|:------|
| ALMs | 1,585 |
| Registers (FFs) | 3,775 |
| RAM Blocks | 1 |
| RAM Bits | 4,096 |
| DSP Blocks | 0 |

---

## 9. Verification Status

| Suite | Cases | Status |
|:------|:------|:-------|
| `tb/sim/` (deterministic) | 8 SIM_* | All pass |
| `tb/uvm/` (randomized) | 128 UVM_* | All pass |
| Qsys parity regeneration | 2 systems | Pass (debug_sc_system, feb_system) |
| Gate-level simulation | — | Not yet run |

### 9.1 Simulation Test List

**Deterministic (`tb/sim/`)**:
- `SIM_001_RESET_DEFAULTS` — Verify register reset values
- `SIM_002_CSR_STAGE_PREFIX` — PAGE_DATA staging and prefix counting
- `SIM_003_FULL_PAGE_PROGRAM` — Complete 256-byte programming flow
- `SIM_004_PARTIAL_ODD` — Partial page with odd byte count
- `SIM_005_BACK_TO_BACK_SNAPSHOT` — Consecutive launches with snapshot reuse
- `SIM_006_LAUNCH_REJECTS` — All START rejection error codes
- `SIM_007_SW_RESET_FLUSH` — Software reset during idle and in-flight
- `SIM_008_FAULT_INJECTION` — MAX10 timeout, nSTATUS, CRC error injection

**Randomized (`tb/uvm/`)**:
- `UVM_001..016` — Reset defaults, versioning, CSR semantics
- `UVM_017..048` — Legal programming flows
- `UVM_049..072` — Overlap, snapshot reuse, clear operations
- `UVM_073..096` — Clock-ratio and reset-phase stress
- `UVM_097..112` — Timeout, CRC, nSTATUS, underrun, reset-drain
- `UVM_113..128` — Fully randomized regressions

**Note**: Simulation uses `STATUS_POLL_LIMIT=1024` for practical test times;
synthesis default is `50000` (~1 ms at 50 MHz).

---

## 10. Integration Checklist

- [ ] Add `feb_max10_comm` to your Platform Designer system
- [ ] Connect `csr_avmm` to your `sc_hub` master
- [ ] Connect `csr_clock` / `csr_reset` to the system CSR clock (~156 MHz)
- [ ] Connect `link_clock` / `link_reset` to the MAX10 link clock (~50 MHz)
- [ ] Export the `max10_link` conduit to the top level
- [ ] In your top-level board file: terminate the SPI conduit with explicit tri-state IO buffers and any board-specific pin workarounds
- [ ] Optionally export the `diagnostic` conduit for bring-up / SignalTap capture
- [ ] Set `DEBUG_LEVEL=0` for final production builds to save resources
- [ ] Verify that the `feb_max10_comm.sdc` is included in the Quartus project (auto-included via Qsys fileset)

---

## 11. Known Issues and Open Items

1. **Gate-level simulation**: Not yet run. Should be added for formal sign-off.

2. **DV_PLAN.md**: Missing — should be created if formal verification traceability is required.

3. **Boot history readback**: Deferred to Rev B. The current design covers programming-only.

---

## 12. References

- `doc/RTL_PLAN.md` — Full RTL ownership specification and process descriptions
- `doc/rtl_note.md` — Sign-off status, iteration history, integration evidence
- `legacy/max10_prog_avmm/SPEC.md` — Legacy specification and protocol contract reference
