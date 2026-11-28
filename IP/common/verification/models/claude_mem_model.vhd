-- claude_mem_model.vhd — Behavioral memory that is a target on the Claude memory bus (mem_*).
--
-- Testbench only (not synthesizable). VHDL-2008 twin of claude_mem_model.sv for pure-VHDL
-- benches (GHDL); same timing behaviour and the same xorshift32 random generator, so a
-- VHDL and an SV bench with the same seed see the same delays. Specified in
-- .agents/IP_SPEC_mem_bus_initiator.md (verification plan, "claude_mem_model").
--
-- Behaviour:
--   Storage: SIZE bytes from address 0, word index = address bits above the byte offset,
--   wrapping (SIZE / (DATA_W / 8) must be a power of two). Contents start at 0.
--   Writes merge byte lanes by mem_be; reads return the whole word.
--   Errors: when ERR_MSB = 1, any access with address bit ADDR_W-1 set answers mem_err = 1
--   (a failed write is dropped, failed read data is 0).
--   Timing (input ports, may change at any time):
--     min_gnt / max_gnt  cycles a request waits for mem_gnt: random in [min, max]
--                        (0 / 0 = grant in the request cycle)
--     min_rsp / max_rsp  extra cycles after the cycle following the grant (0 / 0 = next cycle)
--   mem_rdata / mem_err are 'X' outside the response cycle.
--   Checks on the initiator (counted in proto_errors and reported): rule 1 (request held,
--   payload stable until granted), rule 2 (no request while one is outstanding or in the
--   response cycle), rule 9 (mem_be not all zeros).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity claude_mem_model is
  generic (
    DATA_W  : positive := 32;
    ADDR_W  : positive := 32;
    SIZE    : positive := 4096;  -- bytes
    ERR_MSB : natural  := 1;     -- 1 = address bit ADDR_W-1 set is an error region
    SEED    : natural  := 1
  );
  port (
    clk          : in  std_ulogic;
    rst_n        : in  std_ulogic;
    mem_req      : in  std_ulogic;
    mem_gnt      : out std_ulogic;
    mem_we       : in  std_ulogic;
    mem_addr     : in  std_ulogic_vector(ADDR_W - 1 downto 0);
    mem_be       : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);
    mem_wdata    : in  std_ulogic_vector(DATA_W - 1 downto 0);
    mem_rvalid   : out std_ulogic;
    mem_rdata    : out std_ulogic_vector(DATA_W - 1 downto 0);
    mem_err      : out std_ulogic;
    min_gnt      : in  natural := 0;
    max_gnt      : in  natural := 0;
    min_rsp      : in  natural := 0;
    max_rsp      : in  natural := 0;
    proto_errors : out natural
  );
end entity claude_mem_model;

architecture sim of claude_mem_model is

  constant STRB_W : positive := DATA_W / 8;

  function clog2(n : positive) return natural is
  begin
    for i in 0 to 30 loop
      if 2 ** i >= n then
        return i;
      end if;
    end loop;
    return 31;
  end function;

  constant OFF_W : natural  := clog2(STRB_W);
  constant WORDS : positive := SIZE / STRB_W;
  constant IDX_W : natural  := clog2(WORDS);

  type mem_t is array (0 to WORDS - 1) of std_ulogic_vector(DATA_W - 1 downto 0);

  signal gnt_i       : std_ulogic;
  signal rvalid_q    : std_ulogic := '0';
  signal outstanding : std_ulogic := '0';
  signal cur_wait    : natural := 0;
  signal waited      : natural := 0;
  signal rsp_data    : std_ulogic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal rsp_err     : std_ulogic := '0';
  -- Seed as in claude_mem_model.sv: SEED, or 1 when SEED = 0 (xorshift must not start at 0).
  function seed_init(s : natural) return unsigned is
  begin
    if s = 0 then
      return to_unsigned(1, 32);
    end if;
    return to_unsigned(s, 32);
  end function;

  signal rng         : unsigned(31 downto 0) := seed_init(SEED);

  -- xorshift32, identical to claude_mem_model.sv
  procedure rng_next(variable x : inout unsigned(31 downto 0)) is
  begin
    x := x xor shift_left(x, 13);
    x := x xor shift_right(x, 17);
    x := x xor shift_left(x, 5);
  end procedure;

  function idx(a : std_ulogic_vector) return natural is
  begin
    if IDX_W = 0 then
      return 0;
    end if;
    return to_integer(unsigned(a(OFF_W + IDX_W - 1 downto OFF_W)));
  end function;

