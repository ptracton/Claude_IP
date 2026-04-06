-- bus_matrix_arb.vhd — Bus Matrix arbitration for one slave port (VHDL-2008).
--
-- Implements fixed-priority and round-robin arbitration.
-- One instance per slave. Configuration entirely via generics.
-- Mirrors bus_matrix_arb.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_arb is
  generic (
    NUM_MASTERS : positive := 2;  -- 1-16 active masters
    ARB_MODE    : natural  := 0;  -- 0=fixed-priority, 1=round-robin
    -- Flat-packed priorities: master i at bits [(i+1)*4-1 : i*4]
    -- Maximum 16 masters = 64 bits.
    M_PRIORITY  : std_ulogic_vector(16*4-1 downto 0) := (others => '0')
  );
  port (
    clk       : in  std_ulogic;
    rst_n     : in  std_ulogic;
    req       : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    valid_trx : in  std_ulogic;
    slv_gnt   : in  std_ulogic;
    gnt       : out std_ulogic_vector(NUM_MASTERS - 1 downto 0)
  );
end entity bus_matrix_arb;

architecture rtl of bus_matrix_arb is

  function clog2(val : positive) return positive is
    variable v : positive := 1;
    variable n : natural  := 0;
  begin
    while v < val loop
      v := v * 2;
      n := n + 1;
    end loop;
    if n = 0 then return 1; end if;
    return n;
  end function clog2;

  constant PTR_W : positive := clog2(NUM_MASTERS);

  signal fp_gnt      : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal rr_ptr_q    : unsigned(PTR_W - 1 downto 0);
  signal rr_gnt_q    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal rr_gnt_next : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal gnt_next    : std_ulogic_vector(NUM_MASTERS - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- Fixed-priority (combinational)
  -- -------------------------------------------------------------------------
  p_fp : process(req) is
    variable beaten : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    variable pi, pj : unsigned(3 downto 0);
  begin
    beaten := (others => '0');
    for i in 0 to NUM_MASTERS - 1 loop
      pi := unsigned(M_PRIORITY((i+1)*4-1 downto i*4));
      for j in 0 to NUM_MASTERS - 1 loop
        if j /= i and req(j) = '1' then
          pj := unsigned(M_PRIORITY((j+1)*4-1 downto j*4));
          if pj < pi then
            beaten(i) := '1';
          elsif pj = pi and j < i then
            beaten(i) := '1';
          end if;
        end if;
      end loop;
    end loop;
    fp_gnt <= req and not beaten;
  end process p_fp;

  -- -------------------------------------------------------------------------
  -- Round-robin next grant (combinational)
  -- -------------------------------------------------------------------------
  p_rr_comb : process(req, rr_ptr_q) is
    variable result : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
    variable found  : boolean;
    variable idx    : integer;
  begin
    result := (others => '0');
    found  := false;
    if req /= (req'range => '0') then
      -- First pass: above rr_ptr_q
      for k in 0 to NUM_MASTERS - 1 loop
        idx := k;
        if idx > to_integer(rr_ptr_q) and req(idx) = '1' and not found then
          result(idx) := '1';
          found       := true;
        end if;
      end loop;
      -- Second pass (wrap): 0..rr_ptr_q
      if not found then
        for k in 0 to NUM_MASTERS - 1 loop
          idx := k;
          if idx <= to_integer(rr_ptr_q) and req(idx) = '1' and not found then
            result(idx) := '1';
            found       := true;
          end if;
        end loop;
      end if;
    end if;
    rr_gnt_next <= result;
  end process p_rr_comb;

  p_rr_reg : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        rr_ptr_q <= (others => '0');
        rr_gnt_q <= (others => '0');
      elsif valid_trx = '0' then
        rr_gnt_q <= rr_gnt_next;
        if rr_gnt_next /= (rr_gnt_next'range => '0') then
          for k in 0 to NUM_MASTERS - 1 loop
            if rr_gnt_next(k) = '1' then
              rr_ptr_q <= to_unsigned(k, PTR_W);
            end if;
          end loop;
        end if;
      end if;
    end if;
  end process p_rr_reg;

  -- -------------------------------------------------------------------------
  -- Mux and registered output
  -- -------------------------------------------------------------------------
  gnt_next <= (others => '0') when (valid_trx = '1' and slv_gnt = '1') else
              rr_gnt_q        when ARB_MODE /= 0 else
              fp_gnt;

  p_gnt_reg : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        gnt <= (others => '0');
      else
        gnt <= gnt_next;
      end if;
    end if;
  end process p_gnt_reg;

end architecture rtl;
