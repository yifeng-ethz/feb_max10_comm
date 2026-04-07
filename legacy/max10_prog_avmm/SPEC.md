# `max10_prog_avmm` Specification

- status   : draft
- author   : Yifeng Wang (yifenwan@phys.ethz.ch)
- created  : 2026-03-12
- based-on : `online/fe_board/firmware/FEB_common/max10_interface/max10_interface.vhd`
- based-on : `online/fe_board/firmware/FEB_common/max10_interface/max10_spi.vhd`
- based-on : `online/fe_board/fe_max10/top.vhd`
- based-on : `online/fe_board/fe_max10/spiflash/flashprogramming_block.vhd`
- based-on : `online/fe_board/ip_mu3e/sc_hub/sc_hub.vhd`

---

## 0. Conventions and Terminology

### 0.1 Document Conventions

- All registers are little-endian, 32-bit, and word-aligned.
- Register offsets are given in both word offsets (`WO`) and byte offsets.
- `RW` means read-write, `RO` means read-only, `WO` means write-only, and `RW1C` means write-1-to-clear.
- Reserved fields are write-ignored and read as `0` unless stated otherwise.
- The software-visible interface shall use standard incrementing AVMM writes only.
- The legacy SC nonincrementing semantic is explicitly out of scope for this IP.

### 0.2 Abbreviations

| Abbrev | Meaning |
|:--|:--|
| AVMM | Avalon Memory-Mapped |
| CSR | Control and Status Register |
| FEB | Front-End Board |
| FPP | Fast Passive Parallel |
| MAX10 | Intel MAX 10 FPGA / system controller |
| SC | Slow Control |
| WFIFO | MAX10 programming write FIFO |

### 0.3 Problem Statement

The existing FEB Arria-side MAX10 programming path uses the legacy SC register
window `0xFC27..0xFC2A` and depends on the software sending
`PACKET_TYPE_SC_WRITE_NONINCREMENTING` to stream programming data into a FIFO.
That makes the programming path a protocol exception in both software and
firmware.

The new IP shall replace that legacy Arria-side wrapper with a standard
AVMM-slave interface behind `sc_hub`. The software-visible programming contract
shall become:

1. Write normal incrementing bursts into a page aperture.
2. Write the flash address and valid byte count.
3. Pulse a start bit.
4. Poll status until completion.

The downstream MAX10 firmware shall remain unchanged.

---

## 1. Scope

### 1.1 Goals

The IP shall:

1. Expose a standard 32-bit AVMM CSR slave toward `sc_hub`.
2. Accept incrementing burst writes for page staging.
3. Preserve the existing Arria-to-MAX10 custom SPI-like protocol.
4. Preserve the existing MAX10 register protocol:
   - `FEBSPI_ADDR_PROGRAMMING_WFIFO`
   - `FEBSPI_ADDR_PROGRAMMING_ADDR`
   - `FEBSPI_ADDR_PROGRAMMING_CTRL`
   - `FEBSPI_ADDR_PROGRAMMING_STATUS`
   - `FEBSPI_ADDR_PROGRAMMING_COUNT`
5. Support partial final pages without software-side padding requirements.
6. Surface software-stable local status and raw MAX10 status separately.

### 1.2 Non-Goals

The IP shall not:

1. Change MAX10 firmware register definitions or flash-programming behavior.
2. Change MAX10 passive-parallel Arria reconfiguration behavior.
3. Require software use of nonincrementing SC writes.
4. Auto-increment flash address across page launches in Rev A.
5. Replace unrelated uses of SC nonincrementing semantics elsewhere in the project.

---

## 2. Placement and Interfaces

### 2.1 System Placement

`max10_prog_avmm` is an Arria-side control IP intended to be instantiated in the
control-path subsystem behind `sc_hub.hub_avmm`.

At the system level:

- upstream software path:
  `host -> slow-control packet -> sc_hub -> AVMM write/read -> max10_prog_avmm`
- downstream hardware path:
  `max10_prog_avmm -> custom Arria/MAX10 SPI-like link -> MAX10 flashprogramming_block`

This IP replaces the legacy Arria-side software-facing role of
`max10_interface`, but reuses its downstream protocol.

### 2.2 Top-Level Interfaces

The IP shall expose:

1. `csr_clock` and `csr_reset`
   - AVMM CSR clock domain.
   - Intended source: `sc_hub` clock domain.
