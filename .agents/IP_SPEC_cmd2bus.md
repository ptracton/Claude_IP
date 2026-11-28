# Byte command protocol (`claude_cmd2bus`) — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_cmd2bus.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.7). Nothing here is
implemented yet.

`uart2bus`, `spi_slave` (bus-master mode), `i2c_slave` (bus-master mode) and `jtag2bus`
(with its DMA burst mode, D5) all do the same job: turn a stream of bytes from an external
host into bus transactions, and send results back. **One engine**, `claude_cmd2bus`, does
this for all of them; each IP adds only a thin physical front end. One host library drives
every one of them the same way.

```
 UART pins ─► uart PHY ─┐                                      ┌─► mem_* ─► claude_<proto>_mst_if ─► bus
 SPI pins ─► SCK front ─┤ s_cmd_* (bytes) ┌─────────────────┐  │
 I2C pins ─► i2c front ─┼────────────────►│ claude_cmd2bus  ├──┼─► m_ctl_* (control packets, §3.8)
 JTAG ─► BUS TDR ───────┤◄────────────────┤ parser, bus FSM ├──┘
                        │ m_rsp_* (bytes) │ CRC, timeouts   │──► op_* handlers (extension opcodes)
                        └─ front ends ────┴─────────────────┘
```

---

## Ports (system clock)

| Port | Dir | Meaning |
|---|---|---|
| `s_cmd_tvalid/tready/tdata[7:0]/tlast` | in | command bytes from the front end; `tlast` = **frame end** (see Framing) |
| `m_rsp_tvalid/tready/tdata[7:0]/tlast` | out | response bytes; `tlast` on the last byte of each response |
| `mem_*` initiator | out / in | to `claude_<proto>_mst_if` (`IP_SPEC_mem_bus_initiator.md`), with `mem_prot` |
| `m_ctl_*` / `s_ctl_*` | out / in | control-stream packets and their responses (`CTL_EN`, `IP_SPEC_ctl_stream.md`) |
| `op_*` handler ports | out / in | extension opcodes, `N_OPS` handlers (same port shape as `jtag_ops`) |
| `dbg_lock_i` | in | lifecycle debug lock: only INFO / STATUS work |
| `busy_o`, `err_o` | out | engine state, for the host IP's status register / interrupt |

`claude_cmd2bus` is a common component with **no register slave**; the host IP (uart2bus,
...) carries the side-band and the standard register block (`IP_SPEC_sideband.md`). Clock
crossings (SCK, TCK) are done by the front ends with `claude_fifo_async`.

---

## Byte order and framing

- **Little-endian** for every multi-byte field and data word (RISC-V and ARM).
- A command is: `CMD` byte, `FLAGS` byte, fields, data, optional `CRC8`.
- **Frame end** (`s_cmd_tlast`) is how a front end tells the engine "the host finished a
  transaction": SPI chip-select deasserted, JTAG Update-DR, I2C STOP. A command cut short by
  a frame end is discarded with status `FRAME`. A frame may hold several commands.
- **Idle timeout** (`IDLE_TMO` cycles, register in the host IP, 0 = off): no byte for that
  long in the middle of a command discards it with `FRAME`. This is UART's resync, together
  with a **break** condition, which the UART front end turns into a frame end.
- After a discard the parser waits for the next `CMD` byte. Hosts resync by: frame end
  (SPI / JTAG / I2C), or a pause longer than `IDLE_TMO` or a break (UART), then `NOP`.

### FLAGS byte (every command)

| Bits | Field | Meaning |
|---|---|---|
| [1:0] | `SIZE` | access size: 0 = byte, 1 = half-word, 2 = word, 3 = reserved |
| [2] | `FIXED` | 1 = same address for every beat (FIFO data registers); 0 = increment by size |
| [3] | `POSTED` | 1 = no response for this command (errors are still recorded, see STATUS) |
| [4] | `CRC` | 1 = a `CRC8` follows the command, and the response carries one |
| [7:5] | `TAG` | echoed in the response, so a host can match responses to commands |

---

## Commands

