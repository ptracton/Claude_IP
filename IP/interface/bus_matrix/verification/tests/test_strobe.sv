// test_strobe.sv — Byte strobes are routed: each lane is written on its own
// through the matrix and the untouched lanes keep their value.

task automatic test_strobe;
  logic [31:0] rdata;
  logic [31:0] addr;
  begin
    test_start("test_strobe");
    addr = slv_addr(1, 12'h100);
    u_m0.write_reg(addr, 32'h0000_0000, 4'hF);
    u_m0.write_reg(addr, 32'h1111_11AA, 4'b0001);
    u_m1.write_reg(addr, 32'h2222_BB22, 4'b0010);
    u_m0.write_reg(addr, 32'h33CC_3333, 4'b0100);
    u_m1.write_reg(addr, 32'hDD44_4444, 4'b1000);
    u_m0.read_reg(addr, rdata);
    check_eq(rdata, 32'hDDCC_BBAA, "one lane per write, both masters");
    u_m1.write_reg(addr, 32'h0000_0000, 4'b0000);
    u_m1.read_reg(addr, rdata);
    check_eq(rdata, 32'hDDCC_BBAA, "all-zero strobe writes nothing");
    test_done("test_strobe");
  end
endtask
