---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Link state machine (DL-3) of the SpaceWire Data Link layer: ErrorReset, ErrorWait, Ready,
-- Started, Connecting and Run with the exit conditions in the order of ECSS-E-ST-50-12C Rev.1
-- clauses 5.5.7.2 to 5.5.7.7, the 6.4 us and 12.8 us timers and port reset (5.5.7.1e).
--
-- Documentation: hdl/owr_dl/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_dl_lsm is
    generic (
        ErrorResetCycles_g : positive := 640;
        TimeoutCycles_g    : positive := 1280
    );
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Management parameters
        Cfg_PortReset    : in    std_logic;
        Cfg_LinkDisabled : in    std_logic;
        Cfg_LinkStart    : in    std_logic;
        Cfg_AutoStart    : in    std_logic;
        -- Encoding layer status and received characters
        Rx_GotNull       : in    std_logic;
        Rx_ParityErr     : in    std_logic;
        Rx_EscErr        : in    std_logic;
        Rx_Disconnect    : in    std_logic;
        RxChar_Valid     : in    std_logic;
        RxChar_Kind      : in    CharKind_t;
        -- Flow control manager and transmit scheduler
        Fc_CreditErr     : in    std_logic;
        Tx_SentNull      : in    std_logic;
        Tx_SentFct       : in    std_logic;
        -- Encoding layer control
        TxEnable         : out   std_logic;
        RxEnable         : out   std_logic;
        -- State
        State            : out   LinkState_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl_lsm is

    type LinkFsm_t is (ErrorReset_s, ErrorWait_s, Ready_s, Started_s, Connecting_s, Run_s);

    constant TimerMax_c : positive := maximum(ErrorResetCycles_g, TimeoutCycles_g);

    type TwoProcess_r is record
        Fsm      : LinkFsm_t;
        Timer    : natural range 0 to TimerMax_c;
        GotFct   : std_logic;
        SentNull : std_logic;
        SentFct  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    function stateCode (fsm : LinkFsm_t) return LinkState_t is
    begin

        case fsm is

            when ErrorWait_s =>
                return StateErrorWait_c;

            when Ready_s =>
                return StateReady_c;

            when Started_s =>
                return StateStarted_c;

            when Connecting_s =>
                return StateConnecting_c;

            when Run_s =>
                return StateRun_c;

            when others =>
                return StateErrorReset_c;

        end case;

    end function;

begin

    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Fct_v     : boolean;
        variable NChar_v   : boolean;
        variable Bc_v      : boolean;
        variable Error_v   : boolean;
        variable Elapsed_v : boolean;
    begin
        v := r;

        -- Received conditions of the Encoding layer (only after gotNull, ECSS Figure 5-19 note 2)
        Fct_v   := RxChar_Valid = '1' and RxChar_Kind = KindFct_c;
        NChar_v := RxChar_Valid = '1' and (RxChar_Kind = KindData_c or RxChar_Kind = KindEop_c or
                                           RxChar_Kind = KindEep_c);
        Bc_v    := RxChar_Valid = '1' and RxChar_Kind = KindBc_c;

        -- Error exits common to all states after ErrorReset, in the order of the standard
        Error_v := Cfg_LinkDisabled = '1' or Rx_Disconnect = '1' or Rx_ParityErr = '1' or Rx_EscErr = '1';

        -- Timer of the current state
        if r.Timer /= 0 then
            v.Timer := r.Timer - 1;
        end if;
        Elapsed_v := r.Timer = 0;

        case r.Fsm is

            when ErrorReset_s =>
                -- ECSS 5.5.7.2: transmitter and receiver disabled, credits zero, gotFCT cleared
                v.GotFct := '0';
                if Elapsed_v and Cfg_LinkDisabled = '0' then
                    v.Fsm   := ErrorWait_s;
                    v.Timer := TimeoutCycles_g - 1;
                end if;

            when ErrorWait_s =>
                -- ECSS 5.5.7.3
                if Error_v or Fct_v or NChar_v or Bc_v then
                    v.Fsm := ErrorReset_s;
                elsif Elapsed_v then
                    v.Fsm := Ready_s;
                end if;

            when Ready_s =>
                -- ECSS 5.5.7.4
                if Error_v or Fct_v or NChar_v or Bc_v then
                    v.Fsm := ErrorReset_s;
                elsif Cfg_LinkStart = '1' or (Cfg_AutoStart = '1' and Rx_GotNull = '1') then
                    v.Fsm      := Started_s;
                    v.Timer    := TimeoutCycles_g - 1;
                    v.SentNull := '0';
                end if;

            when Started_s =>
                -- ECSS 5.5.7.5
                if Tx_SentNull = '1' then
                    v.SentNull := '1';
                end if;
                if Error_v or Fct_v or NChar_v or Bc_v then
                    v.Fsm := ErrorReset_s;
                elsif r.SentNull = '1' and Rx_GotNull = '1' then
                    v.Fsm     := Connecting_s;
                    v.Timer   := TimeoutCycles_g - 1;
                    v.SentFct := '0';
                elsif Elapsed_v then
                    v.Fsm := ErrorReset_s;
                end if;

            when Connecting_s =>
                -- ECSS 5.5.7.6
                if Tx_SentFct = '1' then
                    v.SentFct := '1';
                end if;
                if Fct_v then
                    v.GotFct := '1';
                end if;
                if Error_v then
                    v.Fsm := ErrorReset_s;
                elsif r.SentFct = '1' and r.GotFct = '1' then
                    v.Fsm := Run_s;
                elsif NChar_v or Bc_v then
                    v.Fsm := ErrorReset_s;
                elsif Elapsed_v then
                    v.Fsm := ErrorReset_s;
                end if;

            when Run_s =>
                -- ECSS 5.5.7.7
                if Error_v or Fc_CreditErr = '1' then
                    v.Fsm := ErrorReset_s;
                end if;

            -- Recovery state of the safe encoding
            when others =>
                v.Fsm := ErrorReset_s;

        end case;

        -- Port reset (ECSS 5.5.7.1e)
        if Cfg_PortReset = '1' then
            v.Fsm := ErrorReset_s;
        end if;

        -- Entry to ErrorReset starts the 6.4 us timer
        if v.Fsm = ErrorReset_s and (r.Fsm /= ErrorReset_s or Cfg_PortReset = '1') then
            v.Timer := ErrorResetCycles_g - 1;
        end if;

        r_next <= v;
    end process;

    -- Outputs
    TxEnable <= '1' when r.Fsm = Started_s or r.Fsm = Connecting_s or r.Fsm = Run_s else '0';
    RxEnable <= '0' when r.Fsm = ErrorReset_s else '1';

    State <= stateCode(r.Fsm);

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm      <= ErrorReset_s;
                r.Timer    <= ErrorResetCycles_g - 1;
                r.GotFct   <= '0';
                r.SentNull <= '0';
                r.SentFct  <= '0';
            end if;
        end if;
    end process;

end architecture;