| CMD | Name | Fields after FLAGS | Response payload |
|---|---|---|---|
| `0x00` | NOP | — | none (no response, ever) |
| `0x01` | WRITE | `ADDR[4]`, `CNT[1]` (beats − 1, up to 256), data `(CNT+1) × size` | — |
| `0x02` | READ | `ADDR[4]`, `CNT[1]` | data `(CNT+1) × size` |
| `0x03` | WRITE_MASK | `ADDR[4]`, `MASK[4]`, `DATA[4]` | — (read-modify-write, word) |
| `0x04` | POLL | `ADDR[4]`, `MASK[4]`, `VALUE[4]`, `TMO[2]` (in 1024-cycle units) | last value read `[4]` (status `TIMEOUT` if never equal) |
| `0x05` | STREAM_WRITE | `ADDR[4]`, `LEN[4]` (bytes, multiple of size), data | `COUNT[4]`, `CRC32[4]` of the data written |
| `0x06` | STREAM_READ | `ADDR[4]`, `LEN[4]` | data `LEN` bytes, then `CRC32[4]` |
| `0x07` | CRC | `ADDR[4]`, `LEN[4]` | `CRC32[4]` of the memory region (verify a download without reading it back) |
| `0x08` | CTL | `LEN[1]` (words − 1), control packet words | response words, if the packet has `RESP` set (§3.8) |
| `0x09` | INFO | — | version, `ADDR_W`, max `CNT`, `CTL_EN`, `N_OPS`, `CRC` support, front-end type |
| `0x0A` | STATUS | — | sticky error flags, first error address, error count, bus-hung flag |
| `0x0B` | CLEAR | — | — (clears STATUS sticky flags) |
| `0x0C` | CONFIG | `ID[1]`, `VALUE[4]` | — (engine settings: default `mem_prot`, bus timeout, POLL unit) |
| `0x0D`–`0x7F` | reserved | — | status `BADCMD` |
| `0x80`–`0xFF` | **extension** | `ARG0[4]`, `ARG1[4]` | `RES0[4]`, `RES1[4]` (see "Extension opcodes") |

- `STREAM_WRITE` / `STREAM_READ` are the fast path (the jtag2bus DMA mode of D5, fast
  program download and memory dump): no per-beat response, 32-bit length, the engine keeps
  the bus busy at the front end's byte rate. The CRC32 lets the host verify the whole
  transfer at once.
- Address width: `ADDR_W` = 32 by default. With `ADDR_W` = 64, `ADDR` fields are 8 bytes
  (INFO reports which).

## Response format

```
SOR  TAG/CMD  payload ...  STATUS  [CRC8]
```

| Field | Meaning |
|---|---|
| `SOR` | start of response, fixed `0xA5` |
| `TAG/CMD` | `TAG` in [7:5], low 5 bits of `CMD` in [4:0] |
| payload | as in the table; **always the full length the command asked for** (failed beats read as 0), so a host that clocks bytes (SPI) always knows how many to read |
| `STATUS` | after the payload, so read data can stream out while the bus is still working |
| `CRC8` | if `FLAGS.CRC` was set: CRC-8 (polynomial `0x07`) over the response |

**STATUS codes:** `0x00` OK, `0x01` BUSERR (a beat got `mem_err`), `0x02` TIMEOUT (bus or
POLL), `0x03` BADCMD, `0x04` FRAME (cut short), `0x05` CRCERR (command CRC wrong; the command
was **not** executed), `0x06` LOCKED (`dbg_lock_i`), `0x07` HUNG (see below), `0x08` EXTERR
(extension handler error). The first failing beat index and address are kept in STATUS
(`0x0A`).

Front ends that cannot wait (SPI: the host clocks bytes out at its own pace) send **`0xFF`
filler** while `m_rsp_*` has nothing; `SOR` = `0xA5` marks where the response starts, and no
response begins with `0xFF`.

### CRC definitions

| CRC | Parameters | Covers |
|---|---|---|
| `CRC8` | CRC-8/SMBUS: polynomial `0x07`, init `0x00`, no reflection, no final XOR | command: `CMD` through the last data byte; response: `SOR` through `STATUS` |
| `CRC32` | CRC-32/ISO-HDLC (IEEE 802.3, zlib): polynomial `0x04C11DB7` reflected (`0xEDB88320`), init `0xFFFFFFFF`, final XOR `0xFFFFFFFF` | the data bytes, in address order (STREAM_WRITE / STREAM_READ / CRC) |

