-- timer_regfile.vhd - Timer IP synthesizable register file (VHDL-2008).
-- Hand-maintained after initial generation; updated to add:
--   CTRL.RESTART (bit 12, self-clearing), CTRL.IRQ_MODE (bit 13),
--   CTRL.SNAPSHOT (bit 14, self-clearing), STATUS.OVF (bit 2, W1C),
--   CAPTURE register (0x10, RO).
-- Single source of truth for layout: design/systemrdl/timer.rdl
--
-- Port list is port-for-port equivalent to timer_regfile.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timer_reg_pkg.all;

entity timer_regfile is
  port (
    -- Clock and synchronous active-low reset
    clk          : in  std_ulogic;
    rst_n        : in  std_ulogic;

    -- Write channel
    wr_en        : in  std_ulogic;
    wr_addr      : in  std_ulogic_vector(3 downto 0);
    wr_data      : in  std_ulogic_vector(31 downto 0);
    wr_strb      : in  std_ulogic_vector(3 downto 0);

    -- Read channel
    rd_en        : in  std_ulogic;
    rd_addr      : in  std_ulogic_vector(3 downto 0);
    rd_data      : out std_ulogic_vector(31 downto 0);

    -- Hardware update ports (from timer_core)
    hw_count_val : in  std_ulogic_vector(31 downto 0);
    hw_intr_set  : in  std_ulogic;
    hw_ovf_set   : in  std_ulogic;
    hw_active    : in  std_ulogic;

    -- Output to timer_core
    ctrl_en       : out std_ulogic;
    ctrl_mode     : out std_ulogic;
    ctrl_intr_en  : out std_ulogic;
    ctrl_trig_en  : out std_ulogic;
    ctrl_prescale : out std_ulogic_vector(7 downto 0);
    ctrl_restart  : out std_ulogic;  -- CTRL.RESTART self-clearing pulse
    ctrl_irq_mode : out std_ulogic;  -- CTRL.IRQ_MODE: 0=level, 1=pulse
    load_val      : out std_ulogic_vector(31 downto 0);
    status_intr   : out std_ulogic   -- STATUS.INTR bit for IRQ masking in core
  );
end entity timer_regfile;

architecture rtl of timer_regfile is

  -- Internal register storage
  signal ctrl_q    : std_ulogic_vector(31 downto 0);
  signal status_q  : std_ulogic_vector(31 downto 0);
  signal load_q    : std_ulogic_vector(31 downto 0);
  signal count_q   : std_ulogic_vector(31 downto 0);
  signal capture_q : std_ulogic_vector(31 downto 0); -- CAPTURE snapshot register

  -- -----------------------------------------------------------------------
  -- Byte-enable merge: apply wr_strb to current register value
  -- -----------------------------------------------------------------------
  function apply_strb (
    current : std_ulogic_vector(31 downto 0);
    wdata   : std_ulogic_vector(31 downto 0);
    strb    : std_ulogic_vector(3 downto 0)
  ) return std_ulogic_vector is
    variable result : std_ulogic_vector(31 downto 0);
  begin
    result(7 downto 0)   := wdata(7 downto 0)   when strb(0) = '1' else current(7 downto 0);
    result(15 downto 8)  := wdata(15 downto 8)  when strb(1) = '1' else current(15 downto 8);
    result(23 downto 16) := wdata(23 downto 16) when strb(2) = '1' else current(23 downto 16);
    result(31 downto 24) := wdata(31 downto 24) when strb(3) = '1' else current(31 downto 24);
    return result;
  end function apply_strb;

