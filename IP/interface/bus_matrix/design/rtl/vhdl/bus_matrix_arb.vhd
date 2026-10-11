-- bus_matrix_arb.vhd — Bus Matrix arbiter for one slave port (VHDL-2008).
--
-- One instance per slave. Picks one requesting master when the slave is free
-- and locks that grant until the transaction completes, so a higher-priority
-- request can never take the slave away mid-transaction.
--
--   Fixed priority (ARB_MODE=0): lowest M_PRIORITY value wins; ties go to
--     the lower master index.
--   Round robin   (ARB_MODE=1): the first requester after the last granted
--     master wins (master 0 is first after reset).
--
-- Grant timing: gnt is registered. It is set on the clock edge after a
-- request is seen with the slave free, held while the owner keeps requesting,
-- and cleared on the edge where done is high (or the owner stops
-- requesting). No new grant is made on the edge that releases one.
-- Mirrors bus_matrix_arb.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_matrix_arb is
  generic (
    NUM_MASTERS : positive := 2;  -- 1-16 active masters
    ARB_MODE    : natural  := 0;  -- 0=fixed-priority, 1=round-robin
    -- Master i priority at bits (i*4+3 downto i*4), lower value = higher
    -- priority; maximum-width (16 masters), only NUM_MASTERS entries used.
    M_PRIORITY  : std_ulogic_vector(16 * 4 - 1 downto 0) := (others => '0')
  );
  port (
    clk   : in  std_ulogic;                                   -- system clock
    rst_n : in  std_ulogic;                                   -- synchronous active-low reset
    req   : in  std_ulogic_vector(NUM_MASTERS - 1 downto 0);  -- master i requests this slave
    done  : in  std_ulogic;                                   -- owner's transaction completes
    gnt   : out std_ulogic_vector(NUM_MASTERS - 1 downto 0)   -- one-hot grant (registered)
  );
end entity bus_matrix_arb;

architecture rtl of bus_matrix_arb is

  constant ONE : unsigned(NUM_MASTERS - 1 downto 0) := to_unsigned(1, NUM_MASTERS);

  signal pick        : std_ulogic_vector(NUM_MASTERS - 1 downto 0);  -- one-hot winner
  signal take        : std_ulogic;                    -- make a new grant on this edge
  signal gnt_q       : std_ulogic_vector(NUM_MASTERS - 1 downto 0);
  signal busy        : std_ulogic;                    -- a grant is held
  signal owner_req   : std_ulogic;                    -- the granted master still requests
  signal release_gnt : std_ulogic;                    -- drop the grant on this edge

begin

  gen_fp : if ARB_MODE = 0 generate
    -- -----------------------------------------------------------------------
    -- Fixed priority: master i wins unless another requester j beats it with
    -- a strictly lower priority value, or the same value and a lower index.
    -- -----------------------------------------------------------------------
    gen_m : for gi in 0 to NUM_MASTERS - 1 generate
      signal beats : std_ulogic_vector(NUM_MASTERS - 1 downto 0);  -- j beats master i
    begin
      gen_cmp : for gj in 0 to NUM_MASTERS - 1 generate
        gen_lo : if gj < gi generate
          beats(gj) <= req(gj) when unsigned(M_PRIORITY(gj * 4 + 3 downto gj * 4)) <=
                                    unsigned(M_PRIORITY(gi * 4 + 3 downto gi * 4)) else '0';
        end generate gen_lo;
        gen_hi : if gj > gi generate
          beats(gj) <= req(gj) when unsigned(M_PRIORITY(gj * 4 + 3 downto gj * 4)) <
                                    unsigned(M_PRIORITY(gi * 4 + 3 downto gi * 4)) else '0';
        end generate gen_hi;
        gen_self : if gj = gi generate
          beats(gj) <= '0';
        end generate gen_self;
      end generate gen_cmp;

      pick(gi) <= req(gi) when beats = (beats'range => '0') else '0';
    end generate gen_m;
  end generate gen_fp;

  gen_rr : if ARB_MODE /= 0 generate
    -- -----------------------------------------------------------------------
    -- Round robin: the lowest requester above the last granted master, else
    -- the lowest requester overall (wrap). last_q is one-hot; resetting it to
    -- the top master makes master 0 first after reset.
    -- -----------------------------------------------------------------------
    signal last_q : unsigned(NUM_MASTERS - 1 downto 0);  -- one-hot last granted master
    signal above  : unsigned(NUM_MASTERS - 1 downto 0);  -- masters strictly above last_q
    signal req_u  : unsigned(NUM_MASTERS - 1 downto 0);
    signal req_hi : unsigned(NUM_MASTERS - 1 downto 0);  -- requesters above last_q
  begin
    req_u  <= unsigned(req);
    above  <= not ((shift_left(last_q, 1)) - ONE);
    req_hi <= req_u and above;
    pick   <= std_ulogic_vector(req_hi and ((not req_hi) + ONE)) when req_hi /= (req_hi'range => '0') else
              std_ulogic_vector(req_u and ((not req_u) + ONE));

    p_last : process (clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          last_q <= shift_left(ONE, NUM_MASTERS - 1);
        elsif take = '1' then
          last_q <= unsigned(pick);
        end if;
      end if;
    end process p_last;
  end generate gen_rr;

  -- -------------------------------------------------------------------------
  -- Grant lock
  -- -------------------------------------------------------------------------
  busy        <= '1' when gnt_q /= (gnt_q'range => '0') else '0';
  owner_req   <= '1' when (gnt_q and req) /= (gnt_q'range => '0') else '0';
  release_gnt <= busy and (done or not owner_req);
  take        <= '1' when busy = '0' and req /= (req'range => '0') else '0';

  p_gnt : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        gnt_q <= (others => '0');
      elsif release_gnt = '1' then
        gnt_q <= (others => '0');
      elsif take = '1' then
        gnt_q <= pick;
      end if;
    end if;
  end process p_gnt;

  gnt <= gnt_q;

end architecture rtl;