begin

  assert 2 ** IDX_W = WORDS
    report "claude_mem_model: SIZE / (DATA_W / 8) must be a power of two" severity failure;

  gnt_i   <= '1' when mem_req = '1' and outstanding = '0' and rvalid_q = '0' and waited >= cur_wait
             else '0';
  mem_gnt <= gnt_i;

  p_main : process (clk) is
    variable mem        : mem_t := (others => (others => '0'));
    variable x          : unsigned(31 downto 0);
    variable d          : natural;
    variable perr       : natural := 0;
    variable prev_wait  : boolean := false;
    variable prev_we    : std_ulogic;
    variable prev_addr  : std_ulogic_vector(ADDR_W - 1 downto 0);
    variable prev_be    : std_ulogic_vector(STRB_W - 1 downto 0);
    variable prev_wdata : std_ulogic_vector(DATA_W - 1 downto 0);
    variable rsp_wait   : natural := 0;

    impure function pick(lo, hi : natural) return natural is
    begin
      if hi <= lo then
        return lo;
      end if;
      rng_next(x);
      return lo + to_integer(x mod to_unsigned(hi - lo + 1, 32));
    end function;
  begin
    if rising_edge(clk) then
      x := rng;
      if rst_n = '0' then
        outstanding <= '0';
        rvalid_q    <= '0';
        cur_wait    <= 0;
        waited      <= 0;
        prev_wait   := false;
        rsp_wait    := 0;
      else
        -- rule 1
        if prev_wait and not (mem_req = '1' and mem_we = prev_we and mem_addr = prev_addr and
                              mem_be = prev_be and (mem_we = '0' or mem_wdata = prev_wdata)) then
          report "ERROR [claude_mem_model] request dropped or changed before grant" severity error;
          perr := perr + 1;
        end if;
        -- rule 2
        if mem_req = '1' and (outstanding = '1' or rvalid_q = '1') then
          report "ERROR [claude_mem_model] request while one is outstanding" severity error;
          perr := perr + 1;
        end if;
        -- rule 9
        if mem_req = '1' and unsigned(mem_be) = 0 then
          report "ERROR [claude_mem_model] mem_be all zeros" severity error;
          perr := perr + 1;
        end if;
        prev_wait  := mem_req = '1' and gnt_i = '0';
        prev_we    := mem_we;
        prev_addr  := mem_addr;
        prev_be    := mem_be;
        prev_wdata := mem_wdata;

        -- grant delay of the next request
        if mem_req = '0' or gnt_i = '1' then
          cur_wait <= pick(min_gnt, max_gnt);
          waited   <= 0;
        else
          waited <= waited + 1;
        end if;

        rvalid_q <= '0';
        if mem_req = '1' and gnt_i = '1' then
          rsp_err  <= '0';
          rsp_data <= (others => '0');
          if ERR_MSB = 1 and mem_addr(ADDR_W - 1) = '1' then
            rsp_err <= '1';
          elsif mem_we = '1' then
            for b in 0 to STRB_W - 1 loop
              if mem_be(b) = '1' then
                mem(idx(mem_addr))(8 * b + 7 downto 8 * b) := mem_wdata(8 * b + 7 downto 8 * b);
              end if;
            end loop;
          else
            rsp_data <= mem(idx(mem_addr));
          end if;
          d := pick(min_rsp, max_rsp);
          if d = 0 then
            rvalid_q <= '1';
          else
            rsp_wait    := d - 1;
            outstanding <= '1';
          end if;
        elsif outstanding = '1' then
          if rsp_wait = 0 then
            rvalid_q    <= '1';
            outstanding <= '0';
          else
            rsp_wait := rsp_wait - 1;
          end if;
        end if;
      end if;
      rng          <= x;
      proto_errors <= perr;
    end if;
  end process p_main;

  mem_rvalid <= rvalid_q;
  mem_rdata  <= rsp_data when rvalid_q = '1' else (others => 'X');
  mem_err    <= rsp_err  when rvalid_q = '1' else 'X';

end architecture sim;
