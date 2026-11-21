// sram_uvm_cfg.sv — What the UVM bench was built with (Step 6).
//
// tb_sram_uvm.sv fills one object from its compile-time configuration and
// publishes it in uvm_config_db ("cfg"); every component reads it. Index
// [0] is port A, [1] port B (dual port only).

`ifndef SRAM_UVM_CFG_SV
`define SRAM_UVM_CFG_SV

class sram_uvm_cfg extends uvm_object;
  `uvm_object_utils(sram_uvm_cfg)

  string       proto;          // "apb", "ahb", "axi4l", "wb"
  string       cfg_name;       // "base", "full", "dp"
  bit          vhdl;           // VHDL DUT
  int unsigned tech;           // sram_pkg::TECH_* value

  bit          dual_port;
  bit          common_clk;     // dual port: one clock
  int unsigned width   [2];    // data width (bits)
  int unsigned depth   [2];    // words
  int unsigned stride  [2];    // bytes of address per word (power of two)
  int unsigned rl      [2];    // READ_LATENCY
  bit          byte_en [2];
  bit          read_only [2];  // SKY130 port B
  bit          ecc;
  bit          bist;
  bit          pwr_gate;
  int unsigned npd;            // power domains
  int unsigned total_bytes;    // storage bytes (both ports see the same)
  realtime     clk_period [2];

  function new(string name = "sram_uvm_cfg");
    super.new(name);
  endfunction

  function int unsigned nports();
    return dual_port ? 2 : 1;
  endfunction

  // Both ports on one clock (exact cycle relations between ports hold).
  function bit single_clk();
    return !dual_port || common_clk;
  endfunction

  function int unsigned bytes_per_word(int unsigned p);
    return width[p] / 8;
  endfunction

  // Port p's window: DEPTH * stride bytes.
  function int unsigned span(int unsigned p);
    return depth[p] * stride[p];
  endfunction

  // Storage byte of port p, word index idx, lane l (little-endian packing:
  // both ports address the same bytes).
  function int unsigned storage_byte(int unsigned p, int unsigned idx, int unsigned l);
    return idx * bytes_per_word(p) + l;
  endfunction

  function int unsigned domain_of(int unsigned pos);
    return pos / (total_bytes / npd);
  endfunction

  // Largest AHB HSIZE of port p.
  function int unsigned max_size(int unsigned p);
    return $clog2(bytes_per_word(p));
  endfunction

  function string convert2string();
    return $sformatf({"%s/%s%s tech=%0d A=%0dx%0d RL%0d", "%s ecc=%0b bist=%0b npd=%0d"},
                     proto, cfg_name, vhdl ? "(vhdl)" : "", tech, width[0], depth[0], rl[0],
                     dual_port ? $sformatf(" B=%0dx%0d RL%0d ro=%0b cc=%0b", width[1],
                                           depth[1], rl[1], read_only[1], common_clk) : "",
                     ecc, bist, npd);
  endfunction

endclass : sram_uvm_cfg

`endif // SRAM_UVM_CFG_SV
