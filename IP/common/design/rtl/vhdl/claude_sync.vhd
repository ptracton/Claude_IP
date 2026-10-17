-- claude_sync.vhd — Multi-flop synchronizer for level signals.
--
-- VHDL-2008 twin of claude_sync.sv; behaviour is identical.
-- Each bit of d_i (from another clock domain) passes through STAGES flops
-- on clk. Bits are synchronized independently, so a multi-bit d_i must be
-- a set of unrelated levels (or change one bit at a time, e.g. Gray code).
-- The source must hold each level for longer than STAGES + 1 destination
-- cycles to be seen. Synchronous active-low reset to RST_VAL.
--
-- CDC: the first flop (stage_q(0)) is the metastability stage; waive the
-- crossing onto it in CDC lint.

library ieee;
use ieee.std_logic_1164.all;

entity claude_sync is
  generic (
    WIDTH   : positive   := 1;   -- independent bits
    STAGES  : positive   := 2;   -- flops per bit (>= 2)
    RST_VAL : std_ulogic := '0'  -- reset value of every bit
  );
  port (
    clk   : in  std_ulogic;                            -- destination clock
    rst_n : in  std_ulogic;                            -- synchronous active-low reset
    d_i   : in  std_ulogic_vector(WIDTH - 1 downto 0); -- asynchronous levels
    q_o   : out std_ulogic_vector(WIDTH - 1 downto 0)  -- synchronized levels
  );
end entity claude_sync;

architecture rtl of claude_sync is

  type stage_t is array (0 to STAGES - 1) of std_ulogic_vector(WIDTH - 1 downto 0);

  signal stage_q : stage_t;

begin

  assert_stages_a : assert STAGES >= 2
      report "claude_sync: STAGES must be >= 2" severity failure;

  -- Synchronizer chain.
  p_sync : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        stage_q <= (others => (others => RST_VAL));
      else
        stage_q(0) <= d_i;
        for i in 1 to STAGES - 1 loop
          stage_q(i) <= stage_q(i - 1);
        end loop;
      end if;
    end if;
  end process p_sync;

  q_o <= stage_q(STAGES - 1);

end architecture rtl;