Both are computed by `claude_crc` (§10.5) in the RTL, by `zlib.crc32` / a table in
`claude_cmd2bus.py`, and by `c2b_crc8()` / `c2b_crc32()` in C, and all three are checked
against each other.

### INFO payload (16 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | `VER_MAJOR` |
| 1 | 1 | `VER_MINOR` |
| 2 | 1 | `ADDR_W` (32 or 64) |
| 3 | 1 | `MAX_CNT` (255 = 256 beats) |
| 4 | 2 | `FEATURES`: [0] CTL, [1] CRC, [2] STREAM, [3] POLL, [4] address filter, [5] 64-bit address |
| 6 | 1 | `N_OPS` |
| 7 | 1 | `FRONT_END`: 0 UART, 1 SPI, 2 I2C, 3 JTAG |
| 8 | 4 | `BUS_TMO` (current, cycles) |
| 12 | 4 | reserved (0) |

### STATUS payload (16 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | `ERR_FLAGS` (sticky): [0] BUSERR, [1] TIMEOUT, [2] BADCMD, [3] FRAME, [4] CRCERR, [5] LOCKED, [6] EXTERR, [7] POSTED_ERR (an error in a POSTED command); [8] HUNG (current state, not sticky) |
| 2 | 2 | `ERR_COUNT` (saturating) |
| 4 | 2 | `ERR_BEAT` (beat index of the first error) |
| 6 | 2 | reserved (0) |
| 8 | 8 | `ERR_ADDR` (address of the first error; upper 4 bytes 0 when `ADDR_W` = 32) |

### CONFIG IDs

| ID | Name | Value |
|---|---|---|
| `0x00` | `MEM_PROT` | [2:0] AxPROT encoding (default `0b001`: privileged, secure, data) |
| `0x01` | `BUS_TMO` | cycles (default 65 536, 0 = no timeout) |
| `0x02` | `POLL_UNIT` | cycles per POLL `TMO` unit (default 1024) |
| `0x03` | `IDLE_TMO` | cycles (0 = off; also a register of the host IP) |
| others | — | `BADCMD` |

---

## Bus behavior

0. **Alignment:** `ADDR` must be naturally aligned to `SIZE` (initiator rule 7). A
   misaligned command answers `BUSERR` with no bus access, and STATUS records the address.
1. **One `mem_*` request outstanding** (rule 2), `mem_be` exact per `SIZE` and address
   (initiator rules 6–9). `mem_prot` defaults to privileged, secure, data (CONFIG can
   change it).
2. **A hung target never locks the host.** The `mem_*` protocol cannot abandon a granted
   request, so on `BUS_TMO` cycles (CONFIG, default 65 536) the engine **answers the host**
   with `TIMEOUT` and enters **HUNG**: the outstanding request keeps waiting inside, every
   further bus command answers `HUNG` at once (INFO / STATUS / CLEAR / extension opcodes
   still work), and HUNG ends when the late response finally arrives (and is discarded).
   An extension handler (for example `rst_hold` on the reset controller) is how a host
   recovers a truly dead bus. The bus fabric's own timeout unit (§10.1) is the real fix
   and makes HUNG rare.
3. **POSTED writes**: errors are recorded in STATUS and counted; the host checks with
   STATUS after a batch.
4. **Throughput**: the engine accepts one byte per cycle; bus beats are issued as soon as
   their data bytes are in. The front end is always the limit.

## Control packets (`CTL`, `CTL_EN`, default 1)

The `CTL` command sends the given words as one control-stream packet on `m_ctl_*` and, if
the packet's header has `RESP` set, returns the response words from `s_ctl_*`. This is the
bring-up path with no CPU (plan §3.8): a host configures a DSP chain over UART / SPI / JTAG.

## Extension opcodes (easy to add special operations)

Opcodes `0x80`–`0xFF` go to **op handlers**, with the **same handler port as `jtag_ops`**
(`op_start_i`, `op_code_i[7:0]`, `op_arg0_i`, `op_arg1_i` → `op_done_o`, `op_err_o`,
`op_res0_o`, `op_res1_o`, `IP_SPEC_tap_tdr.md`). One handler can therefore be reached from
JTAG `OPS` **and** from every `cmd2bus` host, and is written once.

