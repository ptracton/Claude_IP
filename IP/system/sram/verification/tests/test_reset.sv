// test_reset.sv — Every SRAM answers after reset.
//
// Every slave port (both ports of a dual port) reads its first and last word
// with an OKAY response; ECC arrays read zero (cleared after reset), the
// others are unknown and only the response is checked. Every power domain
// acknowledges RUN and no instance is busy. Then reset is applied again
// with data in every SRAM: ECC arrays are cleared again, every domain comes
// back in RUN and every port answers.

task automatic test_reset();
  test_start("test_reset");
  for (int sb = 0; sb < NSB; sb++) begin
    for (int d = 0; d < slv[a_slave[sb]].npd; d++) begin
      chk(ack(sb, d) === RUN, $sformatf("%s domain %0d ack RUN", slv[a_slave[sb]].name, d));
    end
    chk(busy[sb] === 1'b0, $sformatf("%s not busy", slv[a_slave[sb]].name));
  end
  row("every power domain acknowledges RUN, no instance busy");
  for (int s = 0; s < NSL; s++) begin
    rd_chk(s, 0, 0, "reset");
    rd_chk(s, slv[s].depth - 1, 0, "reset");
    row($sformatf("%-6s first and last word read OKAY%s", slv[s].name,
                  slv[s].ecc ? ", zero (ECC clear)" : ""));
  end
  // Reset again, with data written everywhere.
  for (int s = 0; s < NSL; s++) if (!slv[s].ro) wr(s, 1, rnd(s));
  reset_all();
  for (int sb = 0; sb < NSB; sb++) begin
    for (int d = 0; d < slv[a_slave[sb]].npd; d++) begin
      chk(ack(sb, d) === RUN, $sformatf("%s domain %0d RUN after the second reset",
                                        slv[a_slave[sb]].name, d));
    end
  end
  for (int s = 0; s < NSL; s++) rd_chk(s, 1, 0, "second reset");
  row("second reset with data: ECC arrays cleared again, every port answers");
  test_done("test_reset");
endtask