2. `avs_csr_*`
   - 32-bit AVMM slave interface.
3. `link_clock` and `link_reset`
   - Downstream custom protocol clock domain.
   - Intended source: existing Arria-side MAX10 link clock domain.
4. `max10_link_*`
   - Custom SPI-like conduit toward the existing Arria/MAX10 wiring.

### 2.3 Clocking

The legacy path stages programming data in the `156.25 MHz` domain and consumes
it in the `50 MHz` MAX10 link domain. Rev A of this IP shall keep that
separation.

Hard spec:

1. AVMM CSR and page staging state live in `csr_clock`.
2. The custom MAX10 protocol engine lives in `link_clock`.
3. `START` launches shall cross domains through an explicit CDC mechanism.
4. Page payload transfer into the link domain shall use an explicit CDC-safe
   structure.

PROPOSAL for Rev A:

- page aperture storage in `csr_clock`
- valid-mask plus metadata snapshot on accepted `START`
- payload transfer to `link_clock` through a dual-clock FIFO or equivalent
  CDC-safe buffer

OPEN:

- confirm final `link_clock` source for the Qsys integration path
- decide whether a later revision should absorb the link engine into the
  `csr_clock` domain using a programmable SPI clock divider

### 2.4 Downstream MAX10 Contract

The IP shall preserve the current downstream register-level contract:

| FEBSPI Address | Symbol | Direction | Purpose |
|:--|:--|:--|:--|
| `0x10` | `FEBSPI_ADDR_PROGRAMMING_STATUS` | read | MAX10 programming status |
| `0x11` | `FEBSPI_ADDR_PROGRAMMING_COUNT`  | read | MAX10 debug/programming count |
| `0x12` | `FEBSPI_ADDR_PROGRAMMING_CTRL`   | write | MAX10 page-program trigger |
| `0x13` | `FEBSPI_ADDR_PROGRAMMING_ADDR`   | write | flash byte address |
| `0x14` | `FEBSPI_ADDR_PROGRAMMING_WFIFO`  | write | programming payload bytes |

The MAX10 firmware is the source of truth for:

- flash erase decision at `64 KiB` boundaries
- quad-page-program execution
- FPP replay into Arria
- `CONF_DONE`, `NSTATUS`, `TIMEOUT`, and `CRCERROR`

---

## 3. Functional Behavior

### 3.1 Programming Granularity

The software-visible staging granularity is one flash page:

- `PAGE_SIZE_BYTES = 256`
- `PAGE_SIZE_WORDS = 64`

The host may request any `XFER_BYTES` value in the range `1..256`.

### 3.2 Software Transaction Model

One page program transaction is:

1. Ensure the IP is not in software reset.
2. Write `FLASH_ADDR`.
3. Write `XFER_BYTES`.
4. Write `PAGE_DATA[0..N-1]` using a standard incrementing burst.
5. Pulse `PROG_CTRL.start`.
6. Poll `STATUS.busy` or `PROG_STATUS.busy` until `0`.
7. Check `ERR_FLAGS` and raw `MAX10_STAT` if needed.

The IP shall not require:

- nonincrementing writes
- software-side padding of the final page to a full `256` bytes
- writing the page aperture more than once per page launch

### 3.3 Byte and Word Ordering

`PAGE_DATA[n]` stores four payload bytes:

- `PAGE_DATA[n][7:0]`   = byte `4n + 0`
- `PAGE_DATA[n][15:8]`  = byte `4n + 1`
- `PAGE_DATA[n][23:16]` = byte `4n + 2`
- `PAGE_DATA[n][31:24]` = byte `4n + 3`

The downstream link engine shall emit only the first `XFER_BYTES` bytes of the
staged page. Bytes beyond that limit shall be ignored for the current launch.

### 3.4 Page Validity Model

The IP shall maintain a `64-bit` word-valid mask for `PAGE_DATA[0..63]`.

Hard spec:

1. A word becomes valid when software writes its `PAGE_DATA` location.
2. `STAGED_WORDS` reports the length of the contiguous valid prefix starting at
   word `0`.
3. `page_ready = 1` when `STAGED_WORDS >= ceil(XFER_BYTES / 4)`.
4. Sparse writes are permitted, but `START` shall be rejected until the
   contiguous prefix covers the requested transfer.
5. `PROG_CTRL.clear_page` clears the valid mask and zeroes the page aperture.

### 3.5 Accepted `START` Sequence