begin

  -- -----------------------------------------------------------------------
  -- CTRL register - RW, reset 0x0
  -- Reserved bits [31:15] are always zero.
  -- RESTART(bit 12) and SNAPSHOT(bit 14) are self-clearing command bits:
  -- they hold '1' for one cycle after a write that sets them, then auto-clear.
  -- -----------------------------------------------------------------------
  p_ctrl : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        ctrl_q <= TIMER_CTRL_RESET;
      elsif wr_en = '1' and wr_addr = TIMER_CTRL_OFFSET then
        -- Capture write; mask reserved bits [31:15] to zero.
        ctrl_q <= apply_strb(ctrl_q, wr_data, wr_strb)
                  and x"00007FFF";
      else
        -- Auto-clear self-clearing command bits when not writing.
        ctrl_q(TIMER_CTRL_RESTART_BIT)  <= '0';
        ctrl_q(TIMER_CTRL_SNAPSHOT_BIT) <= '0';
      end if;
    end if;
  end process p_ctrl;

  -- -----------------------------------------------------------------------
  -- STATUS register
  --   INTR  (bit 0) : W1C — hw sets on underflow; write-1 to clear.
  --   ACTIVE(bit 1) : RO  — driven by hw_active.
  --   OVF   (bit 2) : W1C — hw sets when underflow fires while INTR=1.
  -- -----------------------------------------------------------------------
  p_status : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        status_q <= TIMER_STATUS_RESET;
      else
        -- ACTIVE tracks hw_active
        status_q(TIMER_STATUS_ACTIVE_BIT) <= hw_active;

        -- INTR: set by hw_intr_set; cleared by W1C write
        if hw_intr_set = '1' then
          status_q(TIMER_STATUS_INTR_BIT) <= '1';
        elsif wr_en = '1'
              and wr_addr = TIMER_STATUS_OFFSET
              and wr_strb(0) = '1'
              and wr_data(TIMER_STATUS_INTR_BIT) = '1' then
          status_q(TIMER_STATUS_INTR_BIT) <= '0';
        end if;

        -- OVF: set by hw_ovf_set; cleared by W1C write
        if hw_ovf_set = '1' then
          status_q(TIMER_STATUS_OVF_BIT) <= '1';
        elsif wr_en = '1'
              and wr_addr = TIMER_STATUS_OFFSET
              and wr_strb(0) = '1'
              and wr_data(TIMER_STATUS_OVF_BIT) = '1' then
          status_q(TIMER_STATUS_OVF_BIT) <= '0';
        end if;

        -- Reserved bits stay zero
        status_q(31 downto 3) <= (others => '0');
      end if;
    end if;
  end process p_status;

  -- -----------------------------------------------------------------------
  -- LOAD register - fully RW, reset 0x0
  -- -----------------------------------------------------------------------
  p_load : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        load_q <= TIMER_LOAD_RESET;
      elsif wr_en = '1' and wr_addr = TIMER_LOAD_OFFSET then
        load_q <= apply_strb(load_q, wr_data, wr_strb);
      end if;
    end if;
  end process p_load;

  -- -----------------------------------------------------------------------
  -- COUNT register - RO mirror of hw_count_val
  -- -----------------------------------------------------------------------
  p_count : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        count_q <= TIMER_COUNT_RESET;
      else
        count_q <= hw_count_val;
      end if;
    end if;
  end process p_count;

  -- -----------------------------------------------------------------------
  -- CAPTURE register - RO; latched when CTRL.SNAPSHOT fires.
  -- Captures hw_count_val (the live counter value from timer_core).
  -- -----------------------------------------------------------------------
  p_capture : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        capture_q <= TIMER_CAPTURE_RESET;
      elsif ctrl_q(TIMER_CTRL_SNAPSHOT_BIT) = '1' then
        capture_q <= hw_count_val;
      end if;
    end if;
  end process p_capture;

  -- -----------------------------------------------------------------------
  -- Read path - registered (valid cycle after rd_en)
  -- -----------------------------------------------------------------------
  p_read : process (clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        rd_data <= (others => '0');
      elsif rd_en = '1' then
        case rd_addr is
          when TIMER_CTRL_OFFSET    => rd_data <= ctrl_q;
          when TIMER_STATUS_OFFSET  => rd_data <= status_q;
          when TIMER_LOAD_OFFSET    => rd_data <= load_q;
          when TIMER_COUNT_OFFSET   => rd_data <= count_q;
          when TIMER_CAPTURE_OFFSET => rd_data <= capture_q;
          when others               => rd_data <= (others => '0');
        end case;
      end if;
    end if;
  end process p_read;

  -- -----------------------------------------------------------------------
  -- Output assignments to timer_core
  -- -----------------------------------------------------------------------
  ctrl_en       <= ctrl_q(TIMER_CTRL_EN_BIT);
  ctrl_mode     <= ctrl_q(TIMER_CTRL_MODE_BIT);
  ctrl_intr_en  <= ctrl_q(TIMER_CTRL_INTR_EN_BIT);
  ctrl_trig_en  <= ctrl_q(TIMER_CTRL_TRIG_EN_BIT);
  ctrl_prescale <= ctrl_q(TIMER_CTRL_PRESCALE_MSB downto TIMER_CTRL_PRESCALE_LSB);
  ctrl_restart  <= ctrl_q(TIMER_CTRL_RESTART_BIT);
  ctrl_irq_mode <= ctrl_q(TIMER_CTRL_IRQ_MODE_BIT);
  load_val      <= load_q;
  status_intr   <= status_q(TIMER_STATUS_INTR_BIT);

end architecture rtl;
