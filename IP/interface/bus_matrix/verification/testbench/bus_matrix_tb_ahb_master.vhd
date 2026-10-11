-- bus_matrix_tb_ahb_master.vhd — One AHB-Lite master for the VHDL bus matrix testbench.
--
-- Runs one single transfer per command. A command is issued by setting
-- cmd_we/cmd_addr/cmd_wdata/cmd_strb and toggling cmd_req; when the transfer
-- has completed, rsp_rdata/rsp_err are valid and cmd_ack equals cmd_req.
-- Timing matches the shared SV task library (tasks_ahb.sv): both phases wait
-- for HREADY, which is sampled at the clock edge that ends the phase.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_tb_ahb_master is
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
    HSEL      : out std_ulogic := '0';
    HADDR     : out std_ulogic_vector(31 downto 0) := (others => '0');
    HTRANS    : out std_ulogic_vector(1 downto 0) := "00";
    HWRITE    : out std_ulogic := '0';
    HWDATA    : out std_ulogic_vector(31 downto 0) := (others => '0');
    HWSTRB    : out std_ulogic_vector(3 downto 0) := (others => '0');
    HREADY    : in  std_ulogic;
    HRDATA    : in  std_ulogic_vector(31 downto 0);
    HRESP     : in  std_ulogic
  );
end entity bus_matrix_tb_ahb_master;

architecture sim of bus_matrix_tb_ahb_master is
begin

  p_bfm : process is
    variable ack : std_ulogic := '0';
  begin
    wait until cmd_req /= ack;
    wait until rising_edge(clk);
    -- Address phase
    HSEL   <= '1';
    HADDR  <= cmd_addr;
    HTRANS <= "10";
    HWRITE <= cmd_we;
    loop
      wait until rising_edge(clk);
      exit when HREADY = '1';
    end loop;
    -- Data phase
    HSEL   <= '0';
    HTRANS <= "00";
    HWRITE <= '0';
    if cmd_we = '1' then
      HWDATA <= cmd_wdata;
      HWSTRB <= cmd_strb;
    end if;
    loop
      wait until rising_edge(clk);
      exit when HREADY = '1';
    end loop;
    rsp_rdata <= HRDATA;
    rsp_err   <= HRESP;
    ack       := not ack;
    cmd_ack   <= ack;
  end process p_bfm;

end architecture sim;
