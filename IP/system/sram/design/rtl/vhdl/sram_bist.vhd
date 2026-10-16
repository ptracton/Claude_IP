-- sram_bist.vhd — March C- built-in self-test engine for the sram IP.
--
-- VHDL-2008 twin of sram_bist.sv (see it for the algorithm and sequence):
--   M0 up (w0); M1 up (r0,w1); M2 up (r1,w0); M3 down (r0,w1);
--   M4 down (r1,w0); M5 up (r0), on the raw stored words.
-- The array ends all-zero. fail_o / fail_idx_o hold from done_o until the
-- next start.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_bist is
  generic (
    DEPTH : positive := 1024; -- words
    MW    : positive := 32    -- stored word width
  );
  port (
    clk         : in  std_ulogic;                                   -- clock
    rst_n       : in  std_ulogic;                                   -- synchronous active-low reset
    start_i     : in  std_ulogic;                                   -- start a test (pulse)
    port_idle_i : in  std_ulogic; -- bus port has nothing in flight
    all_ok_i    : in  std_ulogic;                                   -- every domain accepts accesses
    pending_o   : out std_ulogic;                                   -- requested or running
    force_run_o : out std_ulogic;                                   -- bring every domain to RUN
    busy_o      : out std_ulogic;                                   -- test requested or running
    active_o    : out std_ulogic;                                   -- march running
    done_o      : out std_ulogic;                                   -- test finished (pulse)
    fail_o      : out std_ulogic;                                   -- a compare failed
    fail_idx_o  : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- first failing word
    cs_o        : out std_ulogic;                                   -- array access this cycle
    we_o        : out std_ulogic;                                   -- 1 = write
    idx_o       : out std_ulogic_vector(clog2(DEPTH) - 1 downto 0); -- word index
    wdata_o     : out std_ulogic_vector(MW - 1 downto 0);           -- pattern to write
    rdata_i     : in  std_ulogic_vector(MW - 1 downto 0) -- stored word (cycle after a read)
  );
end entity sram_bist;

architecture rtl of sram_bist is

  constant IDX_W_C    : positive := clog2(DEPTH);
  constant LAST_IDX_C : unsigned(IDX_W_C - 1 downto 0) := to_unsigned(DEPTH - 1, IDX_W_C);
  constant ZEROS_C    : std_ulogic_vector(MW - 1 downto 0) := (others => '0');
  constant ONES_C     : std_ulogic_vector(MW - 1 downto 0) := (others => '1');

  type bist_state_t is (StIdle, StWaitPort, StWaitPwr, StRead, StCheck, StWrite);

  signal state_d    : bist_state_t;
  signal state_q    : bist_state_t;
  signal elem_d     : unsigned(2 downto 0); -- march element 0..5
  signal elem_q     : unsigned(2 downto 0);
  signal idx_d      : unsigned(IDX_W_C - 1 downto 0);
  signal idx_q      : unsigned(IDX_W_C - 1 downto 0);
  signal fail_d     : std_ulogic;
  signal fail_q     : std_ulogic;
  signal fidx_d     : unsigned(IDX_W_C - 1 downto 0);
  signal fidx_q     : unsigned(IDX_W_C - 1 downto 0);
  signal done       : std_ulogic;

  signal elem_down  : boolean; -- descending addresses (M3, M4)
  signal exp_ones   : boolean; -- value expected by the read (M2, M4)
  signal wr_ones    : boolean; -- value written (M1, M3)
  signal elem_write : boolean; -- element has a write (all but M5)
  signal elem_end   : boolean; -- current word is the last of the element
  signal next_idx   : unsigned(IDX_W_C - 1 downto 0);
  signal next_elem  : unsigned(2 downto 0);

