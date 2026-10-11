-- bus_matrix_ahb_tgt.vhd — AHB-Lite target adapter for one bus matrix master port (VHDL-2008).
--
-- Acts as an AHB-Lite slave towards the external master and turns each
-- transfer into one request on the core's internal handshake.
--
--   Address phase: accepted when HREADY is high and HSEL and HTRANS(1)
--     (NONSEQ or SEQ; every beat is treated as a single transfer).
--   Data phase:    req is held, HREADY low, until the core reports done.
--     HWDATA/HWSTRB are passed through live: the master holds them for the
--     whole data phase.
--   Response:      OKAY ends the data phase in the done cycle. ERROR takes
--     two cycles (HREADY low + HRESP high, then HREADY high + HRESP high).
--
-- HREADY is this port's HREADYOUT; the port is the only slave on the master's
-- bus, so it is also the HREADY the master and this adapter sample.
-- Mirrors bus_matrix_ahb_tgt.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_ahb_tgt is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    clk    : in  std_ulogic; -- system clock
    rst_n  : in  std_ulogic; -- synchronous active-low reset

    -- AHB-Lite slave interface (towards the external master)
    HSEL   : in  std_ulogic;                                 -- slave select
    HADDR  : in  std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    HTRANS : in  std_ulogic_vector(1 downto 0);              -- transfer type
    HWRITE : in  std_ulogic;                                 -- 1 = write
    HWDATA : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- write data (data phase)
    HWSTRB : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte strobes (data phase)
    HRDATA : out std_ulogic_vector(DATA_W - 1 downto 0);     -- read data
    HREADY : out std_ulogic;                                 -- transfer done
    HRESP  : out std_ulogic;                                 -- 1 = ERROR

    -- Core handshake
    core_req    : out std_ulogic;                                 -- request held until done
    core_addr   : out std_ulogic_vector(ADDR_W - 1 downto 0);     -- byte address
    core_wdata  : out std_ulogic_vector(DATA_W - 1 downto 0);     -- write data
    core_we     : out std_ulogic;                                 -- 1 = write
    core_be     : out std_ulogic_vector(DATA_W / 8 - 1 downto 0); -- byte enables
    core_done   : in  std_ulogic;                                 -- one-cycle completion
    core_rdata  : in  std_ulogic_vector(DATA_W - 1 downto 0);     -- read data (valid with done)
    core_err    : in  std_ulogic                                  -- error (valid with done)
  );
end entity bus_matrix_ahb_tgt;

architecture rtl of bus_matrix_ahb_tgt is

  type tgt_state_t is (TGT_IDLE, TGT_BUSY, TGT_ERR2);

  signal state_q : tgt_state_t;
  signal state_d : tgt_state_t;
  signal addr_q  : std_ulogic_vector(ADDR_W - 1 downto 0);
  signal we_q    : std_ulogic;
  signal aphase  : std_ulogic;  -- an address phase is presented
  signal hready_i: std_ulogic;

begin

  aphase <= HSEL and HTRANS(1);

  p_hready : process (state_q, core_done, core_err) is
  begin
    hready_i <= '1';
    HRESP    <= '0';
    case state_q is
      when TGT_BUSY =>
        hready_i <= core_done and not core_err;
        HRESP    <= core_done and core_err;
      when TGT_ERR2 =>
        HRESP    <= '1';
      when others =>
        null;
    end case;
  end process p_hready;

  p_next : process (state_q, core_done, core_err, hready_i, aphase) is
  begin
    state_d <= state_q;
    if state_q = TGT_BUSY and core_done = '1' and core_err = '1' then
      state_d <= TGT_ERR2;
    elsif hready_i = '1' then
      if aphase = '1' then
        state_d <= TGT_BUSY;
      else
        state_d <= TGT_IDLE;
      end if;
    end if;
  end process p_next;

  p_state : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_q <= TGT_IDLE;
      else
        state_q <= state_d;
      end if;
    end if;
  end process p_state;

  p_aphase : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        addr_q <= (others => '0');
        we_q   <= '0';
      elsif hready_i = '1' and aphase = '1' then
        addr_q <= HADDR;
        we_q   <= HWRITE;
      end if;
    end if;
  end process p_aphase;

  core_req   <= '1' when state_q = TGT_BUSY else '0';
  core_addr  <= addr_q;
  core_we    <= we_q;
  core_wdata <= HWDATA;
  core_be    <= HWSTRB;
  HRDATA     <= core_rdata;
  HREADY     <= hready_i;

end architecture rtl;
