// sram_tb_pkg.sv — Configuration table and shadow memory for tb_sram_<proto>.
//
// SB_*  : one index per SRAM instance (its side-band signals, its reference
//         model, and its storage in the shadow memory; both ports of a dual
//         port share one).
// SL_*  : one index per bus-visible slave port (a dual port has two).
// slv[] : what the tests need to know about each slave port; filled by
//         tb_init() in sram_tb_helpers.sv (some fields depend on TECH).
// shadow: expected contents, one byte per storage byte. Storage byte
//         `idx * WIDTH/8 + lane` of a port is the same byte for both ports of
//         a dual port (little-endian packing), so the shadow needs no
//         knowledge of the width ratio. Bytes never written are X.

package sram_tb_pkg;

  // sram_pkg::TECH_* values (the bench does not import the RTL package, so it
  // runs unchanged on the VHDL tops)
  localparam int unsigned TB_TECH_GENERIC = 0;
  localparam int unsigned TB_TECH_SAED90  = 3;
  localparam int unsigned TB_TECH_SAED32  = 4;
  localparam int unsigned TB_TECH_SAED14  = 5;
  localparam int unsigned TB_TECH_SKY130  = 6;

  // SRAM instances
  localparam int SB_S32  = 0;
  localparam int SB_S32E = 1;
  localparam int SB_DP0  = 2;
  localparam int SB_S8   = 3;
  localparam int SB_S16  = 4;
  localparam int SB_S16W = 5;
  localparam int SB_DP1  = 6;
  localparam int SB_S24  = 7;
  localparam int SB_S24B = 8;
  localparam int SB_S64  = 9;
  localparam int SB_S32P = 10;
  localparam int SB_S32Q = 11;
  localparam int SB_DP2  = 12;
  localparam int SB_DP3  = 13;
  localparam int NSB     = 14;

  // Slave ports
  localparam int SL_S32  = 0;
  localparam int SL_S32E = 1;
  localparam int SL_DP0A = 2;
  localparam int SL_S8   = 3;
  localparam int SL_DP0B = 4;
  localparam int SL_S16  = 5;
  localparam int SL_S16W = 6;
  localparam int SL_DP1A = 7;
  localparam int SL_S24  = 8;
  localparam int SL_S24B = 9;
  localparam int SL_S64  = 10;
  localparam int SL_DP1B = 11;
  localparam int SL_S32P = 12;
  localparam int SL_S32Q = 13;
  localparam int SL_DP2A = 14;
  localparam int SL_DP2B = 15;
  localparam int SL_DP3A = 16;
  localparam int SL_DP3B = 17;
  localparam int NSL     = 18;

  // Masters: 0/1 X32 (CPU/DMA), 2 X8, 3 X16, 4 X24, 5 X64, 6/7 direct
  localparam int NM = 8;

  typedef struct {
    string       name;     // short name in reports
    int          m;        // master that reaches it
    logic [31:0] base;     // window base address
    int          w;        // data width (bits)
    int          depth;    // words seen by this port
    bit          ecc;      // ECC_EN
    bit          be;       // byte-lane writes
    bit          pwe;      // BYTE_EN = 0: partial write is an error
    bit          ro;       // read-only port (SKY130 port B)
    int          rl;       // READ_LATENCY of this port
    int          npd;      // power domains (BANK_PG ? NUM_BANKS : 1)
    bit          bist;     // BIST_EN
    int          sb;       // SRAM instance
    bit          port_b;   // port B of a dual port
    bit          on_b;     // runs on clk_b
    int          peer;     // other port of a dual port (-1: none)
    bit          pg;       // PWR_GATE
  } slv_t;

  slv_t slv [NSL];

  // Shadow memory: [instance][storage byte]
  logic [7:0] shadow [NSB][int];

  function automatic logic [7:0] sh_byte(int sb, int pos);
    if (shadow[sb].exists(pos)) return shadow[sb][pos];
    return 8'hxx;
  endfunction

endpackage : sram_tb_pkg