When `PROG_CTRL.start` is accepted, the IP shall:

1. Snapshot `FLASH_ADDR`, `XFER_BYTES`, and the required staged payload.
2. Stream `XFER_BYTES` bytes to MAX10 `FEBSPI_ADDR_PROGRAMMING_WFIFO`.
3. Write `FLASH_ADDR` to MAX10 `FEBSPI_ADDR_PROGRAMMING_ADDR`.
4. Write `1` to MAX10 `FEBSPI_ADDR_PROGRAMMING_CTRL`.
5. Poll MAX10 `FEBSPI_ADDR_PROGRAMMING_STATUS` until the MAX10 page-program
   operation completes.
6. Write `0` to MAX10 `FEBSPI_ADDR_PROGRAMMING_CTRL`.
7. Clear local busy state and latch success or failure status.

### 3.6 Rejected `START` Conditions

`PROG_CTRL.start` shall be rejected and set sticky error flags when:

1. a previous transaction is still busy
2. software reset is in progress
3. `FLASH_ADDR` has not been written since reset or `CTRL.sw_reset`
4. `XFER_BYTES = 0`
5. `XFER_BYTES > 256`
6. `page_ready = 0`

### 3.7 Software Reset

Common `CTRL.sw_reset` behavior:

1. Local in-flight state is aborted.
2. Page aperture and valid mask are cleared.
3. `FLASH_ADDR` valid latch is cleared.
4. `XFER_BYTES` resets to default.
5. Sticky `ERR_FLAGS` are cleared.
6. `STATUS.busy` and `PROG_STATUS.busy` return to `0`.

---

## 4. Common CSR Header

### 4.1 Common CSR Header (All IPs)

Every `max10_prog_avmm` instance maps a 32-bit CSR window. The first `7 DW`
(`WO 0x000..0x006`, byte offsets `0x000..0x018`) are reserved for a uniform
management header.

| WO    | Byte Offs | Name        | Access | Reset | Description |
|:--:|:--:|:--|:--:|:--:|:--|
| `0x000` | `0x000` | `ID`        | RO   | impl | IP identifier magic, encoded as 4 ASCII chars. |
| `0x001` | `0x004` | `VERSION`   | RO   | impl | Packed component version. |
| `0x002` | `0x008` | `CTRL`      | RW   | `0`  | Common management control with only software reset defined in Rev A. |
| `0x003` | `0x00C` | `STATUS`    | RO   | `0`  | Common ready, busy, fault, and resetting summary. |
| `0x004` | `0x010` | `ERR_FLAGS` | RW1C | `0`  | Sticky local error flags. |
| `0x005` | `0x014` | `ERR_COUNT` | RO   | `0`  | Saturating 32-bit error event counter. |
| `0x006` | `0x018` | `SCRATCH`   | RW   | `0`  | Diagnostic scratch register with no side-effects. |

IP-specific registers start at `WO 0x007`.

### 4.2 `ID` Encoding

`ID` uses a 4-character ASCII magic:

- `ID[31:24] = CHAR3`
- `ID[23:16] = CHAR2`
- `ID[15:8]  = CHAR1`
- `ID[7:0]   = CHAR0`

Rev A identity:

- `ID = "M10P"`
- `ID = 32'h4D31_3050`

### 4.3 `VERSION` Encoding

Displayed `_hw.tcl` version string:

`MAJOR.MINOR.PATCH`

Packed CSR encoding:

- `VERSION[31:24] = MAJOR`
- `VERSION[23:16] = MINOR`
- `VERSION[15:12] = PATCH`
- `VERSION[11:0]  = BUILD`

Rules:

1. `BUILD = 0` means unset or unknown.
2. `BUILD` is generation-time provenance and not software ABI.
3. Software compatibility shall use `IF_VERSION = VERSION[31:12]`.

### 4.4 Common `CTRL` Bitfields

| Bit | Name | Meaning |
|:--:|:--|:--|
| `0` | `sw_reset` | Soft reset. Abort local state and self-clear when complete. |
| `31:1` | reserved | Write `0`. |

### 4.5 Common `STATUS` Bitfields

| Bit | Name | Meaning |
|:--:|:--|:--|
| `0` | `ready`    | IP is CSR-accessible and not held in software reset. For this IP, this is normally `1`. |
| `1` | `busy`     | At least one local programming operation is in flight. |
| `2` | `fault`    | Sticky summary: `ERR_FLAGS != 0`. |
| `3` | `resetting`| Software reset is in progress. |
| `31:4` | reserved | Read `0`. |

