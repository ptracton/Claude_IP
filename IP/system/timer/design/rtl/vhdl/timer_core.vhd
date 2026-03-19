-- timer_core.vhd — Timer IP core logic (VHDL-2008).
--
-- Implements the 32-bit down-counter with 8-bit pre-scaler, two operating
-- modes (repeating / one-shot), interrupt generation, and trigger output.
-- Extended with: RESTART force-reload, IRQ_MODE level/pulse select,
-- OVF overrun detection, and LOAD=0 minimum-count protection.
--
-- This module is bus-protocol-agnostic.  All register-file decoded outputs
-- come in as inputs and all hardware-update signals go out as outputs.
--
-- Port-for-port equivalent to timer_core.sv.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity timer_core is
  generic (
    DATA_W : positive := 32  -- counter / load value width
  );
  port (
    -- Clock and synchronous active-low reset
    clk           : in  std_ulogic;                             -- system clock
    rst_n         : in  std_ulogic;                             -- sync active-low reset

    -- Decoded register outputs (from timer_regfile)
    ctrl_en       : in  std_ulogic;                             -- CTRL.EN
    ctrl_mode     : in  std_ulogic;                             -- CTRL.MODE (0=repeat 1=oneshot)
    ctrl_intr_en  : in  std_ulogic;                             -- CTRL.INTR_EN
    ctrl_trig_en  : in  std_ulogic;                             -- CTRL.TRIG_EN
    ctrl_prescale : in  std_ulogic_vector(7 downto 0);          -- CTRL.PRESCALE
    ctrl_restart  : in  std_ulogic;                             -- CTRL.RESTART self-clearing pulse
    ctrl_irq_mode : in  std_ulogic;                             -- CTRL.IRQ_MODE: 0=level, 1=pulse
    load_val      : in  std_ulogic_vector(DATA_W - 1 downto 0); -- LOAD register

    -- Status feedback from regfile
    status_intr   : in  std_ulogic;                             -- STATUS.INTR sticky bit

    -- Hardware update outputs (to timer_regfile)
    hw_count_val  : out std_ulogic_vector(DATA_W - 1 downto 0); -- current count
    hw_intr_set   : out std_ulogic;                             -- one-cycle set pulse
    hw_ovf_set    : out std_ulogic;                             -- one-cycle OVF set pulse
    hw_active     : out std_ulogic;                             -- counter running

    -- External IP outputs
    irq           : out std_ulogic;                             -- masked interrupt
    trigger_out   : out std_ulogic                              -- one-cycle trigger pulse
  );
end entity timer_core;

architecture rtl of timer_core is

  signal prescale_cnt_q : unsigned(7 downto 0);
  signal count_q        : unsigned(DATA_W - 1 downto 0);
  signal active_q       : std_ulogic;
  signal en_prev_q      : std_ulogic;

  signal tick           : std_ulogic;
  signal load_pulse     : std_ulogic;
  signal underflow      : std_ulogic;

  -- LOAD=0 protection: minimum reload value is 1 to prevent infinite underflow loops
  signal safe_load_val  : unsigned(DATA_W - 1 downto 0);

