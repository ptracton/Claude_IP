-- sram_pwr_ctrl.vhd — Power-mode state machine for one sram power domain.
--
-- VHDL-2008 twin of sram_pwr_ctrl.sv (see it for the state diagram).
-- Target mode = RUN while wake_i is high, else mode_req_i. Sleep is entered
-- only when idle_i; leaving shutdown waits for the clear engine (clr_req_o /
-- clr_done_i). With PWR_GATE = 0 the domain is permanently in RUN.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sram_pkg.all;

entity sram_pwr_ctrl is
  generic (
    PWR_GATE  : natural := 1; -- power modes enabled (0 / 1)
    ENTER_CYC : natural := 2; -- pins-on to mode reached
    WAKE_LS   : natural := 2; -- wake time from light sleep
    WAKE_DS   : natural := 4; -- wake time from deep sleep
    WAKE_SD   : natural := 8  -- wake time from shutdown
  );
  port (
    clk         : in  std_ulogic;                    -- clock
    rst_n       : in  std_ulogic;                    -- synchronous active-low reset
    mode_req_i  : in  std_ulogic_vector(1 downto 0); -- requested mode (PWR_*_C)
    wake_i      : in  std_ulogic;                    -- keep / bring the domain to RUN
    idle_i      : in  std_ulogic;                    -- no access to this domain in flight
    clr_done_i  : in  std_ulogic;                    -- clear engine finished this domain
    ls_o        : out std_ulogic;                    -- light-sleep pin
    ds_o        : out std_ulogic;                    -- deep-sleep pin
    sd_o        : out std_ulogic;                    -- shutdown pin
    awake_o     : out std_ulogic;                    -- RUN: bus accesses allowed
    engine_ok_o : out std_ulogic;                    -- RUN or clearing: engine accesses allowed
    clr_req_o   : out std_ulogic;                    -- contents lost: please clear this domain
    busy_o      : out std_ulogic;                    -- mode transition in progress
    ack_o       : out std_ulogic_vector(1 downto 0)  -- mode in effect
  );
end entity sram_pwr_ctrl;

architecture rtl of sram_pwr_ctrl is

  constant CNT_W_C : positive := 5; -- counts up to 31 cycles

begin

  gen_pwr : if PWR_GATE /= 0 generate

    type pwr_state_t is (StRun, StEnter, StSleep, StWake, StClear);

    signal state_d : pwr_state_t;
    signal state_q : pwr_state_t;
    signal mode_d  : std_ulogic_vector(1 downto 0); -- sleep mode entered / being left
    signal mode_q  : std_ulogic_vector(1 downto 0);
    signal ack_d   : std_ulogic_vector(1 downto 0);
    signal ack_q   : std_ulogic_vector(1 downto 0);
    signal cnt_d   : unsigned(CNT_W_C - 1 downto 0);
    signal cnt_q   : unsigned(CNT_W_C - 1 downto 0);
    signal target  : std_ulogic_vector(1 downto 0);
    signal pins_on : std_ulogic;

    function wake_count(mode : std_ulogic_vector(1 downto 0)) return unsigned is
    begin
      if mode = PWR_LS_C then
        return to_unsigned(WAKE_LS, CNT_W_C);
      elsif mode = PWR_DS_C then
        return to_unsigned(WAKE_DS, CNT_W_C);
      elsif mode = PWR_SD_C then
        return to_unsigned(WAKE_SD, CNT_W_C);
      end if;
      return to_unsigned(1, CNT_W_C);
    end function wake_count;

  begin

    target <= PWR_RUN_C when wake_i = '1' else mode_req_i;

    p_state_comb : process (all) is
    begin
      state_d <= state_q;
      mode_d  <= mode_q;
      ack_d   <= ack_q;
      if cnt_q /= 0 then
        cnt_d <= cnt_q - 1;
      else
        cnt_d <= cnt_q;
      end if;
      case state_q is
        -- StRun: full operation; enter a sleep mode once the domain is idle.
        when StRun =>
          if target /= PWR_RUN_C and idle_i = '1' then
            mode_d  <= target;
            cnt_d   <= to_unsigned(ENTER_CYC, CNT_W_C);
            state_d <= StEnter;
          end if;
        -- StEnter: pins asserted, waiting for the macro to reach the mode.
        when StEnter =>
          if cnt_q = 0 then
            ack_d   <= mode_q;
            state_d <= StSleep;
          end if;
        -- StSleep: in the mode; leave it when the target changes.
        when StSleep =>
          if target /= mode_q then
            cnt_d   <= wake_count(mode_q);
            state_d <= StWake;
          end if;
        -- StWake: pins released, waiting for the wake-up time.
        when StWake =>
          if cnt_q = 0 then
            if mode_q = PWR_SD_C then
              state_d <= StClear;
            else
              ack_d   <= PWR_RUN_C;
              state_d <= StRun;
            end if;
          end if;
        -- StClear: contents were lost in shutdown; wait for the clear engine.
        when StClear =>
          if clr_done_i = '1' then
            ack_d   <= PWR_RUN_C;
            state_d <= StRun;
          end if;
        when others =>
          state_d <= StRun;
      end case;
    end process p_state_comb;

    -- State, mode, acknowledge and counter registers.
    p_state_reg : process (clk) is
    begin
      if rising_edge(clk) then
        if rst_n = '0' then
          state_q <= StRun;
          mode_q  <= PWR_RUN_C;
          ack_q   <= PWR_RUN_C;
          cnt_q   <= (others => '0');
        else
          state_q <= state_d;
          mode_q  <= mode_d;
          ack_q   <= ack_d;
          cnt_q   <= cnt_d;
        end if;
      end if;
    end process p_state_reg;

    pins_on <= '1' when state_q = StEnter or state_q = StSleep else '0';

    ls_o        <= pins_on when mode_q = PWR_LS_C else '0';
    ds_o        <= pins_on when mode_q = PWR_DS_C else '0';
    sd_o        <= pins_on when mode_q = PWR_SD_C else '0';
    awake_o     <= '1' when state_q = StRun else '0';
    engine_ok_o <= '1' when state_q = StRun or state_q = StClear else '0';
    clr_req_o   <= '1' when state_q = StClear else '0';
    busy_o      <= '1' when state_q = StEnter or state_q = StWake or state_q = StClear else '0';
    ack_o       <= ack_q;

  else generate

    -- Power modes disabled: always running.
    ls_o        <= '0';
    ds_o        <= '0';
    sd_o        <= '0';
    awake_o     <= '1';
    engine_ok_o <= '1';
    clr_req_o   <= '0';
    busy_o      <= '0';
    ack_o       <= PWR_RUN_C;

  end generate gen_pwr;

end architecture rtl;