- The SoC YAML lists them (`cmd2bus.ops:`, or the shared `ops:` list used by `jtag_ops` too),
  and the generator builds the decode, the docs and the host-library opcode table.
- Opcode with no handler → `BADCMD`. A handler error → `EXTERR` with `RES1` = its error code.
- INFO reports `N_OPS`; opcode `0x80` is reserved for discovery (`RES0` = number of handlers,
  `ARG0` = *n* returns the ID of handler *n*), as in `jtag_ops`.

## Security

- `dbg_lock_i` high: every command except NOP, INFO, STATUS and the extension opcodes the
  lifecycle spec allows answers `LOCKED`, and nothing reaches the bus.
- Optional address filter (`ALLOW_BASE` / `ALLOW_MASK` parameters, per SoC): accesses outside
  the window answer BUSERR without a bus request.

---

## Host library and golden model

- **`claude_cmd2bus.py`** (`IP/common/verification/tools/`): encodes commands and decodes
  responses, with transports for pyserial (uart2bus), SPI (FTDI / spidev), I2C, and
  OpenOCD Tcl (jtag2bus `drscan`). It is the reference model in the testbenches (Python
  generates the byte streams and the expected responses) and the real host tool on the
  boards. The same API on every transport: `read32`, `write32`, `read_block`,
  `write_block`, `poll`, `crc`, `ctl`, `op`, `info`.
- A Tcl version of the encoder for OpenOCD scripts.
- The C library below, for MCU or embedded hosts that drive another chip's uart2bus /
  spi_slave / i2c_slave, and for firmware tests.

## C data structures (user 2026-11-27)

Files: `IP/common/firmware/include/claude_cmd2bus.h` (below) and
`IP/common/firmware/src/claude_cmd2bus.c`. Rules from `.agents/firmware.md`: **pure C99**, no
compiler extensions, no OS dependencies, Doxygen comments, `-fsyntax-only -std=c99` clean with
`arm-none-eabi-gcc` (Cortex-M33) and `riscv-none-elf-gcc`, and the host
`-Wall -Wextra -Werror -pedantic` build.

Design:

- **No packed structs.** C99 has no portable way to pack or fix byte order, so the **wire
  format is defined by byte-offset macros**, and the structs are the **decoded** form.
  `c2b_enc_*()` writes a command into a byte buffer and `c2b_dec_*()` parses a response,
  byte by byte in little-endian order, so the code is correct on any CPU and alignment.
- **Transport-agnostic.** The high-level calls (`c2b_read32()`, `c2b_write_block()`, ...) use
  a `c2b_port_t` holding two function pointers (send bytes, receive bytes) that the user
  writes for UART / SPI / I2C. The library adds framing, tags, CRC, filler skipping and
  status checking.
- **Same names as the Python library** (`read32`, `write_block`, `poll`, `crc`, `ctl`, `op`,
  `info`), so tests and scripts translate one to one.
- Prefix `c2b_` / `C2B_` (the protocol), to keep names short.

