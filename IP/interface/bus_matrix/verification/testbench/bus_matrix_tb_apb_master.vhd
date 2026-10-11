-- bus_matrix_tb_apb_master.vhd — One APB4 master for the VHDL bus matrix testbench.
--
-- Runs one transfer per command (see bus_matrix_tb_ahb_master.vhd for the
-- cmd_req/cmd_ack toggle handshake). Timing matches the shared SV task
-- library (tasks_apb.sv): one SETUP cycle, then ACCESS until PREADY is high
-- at a clock edge. PSTRB is 0 on reads.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_tb_apb_master is
  port (
    clk       : in  std_ulogic;
    cmd_req   : in  std_ulogic;
    cmd_we    : in  std_ulogic;
    cmd_addr  : in  std_ulogic_vector(31 downto 0);
    cmd_wdata : in  std_ulogic_vector(31 downto 0);
    cmd_strb  : in  std_ulogic_vector(3 downto 0);
    cmd_ack   : out std_ulogic := '0';
    rsp_rdata : out std_ulogic_vector(31 downto 0) := (others => '0');
    rsp_err   : out std_ulogic := '0';
    PSEL      : out std_ulogic := '0';
    PENABLE   : out std_ulogic := '0';
    PADDR     : out std_ulogic_vector(31 downto 0) := (others => '0');
    PWRITE    : out std_ulogic := '0';
    PWDATA    : out std_ulogic_vector(31 downto 0) := (others => '0');
    PSTRB     : out std_ulogic_vector(3 downto 0) := (others => '0');
    PRDATA    : in  std_ulogic_vector(31 downto 0);
    PREADY    : in  std_ulogic;
    PSLVERR   : in  std_ulogic
  );
end entity bus_matrix_tb_apb_master;

architecture sim of bus_matrix_tb_apb_master is
begin

  p_bfm : process is
    variable ack : std_ulogic := '0';
  begin
    wait until cmd_req /= ack;
    wait until rising_edge(clk);
    -- SETUP
    PSEL    <= '1';
    PENABLE <= '0';
    PADDR   <= cmd_addr;
    PWRITE  <= cmd_we;
    PWDATA  <= cmd_wdata;
    if cmd_we = '1' then
      PSTRB <= cmd_strb;
    else
      PSTRB <= (others => '0');
    end if;
    -- ACCESS
    wait until rising_edge(clk);
    PENABLE <= '1';
    loop
      wait until rising_edge(clk);
      exit when PREADY = '1';
    end loop;
    rsp_rdata <= PRDATA;
    rsp_err   <= PSLVERR;
    PSEL      <= '0';
    PENABLE   <= '0';
    PWRITE    <= '0';
    PSTRB     <= (others => '0');
    ack       := not ack;
    cmd_ack   <= ack;
  end process p_bfm;

end architecture sim;
