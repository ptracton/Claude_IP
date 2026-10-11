-- bus_matrix_arb_fv_top.vhd — VC Formal harness for bus_matrix_arb on its own (VHDL-2008).
--
-- Mirrors bus_matrix_arb_fv_top.sv: both arbitration modes with 4 masters and
-- free-running inputs.
--   u_fp  fixed priority, M_PRIORITY = {M3:1, M2:0, M1:1, M0:2}
--   u_rr  round robin

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_arb_fv_top is
  port (
    clk     : in  std_ulogic;
    rst_n   : in  std_ulogic;
    fp_req  : in  std_ulogic_vector(3 downto 0);
    fp_done : in  std_ulogic;
    fp_gnt  : out std_ulogic_vector(3 downto 0);
    rr_req  : in  std_ulogic_vector(3 downto 0);
    rr_done : in  std_ulogic;
    rr_gnt  : out std_ulogic_vector(3 downto 0)
  );
end entity bus_matrix_arb_fv_top;

architecture rtl of bus_matrix_arb_fv_top is
begin

  u_fp : entity work.bus_matrix_arb(rtl)
    generic map (
      NUM_MASTERS => 4,
      ARB_MODE    => 0,
      M_PRIORITY  => (63 downto 16 => '0') & x"1012"
    )
    port map (
      clk   => clk,
      rst_n => rst_n,
      req   => fp_req,
      done  => fp_done,
      gnt   => fp_gnt
    );

  u_rr : entity work.bus_matrix_arb(rtl)
    generic map (
      NUM_MASTERS => 4,
      ARB_MODE    => 1,
      M_PRIORITY  => (others => '0')
    )
    port map (
      clk   => clk,
      rst_n => rst_n,
      req   => rr_req,
      done  => rr_done,
      gnt   => rr_gnt
    );

end architecture rtl;
