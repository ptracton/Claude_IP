-- bus_matrix_tb_wb_master.vhd — One Wishbone B4 master for the VHDL bus matrix testbench.
--
-- Runs one classic single transfer per command (see
-- bus_matrix_tb_ahb_master.vhd for the cmd_req/cmd_ack toggle handshake).
-- Timing matches the shared SV task library (tasks_wb.sv): CYC/STB are held
-- until ACK or ERR is high at a clock edge, then one idle cycle follows.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_tb_wb_master is
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
    CYC       : out std_ulogic := '0';
    STB       : out std_ulogic := '0';
    WE        : out std_ulogic := '0';
    ADR       : out std_ulogic_vector(31 downto 0) := (others => '0');
    DAT_W     : out std_ulogic_vector(31 downto 0) := (others => '0');
    SEL       : out std_ulogic_vector(3 downto 0) := (others => '0');
    DAT_R     : in  std_ulogic_vector(31 downto 0);
    ACK       : in  std_ulogic;
    ERR       : in  std_ulogic
  );
end entity bus_matrix_tb_wb_master;

architecture sim of bus_matrix_tb_wb_master is
begin

  p_bfm : process is
    variable ack_v : std_ulogic := '0';
  begin
    wait until cmd_req /= ack_v;
    wait until rising_edge(clk);
    CYC   <= '1';
    STB   <= '1';
    WE    <= cmd_we;
    ADR   <= cmd_addr;
    DAT_W <= cmd_wdata;
    if cmd_we = '1' then
      SEL <= cmd_strb;
    else
      SEL <= (others => '1');
    end if;
    loop
      wait until rising_edge(clk);
      exit when ACK = '1' or ERR = '1';
    end loop;
    rsp_rdata <= DAT_R;
    rsp_err   <= ERR;
    CYC       <= '0';
    STB       <= '0';
    WE        <= '0';
    wait until rising_edge(clk);
    ack_v   := not ack_v;
    cmd_ack <= ack_v;
  end process p_bfm;

end architecture sim;
