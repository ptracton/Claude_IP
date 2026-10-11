-- bus_matrix_axi4l_ini.vhd — AXI4-Lite initiator adapter for one bus matrix slave port (VHDL-2008).
--
-- Acts as an AXI4-Lite master towards the external slave and runs exactly one
-- transaction for each core request:
--   Write: AWVALID and WVALID rise together and each drops after its own
--     handshake; BREADY is high for the whole write and done pulses with
--     BVALID.
--   Read:  ARVALID until its handshake; RREADY is high for the whole read and
--     done pulses with RVALID.
-- err is BRESP(1) / RRESP(1) (SLVERR or DECERR from the slave).
-- Mirrors bus_matrix_axi4l_ini.sv.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_axi4l_ini is
  generic (
    DATA_W : positive := 32;  -- data bus width
    ADDR_W : positive := 32   -- address width
  );
  port (
    clk        : in  std_ulogic;                                  -- system clock
    rst_n      : in  std_ulogic;                                  -- synchronous active-low reset

    -- Core handshake
    core_req   : in  std_ulogic;                                  -- run one transaction
    core_addr  : in  std_ulogic_vector(ADDR_W - 1 downto 0);      -- byte address
    core_wdata : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    core_we    : in  std_ulogic;                                  -- 1 = write
    core_be    : in  std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- byte enables
    core_done  : out std_ulogic;                                  -- one-cycle completion
    core_rdata : out std_ulogic_vector(DATA_W - 1 downto 0);      -- read data (valid with done)
    core_err   : out std_ulogic;                                  -- error (valid with done)

    -- AXI4-Lite master interface (towards the external slave)
    AWVALID    : out std_ulogic;                                  -- write address valid
    AWREADY    : in  std_ulogic;                                  -- write address ready
    AWADDR     : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- write byte address
    WVALID     : out std_ulogic;                                  -- write data valid
    WREADY     : in  std_ulogic;                                  -- write data ready
    WDATA      : out std_ulogic_vector(DATA_W - 1 downto 0);      -- write data
    WSTRB      : out std_ulogic_vector(DATA_W / 8 - 1 downto 0);  -- write byte strobes
    BVALID     : in  std_ulogic;                                  -- write response valid
    BREADY     : out std_ulogic;                                  -- write response ready
    BRESP      : in  std_ulogic_vector(1 downto 0);               -- write response
    ARVALID    : out std_ulogic;                                  -- read address valid
    ARREADY    : in  std_ulogic;                                  -- read address ready
    ARADDR     : out std_ulogic_vector(ADDR_W - 1 downto 0);      -- read byte address
    RVALID     : in  std_ulogic;                                  -- read data valid
    RREADY     : out std_ulogic;                                  -- read data ready
    RDATA      : in  std_ulogic_vector(DATA_W - 1 downto 0);      -- read data
    RRESP      : in  std_ulogic_vector(1 downto 0)                -- read response
  );
end entity bus_matrix_axi4l_ini;

architecture rtl of bus_matrix_axi4l_ini is

  type ini_t is (INI_IDLE, INI_WRITE, INI_READ);

  signal state_q : ini_t;
  signal state_d : ini_t;
  signal aw_ok_q : std_ulogic;  -- AW handshake done
  signal w_ok_q  : std_ulogic;  -- W handshake done
  signal ar_ok_q : std_ulogic;  -- AR handshake done
  signal aw_ok_d : std_ulogic;
  signal w_ok_d  : std_ulogic;
  signal ar_ok_d : std_ulogic;
  signal in_wr   : std_ulogic;
  signal in_rd   : std_ulogic;

begin

  in_wr <= '1' when state_q = INI_WRITE else '0';
  in_rd <= '1' when state_q = INI_READ else '0';

  AWVALID <= in_wr and not aw_ok_q;
  WVALID  <= in_wr and not w_ok_q;
  BREADY  <= in_wr;
  ARVALID <= in_rd and not ar_ok_q;
  RREADY  <= in_rd;

  AWADDR  <= core_addr;
  ARADDR  <= core_addr;
  WDATA   <= core_wdata;
  WSTRB   <= core_be;

  -- Handshake-done flags: set by READY while in the owning state, cleared in idle.
  aw_ok_d <= in_wr and (aw_ok_q or AWREADY);
  w_ok_d  <= in_wr and (w_ok_q or WREADY);
  ar_ok_d <= in_rd and (ar_ok_q or ARREADY);

  p_next : process (state_q, core_req, core_we, BVALID, RVALID) is
  begin
    state_d <= state_q;
    case state_q is
      when INI_IDLE =>
        if core_req = '1' then
          if core_we = '1' then
            state_d <= INI_WRITE;
          else
            state_d <= INI_READ;
          end if;
        end if;
      when INI_WRITE =>
        if BVALID = '1' then
          state_d <= INI_IDLE;
        end if;
      when INI_READ =>
        if RVALID = '1' then
          state_d <= INI_IDLE;
        end if;
    end case;
  end process p_next;

  p_state : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_q <= INI_IDLE;
        aw_ok_q <= '0';
        w_ok_q  <= '0';
        ar_ok_q <= '0';
      else
        state_q <= state_d;
        aw_ok_q <= aw_ok_d;
        w_ok_q  <= w_ok_d;
        ar_ok_q <= ar_ok_d;
      end if;
    end if;
  end process p_state;

  core_done  <= (in_wr and BVALID) or (in_rd and RVALID);
  core_err   <= BRESP(1) when state_q = INI_WRITE else RRESP(1);
  core_rdata <= RDATA;

end architecture rtl;