### 4.6 `ERR_FLAGS` Bitfields

| Bit | Name | Meaning |
|:--:|:--|:--|
| `0`  | `start_while_busy`   | `START` requested while the IP was busy. |
| `1`  | `start_during_reset` | `START` requested while software reset was in progress. |
| `2`  | `addr_missing`       | `START` requested before `FLASH_ADDR` was valid. |
| `3`  | `xfer_bytes_zero`    | `XFER_BYTES = 0`. |
| `4`  | `xfer_bytes_gt_256`  | `XFER_BYTES > 256`. |
| `5`  | `page_underrun`      | `START` requested before enough contiguous data was staged. |
| `6`  | `link_timeout`       | Downstream Arria/MAX10 link transaction timed out. |
| `7`  | `max10_timeout`      | MAX10 programming status reported timeout. |
| `8`  | `max10_crcerror`     | MAX10 programming status reported CRC error. |
| `9`  | `max10_nstatus_low`  | MAX10 programming status reported `NSTATUS = 0`. |
| `31:10` | reserved | Write `0`, read `0`. |

`ERR_COUNT` increments once per newly-detected error event and saturates at
`32'hFFFF_FFFF`.

---

## 5. IP-Specific CSR Register Map

### 5.1 Register Map

| WO    | Byte Offs | Name          | Access | Reset | Description |
|:--:|:--:|:--|:--:|:--:|:--|
| `0x007` | `0x01C` | `FLASH_ADDR`   | RW | `0`   | Absolute flash byte address, valid in bits `[23:0]`. |
| `0x008` | `0x020` | `XFER_BYTES`   | RW | `256` | Number of valid payload bytes for the next `START`. |
| `0x009` | `0x024` | `PROG_CTRL`    | WO | `0`   | Write-one pulse programming commands. |
| `0x00A` | `0x028` | `PROG_STATUS`  | RO | `0`   | Programming engine status and raw MAX10 summary. |
| `0x00B` | `0x02C` | `STAGED_WORDS` | RO | `0`   | Contiguous valid word count from `PAGE_DATA[0]`. |
| `0x00C` | `0x030` | `MAX10_STAT`   | RO | `0`   | Raw mirror of MAX10 `PROGRAMMING_STATUS`. |
| `0x00D` | `0x034` | `MAX10_COUNT`  | RO | `0`   | Raw mirror of MAX10 `PROGRAMMING_COUNT`. |
| `0x00E` | `0x038` | `LAST_ERROR`   | RO | `0`   | Last error code and debug snapshot. |
| `0x00F` | `0x03C` | reserved       | —  | —     | Reserved. |
| `0x010..0x01F` | `0x040..0x07C` | reserved | — | — | Reserved for future metadata or counters. |
| `0x020..0x05F` | `0x080..0x17C` | `PAGE_DATA[0..63]` | RW | `0` | Local page staging aperture, 64 words = 256 bytes. |
| `0x060..0x3FF` | `0x180..0xFFC` | reserved | — | — | Reserved. |

### 5.2 `FLASH_ADDR`

| Bits | Meaning |
|:--|:--|
| `[23:0]` | Absolute SPI-flash byte address. |
| `[31:24]` | Reserved. |

Hard spec:

1. Writing `FLASH_ADDR` marks the local address-valid latch.
2. The IP does not auto-increment `FLASH_ADDR` after `START` in Rev A.

### 5.3 `XFER_BYTES`

| Bits | Meaning |
|:--|:--|
| `[8:0]` | Valid payload byte count for the next page launch. |
| `[31:9]` | Reserved. |

Hard spec:

1. Valid range is `1..256`.
2. Reset value is `256`.
3. Values outside the valid range are rejected only on `START`, not on write.

### 5.4 `PROG_CTRL`

`PROG_CTRL` is write-only. Each defined bit is a write-one pulse. Reads return
`0`.

| Bit | Name | Meaning |
|:--:|:--|:--|
| `0` | `start`          | Launch one programming transaction. |
| `1` | `clear_page`     | Clear page aperture, valid mask, and `STAGED_WORDS`. |
| `2` | `clear_status`   | Clear `LAST_ERROR` and non-common sticky programming status. |
| `3` | `clear_addr`     | Clear local address-valid latch and zero `FLASH_ADDR`. |
| `31:4` | reserved | Write `0`. |