```c
/**
 * @file claude_cmd2bus.h
 * @brief claude_cmd2bus byte command protocol: wire format, decoded types, and host API.
 *
 * Pure C99. The wire format is little-endian and defined by byte offsets; the
 * structs below are the decoded form, never overlaid on a byte buffer.
 */
#ifndef CLAUDE_CMD2BUS_H
#define CLAUDE_CMD2BUS_H

#include <stddef.h>
#include <stdint.h>

#define C2B_PROTO_VER_MAJOR  1u
#define C2B_PROTO_VER_MINOR  0u

/* ---- Command codes (CMD byte) ------------------------------------------ */
typedef enum {
    C2B_CMD_NOP          = 0x00,
    C2B_CMD_WRITE        = 0x01,
    C2B_CMD_READ         = 0x02,
    C2B_CMD_WRITE_MASK   = 0x03,
    C2B_CMD_POLL         = 0x04,
    C2B_CMD_STREAM_WRITE = 0x05,
    C2B_CMD_STREAM_READ  = 0x06,
    C2B_CMD_CRC          = 0x07,
    C2B_CMD_CTL          = 0x08,
    C2B_CMD_INFO         = 0x09,
    C2B_CMD_STATUS       = 0x0A,
    C2B_CMD_CLEAR        = 0x0B,
    C2B_CMD_CONFIG       = 0x0C,
    C2B_CMD_EXT_FIRST    = 0x80,  /**< extension opcodes 0x80..0xFF   */
    C2B_CMD_EXT_DISCOVER = 0x80   /**< reserved: handler discovery     */
} c2b_cmd_t;

/* ---- FLAGS byte --------------------------------------------------------- */
#define C2B_FLAGS_SIZE_MASK   0x03u
#define C2B_FLAGS_FIXED       0x04u
#define C2B_FLAGS_POSTED      0x08u
#define C2B_FLAGS_CRC         0x10u
#define C2B_FLAGS_TAG_SHIFT   5u
#define C2B_FLAGS_TAG_MASK    0xE0u
#define C2B_FLAGS(size, tag, extra) \
    ((uint8_t)(((unsigned)(size) & C2B_FLAGS_SIZE_MASK) | \
               (((unsigned)(tag) << C2B_FLAGS_TAG_SHIFT) & C2B_FLAGS_TAG_MASK) | \
               ((unsigned)(extra))))

typedef enum {
    C2B_SIZE_8  = 0,
    C2B_SIZE_16 = 1,
    C2B_SIZE_32 = 2
} c2b_size_t;

/* ---- Response framing --------------------------------------------------- */
#define C2B_SOR             0xA5u  /**< start of response                    */
#define C2B_FILLER          0xFFu  /**< SPI filler while no response is ready */
#define C2B_RSP_TAG_SHIFT   5u
#define C2B_RSP_CMD_MASK    0x1Fu

typedef enum {
    C2B_ST_OK      = 0x00,
    C2B_ST_BUSERR  = 0x01,
    C2B_ST_TIMEOUT = 0x02,
    C2B_ST_BADCMD  = 0x03,
    C2B_ST_FRAME   = 0x04,
    C2B_ST_CRCERR  = 0x05,
    C2B_ST_LOCKED  = 0x06,
    C2B_ST_HUNG    = 0x07,
    C2B_ST_EXTERR  = 0x08
} c2b_status_t;

/* ---- Command field offsets (bytes after CMD, FLAGS; ADDR_W = 32) -------- */
#define C2B_OFF_CMD     0u
#define C2B_OFF_FLAGS   1u
#define C2B_OFF_ADDR    2u                   /* 4 bytes (8 with ADDR_W = 64) */
#define C2B_OFF_CNT     6u                   /* WRITE / READ: 1 byte          */
#define C2B_OFF_LEN     6u                   /* STREAM_* / CRC: 4 bytes       */
#define C2B_OFF_MASK    6u                   /* WRITE_MASK / POLL: 4 bytes    */
#define C2B_OFF_VALUE  10u                   /* WRITE_MASK DATA / POLL VALUE  */
#define C2B_OFF_TMO    14u                   /* POLL: 2 bytes                 */
#define C2B_OFF_ARG0    2u                   /* extension: 4 bytes            */
#define C2B_OFF_ARG1    6u                   /* extension: 4 bytes            */
#define C2B_MAX_BEATS 256u

/* ---- Decoded payloads --------------------------------------------------- */
#define C2B_FEAT_CTL     0x0001u
#define C2B_FEAT_CRC     0x0002u
#define C2B_FEAT_STREAM  0x0004u
#define C2B_FEAT_POLL    0x0008u
#define C2B_FEAT_FILTER  0x0010u
#define C2B_FEAT_ADDR64  0x0020u

typedef enum {
    C2B_FE_UART = 0, C2B_FE_SPI = 1, C2B_FE_I2C = 2, C2B_FE_JTAG = 3
} c2b_front_end_t;

/** INFO response payload (16 bytes on the wire). */
typedef struct {
    uint8_t  ver_major;
    uint8_t  ver_minor;
    uint8_t  addr_w;       /**< 32 or 64                 */
    uint8_t  max_cnt;      /**< 255 = 256 beats          */
    uint16_t features;     /**< C2B_FEAT_*               */
    uint8_t  n_ops;
    uint8_t  front_end;    /**< c2b_front_end_t          */
    uint32_t bus_tmo;      /**< cycles                   */
} c2b_info_t;
#define C2B_INFO_LEN 16u

#define C2B_ERR_BUSERR      0x0001u
#define C2B_ERR_TIMEOUT     0x0002u
#define C2B_ERR_BADCMD      0x0004u
#define C2B_ERR_FRAME       0x0008u
#define C2B_ERR_CRCERR      0x0010u
#define C2B_ERR_LOCKED      0x0020u
#define C2B_ERR_EXTERR      0x0040u
#define C2B_ERR_POSTED      0x0080u
#define C2B_STATE_HUNG      0x0100u  /**< current state, not sticky */

/** STATUS response payload (16 bytes on the wire). */
typedef struct {
    uint16_t err_flags;    /**< C2B_ERR_* | C2B_STATE_HUNG */
    uint16_t err_count;    /**< saturating                 */
    uint16_t err_beat;     /**< beat of the first error    */
    uint64_t err_addr;     /**< address of the first error */
} c2b_bus_status_t;
#define C2B_STATUS_LEN 16u

typedef enum {
    C2B_CFG_MEM_PROT  = 0x00,
    C2B_CFG_BUS_TMO   = 0x01,
    C2B_CFG_POLL_UNIT = 0x02,
    C2B_CFG_IDLE_TMO  = 0x03
} c2b_cfg_id_t;

/** Decoded response header and trailer. */
typedef struct {
    uint8_t      tag;      /**< TAG echoed from the command   */
    uint8_t      cmd_lo;   /**< low 5 bits of CMD             */
    c2b_status_t status;
    uint8_t      crc_ok;   /**< 1 if no CRC was requested or it matched */
} c2b_rsp_t;

/* ---- Low level: encode / decode (no I/O) -------------------------------- */
/** @brief Write a WRITE / READ command into buf. @return bytes written, 0 if buf too small. */
size_t c2b_enc_rw(uint8_t *buf, size_t cap, c2b_cmd_t cmd, uint8_t flags,
                  uint32_t addr, unsigned beats, const uint8_t *wdata);
/** @brief Write any command with 32-bit fields (POLL, STREAM_*, CRC, CONFIG, extension). */
size_t c2b_enc_fields(uint8_t *buf, size_t cap, c2b_cmd_t cmd, uint8_t flags,
                      const uint32_t *fields, unsigned n_fields);
/** @brief Parse SOR, TAG/CMD, payload, STATUS and CRC from buf. @return bytes consumed, 0 if incomplete. */
size_t c2b_dec_rsp(const uint8_t *buf, size_t len, uint8_t flags,
                   uint8_t *payload, size_t payload_len, c2b_rsp_t *rsp);
void   c2b_dec_info(const uint8_t p[C2B_INFO_LEN], c2b_info_t *info);
void   c2b_dec_status(const uint8_t p[C2B_STATUS_LEN], c2b_bus_status_t *st);
uint8_t  c2b_crc8(uint8_t crc, const uint8_t *data, size_t len);   /**< CRC-8/SMBUS      */
uint32_t c2b_crc32(uint32_t crc, const uint8_t *data, size_t len); /**< CRC-32/ISO-HDLC; start with 0 */

/* ---- High level: blocking host API over a user transport ---------------- */
/** User transport. Each returns 0 on success, nonzero on transport error. */
typedef struct {
    int  (*send)(void *ctx, const uint8_t *data, size_t len);
    int  (*recv)(void *ctx, uint8_t *data, size_t len);   /**< exactly len bytes */
    void (*frame_end)(void *ctx);                         /**< CS release / STOP; may be NULL */
    void  *ctx;
    uint8_t use_crc;       /**< 1 = set FLAGS.CRC on every command */
    uint8_t next_tag;      /**< managed by the library             */
} c2b_port_t;

/** Result of a high-level call: c2b_status_t, or a negative library error. */
typedef int c2b_result_t;
#define C2B_E_TRANSPORT  (-1)  /**< send / recv failed                 */
#define C2B_E_PROTOCOL   (-2)  /**< bad SOR, tag mismatch, CRC mismatch */
#define C2B_E_ARG        (-3)  /**< invalid argument                    */

c2b_result_t c2b_info(c2b_port_t *p, c2b_info_t *info);
c2b_result_t c2b_status(c2b_port_t *p, c2b_bus_status_t *st);
c2b_result_t c2b_clear(c2b_port_t *p);
c2b_result_t c2b_config(c2b_port_t *p, c2b_cfg_id_t id, uint32_t value);
c2b_result_t c2b_read32(c2b_port_t *p, uint32_t addr, uint32_t *value);
c2b_result_t c2b_write32(c2b_port_t *p, uint32_t addr, uint32_t value);
c2b_result_t c2b_write_mask(c2b_port_t *p, uint32_t addr, uint32_t mask, uint32_t value);
c2b_result_t c2b_read_block(c2b_port_t *p, uint32_t addr, c2b_size_t size,
                            int fixed, void *dst, unsigned beats);
c2b_result_t c2b_write_block(c2b_port_t *p, uint32_t addr, c2b_size_t size,
                             int fixed, int posted, const void *src, unsigned beats);
c2b_result_t c2b_poll(c2b_port_t *p, uint32_t addr, uint32_t mask, uint32_t value,
                      uint16_t tmo, uint32_t *last);
c2b_result_t c2b_stream_write(c2b_port_t *p, uint32_t addr, const void *src,
                              uint32_t len, uint32_t *crc32);
c2b_result_t c2b_stream_read(c2b_port_t *p, uint32_t addr, void *dst,
                             uint32_t len, uint32_t *crc32);
c2b_result_t c2b_crc(c2b_port_t *p, uint32_t addr, uint32_t len, uint32_t *crc32);
c2b_result_t c2b_ctl(c2b_port_t *p, const uint32_t *pkt, unsigned n_words,
                     uint32_t *rsp, unsigned rsp_words);
c2b_result_t c2b_op(c2b_port_t *p, uint8_t opcode, uint32_t arg0, uint32_t arg1,
                    uint32_t *res0, uint32_t *res1);

#endif /* CLAUDE_CMD2BUS_H */
```