begin

  elem_down  <= elem_q = 3 or elem_q = 4;
  exp_ones   <= elem_q = 2 or elem_q = 4;
  wr_ones    <= elem_q = 1 or elem_q = 3;
  elem_write <= elem_q /= 5;
  elem_end   <= idx_q = 0 when elem_down else idx_q = LAST_IDX_C;

  -- Next word of the element, or the first word of the next element.
  p_next : process (all) is
    variable ne : unsigned(2 downto 0);
  begin
    ne := elem_q;
    if elem_down then
      next_idx <= idx_q - 1;
    else
      next_idx <= idx_q + 1;
    end if;
    if elem_end then
      ne := elem_q + 1;
      if ne = 3 or ne = 4 then
        next_idx <= LAST_IDX_C;
      else
        next_idx <= (others => '0');
      end if;
    end if;
    next_elem <= ne;
  end process p_next;

  p_state_comb : process (all) is
  begin
    state_d <= state_q;
    elem_d  <= elem_q;
    idx_d   <= idx_q;
    fail_d  <= fail_q;
    fidx_d  <= fidx_q;
    done    <= '0';
    cs_o    <= '0';
    we_o    <= '0';
    wdata_o <= ZEROS_C;
    case state_q is
      -- StIdle: wait for a start request.
      when StIdle =>
        if start_i = '1' then
          fail_d  <= '0';
          fidx_d  <= (others => '0');
          state_d <= StWaitPort;
        end if;
      -- StWaitPort: the core has stopped granting; wait for the port to drain.
      when StWaitPort =>
        if port_idle_i = '1' then
          state_d <= StWaitPwr;
        end if;
      -- StWaitPwr: force_run_o is high; wait until every domain is in RUN.
      when StWaitPwr =>
        if all_ok_i = '1' then
          elem_d  <= (others => '0');
          idx_d   <= (others => '0');
          state_d <= StWrite;
        end if;
      -- StWrite: M0 — write zero to every word.
      when StWrite =>
        cs_o <= '1';
        we_o <= '1';
        idx_d <= next_idx;
        if elem_end then
          elem_d  <= next_elem;
          state_d <= StRead;
        end if;
      -- StRead: read the current word.
      when StRead =>
        cs_o    <= '1';
        state_d <= StCheck;
      -- StCheck: compare the word read last cycle; write the element value.
      when StCheck =>
        if (exp_ones and rdata_i /= ONES_C) or (not exp_ones and rdata_i /= ZEROS_C) then
          if fail_q = '0' then
            fidx_d <= idx_q;
          end if;
          fail_d <= '1';
        end if;
        if elem_write then
          cs_o <= '1';
          we_o <= '1';
          if wr_ones then
            wdata_o <= ONES_C;
          end if;
        end if;
        if elem_end and elem_q = 5 then
          done    <= '1';
          state_d <= StIdle;
        else
          elem_d  <= next_elem;
          idx_d   <= next_idx;
          state_d <= StRead;
        end if;
      when others =>
        state_d <= StIdle;
    end case;
  end process p_state_comb;

  -- State, element, word index and result registers.
  p_state_reg : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_q <= StIdle;
        elem_q  <= (others => '0');
        idx_q   <= (others => '0');
        fail_q  <= '0';
        fidx_q  <= (others => '0');
      else
        state_q <= state_d;
        elem_q  <= elem_d;
        idx_q   <= idx_d;
        fail_q  <= fail_d;
        fidx_q  <= fidx_d;
      end if;
    end if;
  end process p_state_reg;

  idx_o       <= std_ulogic_vector(idx_q);
  pending_o   <= '0' when state_q = StIdle else '1';
  force_run_o <= '0' when state_q = StIdle or state_q = StWaitPort else '1';
  busy_o      <= '0' when state_q = StIdle else '1';
  active_o    <= '1' when state_q = StWrite or state_q = StRead or state_q = StCheck else '0';
  done_o      <= done;
  fail_o      <= fail_q;
  fail_idx_o  <= std_ulogic_vector(fidx_q);

end architecture rtl;