### 5.5 `PROG_STATUS`

| Bit | Name | Meaning |
|:--:|:--|:--|
| `0`  | `ready`              | Local engine is idle and launch-eligible. |
| `1`  | `busy`               | Local programming launch is in progress. |
| `2`  | `page_ready`         | Enough contiguous page data is staged for current `XFER_BYTES`. |
| `3`  | `addr_valid`         | `FLASH_ADDR` has been written since reset or clear. |
| `4`  | `len_valid`          | `XFER_BYTES` is in the legal range `1..256`. |
| `5`  | `cdc_busy`           | Metadata or payload handoff across domains is in progress. |
| `6`  | `launch_accepted`    | Sticky until `clear_status`; most recent `START` was accepted. |
| `7`  | `launch_done`        | Sticky until `clear_status`; most recent accepted `START` finished. |
| `8`  | `max10_arriawriting` | Raw mirror of MAX10 `PROGRAMMING_STATUS[0]`. |
| `9`  | `max10_spi_busy`     | Raw mirror of MAX10 `PROGRAMMING_STATUS[1]`. |
| `10` | `max10_fifo_empty`   | Raw mirror of MAX10 `PROGRAMMING_STATUS[14]`. |
| `11` | `max10_fifo_full`    | Raw mirror of MAX10 `PROGRAMMING_STATUS[15]`. |
| `12` | `max10_conf_done`    | Raw mirror of MAX10 `PROGRAMMING_STATUS[16]`. |
| `13` | `max10_nstatus`      | Raw mirror of MAX10 `PROGRAMMING_STATUS[17]`. |
| `14` | `max10_timeout`      | Raw mirror of MAX10 `PROGRAMMING_STATUS[18]`. |
| `15` | `max10_crcerror`     | Raw mirror of MAX10 `PROGRAMMING_STATUS[19]`. |
| `23:16` | `engine_state`    | Local debug state encoding, implementation-defined. |
| `31:24` | reserved          | Read `0`. |

### 5.6 `STAGED_WORDS`

| Bits | Meaning |
|:--|:--|
| `[6:0]` | Number of contiguous valid words staged from `PAGE_DATA[0]`. |
| `[31:7]` | Reserved. |

### 5.7 `MAX10_STAT`

`MAX10_STAT` is a raw mirror of the MAX10 `FEBSPI_ADDR_PROGRAMMING_STATUS`
register. Bit numbers are intentionally unchanged from the MAX10 firmware
contract.

Relevant known bits:

| Bit | Meaning |
|:--:|:--|
| `0`  | Arria writing in progress |
| `1`  | SPI flash engine busy |
| `14` | programming FIFO empty |
| `15` | programming FIFO full |
| `16` | `CONF_DONE` |
| `17` | `NSTATUS` |
| `18` | timeout |
| `19` | CRC error |
| `31:24` | MAX10 FPP debug |

### 5.8 `MAX10_COUNT`

`MAX10_COUNT` is a raw mirror of MAX10 `FEBSPI_ADDR_PROGRAMMING_COUNT`.
Software shall treat it as debug-only.

### 5.9 `LAST_ERROR`

| Bits | Meaning |
|:--|:--|
| `[7:0]`   | last error code |
| `[15:8]`  | last local engine state |
| `[23:16]` | last staged word count at failure |
| `[31:24]` | last MAX10 debug byte (`MAX10_STAT[31:24]`) |

Error code assignments:

| Code | Meaning |
|:--:|:--|
| `0x00` | none |
| `0x01` | start while busy |
| `0x02` | start during reset |
| `0x03` | missing address |
| `0x04` | `XFER_BYTES = 0` |
| `0x05` | `XFER_BYTES > 256` |
| `0x06` | page underrun |
| `0x07` | link timeout |
| `0x08` | MAX10 timeout |
| `0x09` | MAX10 CRC error |
| `0x0A` | MAX10 `NSTATUS = 0` |
| `0x0B` | aborted by software reset |

---

## 6. Software Contract

### 6.1 Required Access Pattern

Software shall use standard incrementing writes.

Recommended sequence per page:

1. Optionally clear previous page and status:
   - `PROG_CTRL.clear_page = 1`
   - `PROG_CTRL.clear_status = 1`