Behavior of the high-level calls:

- Each call encodes one command, sends it, calls `frame_end` (if set), receives until the
  response is complete, skipping `C2B_FILLER` bytes before `SOR`, and checks the tag and CRC.
- Block calls longer than 256 beats are split into several commands; `c2b_stream_*` use
  STREAM_WRITE / STREAM_READ and compare the returned CRC-32 with the one computed locally
  (`C2B_E_PROTOCOL` on mismatch).
- A device STATUS other than OK is returned as is (positive), so callers can tell bus
  errors from transport errors.
- `c2b_dec_*` and `c2b_enc_*` touch no I/O and have no state, so they also serve as the
  reference in firmware unit tests and in a DPI-C checker if a bench needs one.

## What the front ends document

The physical protocol, how frame end is signalled (CS, STOP, Update-DR, break), whether
`0xFF` filler is used, the maximum byte rate and its relation to the system clock.

---

## Verification

- **Engine bench** (directed + UVM), driven by `claude_cmd2bus.py`, against
  `claude_mem_model` behind each `claude_<proto>_mst_if`:
  every command and `SIZE` / `FIXED` / `POSTED` / `CRC` / `TAG` combination; random command
  mixes compared with the Python model; bus errors on chosen beats; a target that never
  answers (HUNG entry and exit, host still served); frame cut at every byte position; idle
  timeout; CRC errors (command not executed); `dbg_lock_i`; address filter; `CTL` against
  the control-stream BFM; extension opcodes with handlers of 0, 1 and many cycles.
- **Formal**: the master-role `claude_mem_fv` on the `mem_*` port (rules 1–9); the parser
  always returns to idle after a frame end; every non-POSTED, non-NOP command gets exactly
  one response.
- **Each front end** (uart2bus, spi_slave, i2c_slave, jtag2bus): the same command suite
  through its pins, using its line model / JTAG BFM; frame-end handling; full-speed byte
  rate.
- **C library**: cross-compile checks (Cortex-M33, RISC-V, `-std=c99`); host unit tests that
  encode every command with C and with `claude_cmd2bus.py` and compare the bytes, decode
  every response kind (including filler, CRC errors, tag mismatch), and check
  `c2b_crc8` / `c2b_crc32` against the Python and RTL CRCs on the same vectors; a host build
  that runs the high-level calls against the Python model through a pipe transport.
- **On the boards** (SoC-0): the Python host library over UART, SPI and JTAG reads and
  writes SRAM and peripherals, downloads an image with STREAM_WRITE and verifies it with
  CRC.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | misaligned commands answer BUSERR |
