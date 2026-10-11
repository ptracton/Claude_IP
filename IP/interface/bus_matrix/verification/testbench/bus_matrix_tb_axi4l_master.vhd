-- bus_matrix_tb_axi4l_master.vhd — One AXI4-Lite master for the VHDL bus matrix testbench.
--
-- Runs one transaction per command (see bus_matrix_tb_ahb_master.vhd for the
-- cmd_req/cmd_ack toggle handshake). Timing matches the shared SV task
-- library (tasks_axi4l.sv): every VALID is held until its READY is high at a
-- clock edge; AW and W are presented together and complete independently;
-- B/R are taken at the first edge where BVALID/RVALID is high.

library ieee;
use ieee.std_logic_1164.all;

entity bus_matrix_tb_axi4l_master is
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
    AWVALID   : out std_ulogic := '0';
    AWREADY   : in  std_ulogic;
    AWADDR    : out std_ulogic_vector(31 downto 0) := (others => '0');
    WVALID    : out std_ulogic := '0';
    WREADY    : in  std_ulogic;
    WDATA     : out std_ulogic_vector(31 downto 0) := (others => '0');
    WSTRB     : out std_ulogic_vector(3 downto 0) := (others => '0');
    BVALID    : in  std_ulogic;
    BREADY    : out std_ulogic := '0';
    BRESP     : in  std_ulogic_vector(1 downto 0);
    ARVALID   : out std_ulogic := '0';
    ARREADY   : in  std_ulogic;
    ARADDR    : out std_ulogic_vector(31 downto 0) := (others => '0');
    RVALID    : in  std_ulogic;
    RREADY    : out std_ulogic := '0';
    RDATA     : in  std_ulogic_vector(31 downto 0);
    RRESP     : in  std_ulogic_vector(1 downto 0)
  );
end entity bus_matrix_tb_axi4l_master;

architecture sim of bus_matrix_tb_axi4l_master is
begin

  p_bfm : process is
    variable ack     : std_ulogic := '0';
    variable aw_pend : boolean;
    variable w_pend  : boolean;
  begin
    wait until cmd_req /= ack;
    wait until rising_edge(clk);
    if cmd_we = '1' then
      AWVALID <= '1';
      AWADDR  <= cmd_addr;
      WVALID  <= '1';
      WDATA   <= cmd_wdata;
      WSTRB   <= cmd_strb;
      BREADY  <= '1';
      aw_pend := true;
      w_pend  := true;
      while aw_pend or w_pend loop
        wait until rising_edge(clk);
        if aw_pend and AWREADY = '1' then
          aw_pend := false;
          AWVALID <= '0';
        end if;
        if w_pend and WREADY = '1' then
          w_pend := false;
          WVALID <= '0';
        end if;
      end loop;
      loop
        wait until rising_edge(clk);
        exit when BVALID = '1';
      end loop;
      rsp_err <= BRESP(1);
      BREADY  <= '0';
    else
      ARVALID <= '1';
      ARADDR  <= cmd_addr;
      RREADY  <= '1';
      loop
        wait until rising_edge(clk);
        exit when ARREADY = '1';
      end loop;
      ARVALID <= '0';
      loop
        wait until rising_edge(clk);
        exit when RVALID = '1';
      end loop;
      rsp_rdata <= RDATA;
      rsp_err   <= RRESP(1);
      RREADY    <= '0';
    end if;
    ack     := not ack;
    cmd_ack <= ack;
  end process p_bfm;

end architecture sim;