2. Write `FLASH_ADDR`.
3. Write `XFER_BYTES`.
4. Write `PAGE_DATA[0..N-1]` as a single incrementing burst when possible.
5. Pulse `PROG_CTRL.start`.
6. Poll:
   - common `STATUS.busy == 0`
   - and optionally `PROG_STATUS.launch_done == 1`
7. Check `ERR_FLAGS == 0`.

### 6.2 Partial Final Page

The final image chunk is supported without padding:

1. Set `XFER_BYTES` to the exact number of valid bytes in the last chunk.
2. Write only the required `PAGE_DATA` words.
3. Pulse `START`.

The hardware shall emit exactly `XFER_BYTES` bytes downstream.

### 6.3 Readback Expectations

Software may read back:

- common management header
- `FLASH_ADDR`
- `XFER_BYTES`
- `PROG_STATUS`
- `STAGED_WORDS`
- `MAX10_STAT`
- `MAX10_COUNT`
- `LAST_ERROR`
- `PAGE_DATA[*]`

Software shall not depend on:

- `engine_state` numeric values
- `MAX10_COUNT` numeric interpretation
- the exact contents of unused or invalid page words

---

## 7. Migration from Legacy Path

### 7.1 Legacy Registers Replaced

The new IP replaces the software-facing role of:

- `PROGRAMMING_CTRL_REGISTER_W  = 0xFC27`
- `PROGRAMMING_STATUS_REGISTER_R = 0xFC28`
- `PROGRAMMING_ADDR_REGISTER_W  = 0xFC29`
- `PROGRAMMING_DATA_REGISTER_W  = 0xFC2A`

### 7.2 Mapping

| Legacy path | New path |
|:--|:--|
| `PROGRAMMING_CTRL_REGISTER_W` | common `CTRL` + `PROG_CTRL` |
| `PROGRAMMING_STATUS_REGISTER_R` | common `STATUS` + `PROG_STATUS` + `MAX10_STAT` |
| `PROGRAMMING_ADDR_REGISTER_W` | `FLASH_ADDR` |
| repeated nonincrementing write to `PROGRAMMING_DATA_REGISTER_W` | incrementing AVMM burst into `PAGE_DATA[*]` |

### 7.3 Compatibility

The MAX10-side firmware path remains unchanged. Only the Arria-side
software-visible wrapper changes.

---

## 8. Required Internal Structure

This section is normative at the contract level, but does not fully constrain
the micro-architecture.

### 8.1 Required Blocks

The IP shall contain the following logical blocks:

1. AVMM CSR front-end
2. page aperture storage plus valid-mask tracking
3. common CSR header block
4. programming launch controller
5. CDC path from `csr_clock` to `link_clock`
6. downstream MAX10 register engine
7. custom SPI-like physical/link master or wrapper

### 8.2 Single-Writer Discipline

Hard spec:

1. CSR-domain state is owned only by CSR-domain processes.
2. Link-domain state is owned only by link-domain processes.
3. CDC handoff flags shall have explicit ownership and acknowledgement.

### 8.3 Downstream Link Engine

The downstream link engine may be:

1. a refactoring of the current `max10_interface` engine plus `max10_spi`
2. a new wrapper around the existing `max10_spi`

In either case, the externally visible MAX10 behavior must remain unchanged.

---

## 9. Verification Requirements

Minimum directed verification shall cover:

1. standard full-page program with `XFER_BYTES = 256`
2. partial final page with `XFER_BYTES < 256`
3. rejected `START` with missing address
4. rejected `START` with insufficient staged data
5. rejected `START` while busy
6. rejected `START` during software reset
7. soft reset during idle
8. soft reset during in-flight launch
9. propagation of MAX10 timeout and CRC-error status
10. readback of staged page data
11. contiguous-prefix handling for sparse page writes

Simulation-time assertions shall check:

1. AVMM request stability during `waitrequest`
2. CDC command acceptance does not duplicate or drop launches
3. no downstream byte emission beyond `XFER_BYTES`
4. `START` cannot be accepted when `page_ready = 0`

---

## 10. Open Items

1. Confirm final IP directory and entity naming:
   - `max10_prog_avmm`
   - or `max10_flash_bridge`
2. Confirm whether the control-path subsystem should import a dedicated
   `50 MHz` link clock or whether the link engine will be refactored to run
   from `156.25 MHz`.
3. Confirm whether a project-wide common `DATE` CSR should be added after
   `VERSION` for all new AVMM control IPs.
4. Confirm whether software wants a dedicated monotonically increasing launch
   counter in Rev A.