begin

  -- -------------------------------------------------------------------------
  -- EN rising-edge detection: reload counter when EN transitions 0->1
  -- -------------------------------------------------------------------------
  p_en_edge : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        en_prev_q <= '0';
      else
        en_prev_q <= ctrl_en;
      end if;
    end if;
  end process p_en_edge;

  load_pulse <= ctrl_en and (not en_prev_q);

  safe_load_val <= to_unsigned(1, DATA_W)
                   when unsigned(load_val) = to_unsigned(0, DATA_W)
                   else unsigned(load_val);

  -- -------------------------------------------------------------------------
  -- Pre-scaler: counts from ctrl_prescale down to 0, wraps, and asserts tick.
  -- When ctrl_prescale == 0, tick fires every clock while enabled.
  -- RESTART resets the prescaler to ctrl_prescale for a fresh period.
  -- -------------------------------------------------------------------------
  p_prescaler : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        prescale_cnt_q <= (others => '0');
      elsif ctrl_en = '0' then
        -- Hold prescaler in reset while timer is disabled.
        prescale_cnt_q <= unsigned(ctrl_prescale);
      elsif ctrl_restart = '1' then
        -- Force-reload: reset prescaler so next tick starts a fresh period.
        prescale_cnt_q <= unsigned(ctrl_prescale);
      else
        if prescale_cnt_q = to_unsigned(0, 8) then
          prescale_cnt_q <= unsigned(ctrl_prescale);
        else
          prescale_cnt_q <= prescale_cnt_q - to_unsigned(1, 8);
        end if;
      end if;
    end if;
  end process p_prescaler;

  tick <= ctrl_en when prescale_cnt_q = to_unsigned(0, 8) else '0';

  -- -------------------------------------------------------------------------
  -- Main 32-bit down-counter and active flag.
  -- Uses safe_load_val (min 1) to prevent infinite zero-period loops.
  -- RESTART force-reloads the counter without toggling EN.
  -- -------------------------------------------------------------------------
  p_counter : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        count_q  <= (others => '0');
        active_q <= '0';
      else
        if load_pulse = '1' then
          -- EN just asserted: load counter and mark as active.
          count_q  <= safe_load_val;
          active_q <= '1';
        elsif ctrl_restart = '1' and active_q = '1' then
          -- Force-reload: reload without disabling; active_q stays '1'.
          count_q <= safe_load_val;
        elsif active_q = '1' and tick = '1' then
          if count_q = to_unsigned(0, DATA_W) then
            -- Underflow event
            if ctrl_mode = '0' then
              -- Repeat mode: reload with LOAD=0 protection and continue.
              count_q  <= safe_load_val;
              active_q <= '1';
            else
              -- One-shot mode: stop after underflow.
              count_q  <= (others => '0');
              active_q <= '0';
            end if;
          else
            count_q <= count_q - to_unsigned(1, DATA_W);
          end if;
        elsif ctrl_en = '0' then
          -- EN deasserted externally: stop counter.
          active_q <= '0';
        end if;
      end if;
    end if;
  end process p_counter;

  -- -------------------------------------------------------------------------
  -- Underflow detection — combinational
  -- -------------------------------------------------------------------------
  underflow <= active_q and tick
               when (count_q = to_unsigned(0, DATA_W))
               else '0';

  -- -------------------------------------------------------------------------
  -- hw_intr_set: one-cycle pulse to regfile, registered for clean timing
  -- -------------------------------------------------------------------------
  p_intr_set : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        hw_intr_set <= '0';
      else
        hw_intr_set <= underflow;
      end if;
    end if;
  end process p_intr_set;

  -- -------------------------------------------------------------------------
  -- hw_ovf_set: one-cycle pulse when underflow fires while INTR is already set.
  -- Indicates a missed interrupt (overrun).
  -- -------------------------------------------------------------------------
  p_ovf_set : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        hw_ovf_set <= '0';
      else
        hw_ovf_set <= underflow and status_intr;
      end if;
    end if;
  end process p_ovf_set;

  -- -------------------------------------------------------------------------
  -- trigger_out: one-cycle pulse on underflow, gated by ctrl_trig_en
  -- -------------------------------------------------------------------------
  p_trigger : process(clk) is
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        trigger_out <= '0';
      else
        trigger_out <= underflow and ctrl_trig_en;
      end if;
    end if;
  end process p_trigger;

  -- -------------------------------------------------------------------------
  -- hw_count_val and hw_active: driven from registered state
  -- -------------------------------------------------------------------------
  hw_count_val <= std_ulogic_vector(count_q);
  hw_active    <= active_q;

  -- -------------------------------------------------------------------------
  -- irq: masked interrupt output, mode-selectable
  --   Level mode (ctrl_irq_mode=0): irq asserted while STATUS.INTR is set
  --   Pulse mode (ctrl_irq_mode=1): irq is a one-cycle pulse per underflow
  -- -------------------------------------------------------------------------
  irq <= ctrl_intr_en and hw_intr_set when ctrl_irq_mode = '1'
         else ctrl_intr_en and status_intr;

end architecture rtl;
