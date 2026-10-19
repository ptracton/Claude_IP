// test_access.sv — Aligned, sub-word and unaligned accesses.
//
// For every writable slave port:
//   - aligned: every HSIZE up to the bus width at every naturally aligned
//     offset of a word, written then read back at the same size and as a
//     full word (24-bit buses: lanes 0..2, a halfword at offset 2 is lane 2)
//   - sparse strobes (AHB5 HWSTRB) on full-word writes: every lane pattern
//     of the word (all 2**lanes patterns; random ones on the 64-bit bus)
//   - unaligned address (AHB only): AHB transfers are naturally aligned, so
//     the lanes come from the aligned block holding HADDR (documented
//     behaviour, same at the bus_matrix and at the SRAM); checked for a
//     halfword at offset 1 and a word at offset 2. APB / AXI4-Lite / WB have
//     no size signal: the BFM sends a sub-word transfer as byte strobes /
//     selects, and reads return the whole word
//   - unaligned software access: a word-sized store / load at every byte
//     offset, split into the legal byte / halfword transfers a CPU bus
//     interface would issue, including ones that cross into the next word
// BYTE_EN = 0 ports: partial writes get ERROR and change nothing (s16,
// dp1.B) or write the whole word from HWDATA (s16w); sub-word reads work.
// ECC ports: every sub-word write is a read-modify-write.

// Split a store/load of n bytes at byte offset off into aligned transfers.
task automatic unaligned(input int s, input int off, input int n, input bit we,
                         input logic [63:0] data, input string what);
  int         o, left, sz, k;
  logic [7:0] b;
  o    = off;
  left = n;
  k    = 0;
  while (left > 0) begin
    // Largest naturally aligned size that fits and is within the bus word.
    sz = 0;
    while ((1 << (sz + 1)) <= left && (o % (1 << (sz + 1))) == 0 &&
           (1 << (sz + 1)) <= (1 << offw(s)) &&
           ((o & ((1 << offw(s)) - 1)) + (1 << (sz + 1))) <= nb(s)) sz++;
    // Place the bytes on their lanes.
    begin
      logic [63:0] bus;
      bus = '0;
      for (int i = 0; i < (1 << sz); i++) begin
        b = data[8*(k + i) +: 8];
        bus[8*((o & ((1 << offw(s)) - 1)) + i) +: 8] = b;
      end
      sub(s, o, 3'(sz), we, bus, what);
    end
    o    += (1 << sz);
    k    += (1 << sz);
    left -= (1 << sz);
    // Skip the unused lane(s) of a non-power-of-two word (24-bit: lane 3).
    if ((o & ((1 << offw(s)) - 1)) >= nb(s)) o = (o | ((1 << offw(s)) - 1)) + 1;
  end
endtask

task automatic test_access();
  int          s, idx, npat, base;
  logic [63:0] v, rd;
  logic        er;
  logic [7:0]  st;
  test_start("test_access");
  for (s = 0; s < NSL; s++) begin
    if (slv[s].ro) continue;
    idx  = slv[s].depth / 2 + 3;
    base = woff(s, idx);
    // Aligned sizes at every aligned offset.
    for (int sz = 0; sz <= offw(s); sz++) begin
      for (int o = 0; o < nb(s); o += (1 << sz)) begin
        wr(s, idx, rnd(s));
        v = rnd(s);
        sub(s, base + o, 3'(sz), 1'b1, v, "aligned");
        sub(s, base + o, 3'(sz), 1'b0, '0, "aligned");
        rd_chk(s, idx, 0, "aligned full");
      end
    end
    row($sformatf("%-6s W=%0d every HSIZE at every aligned offset%s", slv[s].name, slv[s].w,
                  !slv[s].be ? (slv[s].pwe ? " (partial = ERROR)" : " (partial = full word)") :
                  (slv[s].ecc && cw_bytes(s) > 1) ? " (sub-word = RMW)" : ""));
    // Sparse strobes.
    npat = (nb(s) <= 4) ? (1 << nb(s)) : 64;
    for (int p = 0; p < npat; p++) begin
      st = (nb(s) <= 4) ? 8'(p) : 8'($urandom);
      wr(s, idx + 1, rnd(s));
      wr(s, idx + 1, rnd(s), st, 0, "strobes");
      rd_chk(s, idx + 1, 0, "strobes");
    end
    row($sformatf("%-6s %0d write-strobe patterns", slv[s].name, npat));
    // Unaligned HADDR (aligned down to the transfer's natural block). AHB
    // only: the other buses have no size signal, their lanes are the strobes.
    if (IS_AHB && nb(s) >= 2) begin
      wr(s, idx, rnd(s));
      v = rnd(s);
      sub(s, base + 1, 3'd1, 1'b1, v, "unaligned addr");
      rd_chk(s, idx, 0, "unaligned addr");
    end
    if (IS_AHB && nb(s) >= 4) begin
      wr(s, idx, rnd(s));
      v = rnd(s);
      sub(s, base + 2, 3'd2, 1'b1, v, "unaligned addr");
      rd_chk(s, idx, 0, "unaligned addr");
    end
    // Unaligned software stores / loads of a CPU word (4 bytes, or the bus
    // width if narrower) at every byte offset of two words.
    for (int o = 0; o < 2 * nb(s); o++) begin
      int n;
      n = (nb(s) < 4) ? 2 : 4;
      wr(s, idx, rnd(s));
      wr(s, idx + 1, rnd(s));
      wr(s, idx + 2, rnd(s));
      v = {$urandom, $urandom};
      unaligned(s, base + (o / nb(s)) * (1 << offw(s)) + (o % nb(s)), n, 1'b1, v, "unaligned");
      unaligned(s, base + (o / nb(s)) * (1 << offw(s)) + (o % nb(s)), n, 1'b0, '0, "unaligned");
      rd_chk(s, idx, 0, "unaligned");
      rd_chk(s, idx + 1, 0, "unaligned");
      rd_chk(s, idx + 2, 0, "unaligned");
    end
    row($sformatf("%-6s %ssplit unaligned stores/loads", slv[s].name,
                  IS_AHB ? "unaligned HADDR and " : ""));
  end
  test_done("test_access");
endtask
