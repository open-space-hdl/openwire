---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Link error recovery state machine (DL-7) of the SpaceWire Data Link layer: Normal and Recovery,
-- starts the recovery actions of the transmit scheduler and the receive handler and records the
-- cause of the error (ECSS-E-ST-50-12C Rev.1 clause 5.5.8).
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
entity owr_dl_rec is
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Link state, management parameters, errors
        State            : in    LinkState_t;
        Cfg_PortReset    : in    std_logic;
        Cfg_LinkDisabled : in    std_logic;
        Rx_Disconnect    : in    std_logic;
        Rx_ParityErr     : in    std_logic;
        Rx_EscErr        : in    std_logic;
        Fc_CreditErr     : in    std_logic;
        -- Recovery actions
        Rec_Start        : out   std_logic;
        Tx_RecBusy       : in    std_logic;
        Rx_RecBusy       : in    std_logic;
        -- Status
        Stat_Recovery    : out   std_logic;
        Stat_Cause       : out   ErrCause_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl_rec is

    type RecFsm_t is (Normal_s, Starting_s, Recovery_s);

    type TwoProcess_r is record
        Fsm   : RecFsm_t;
        Start : std_logic;
        Cause : ErrCause_t;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Cause_v : ErrCause_t;
    begin
        v       := r;
        v.Start := '0';

        -- Error in Run, in the order of ECSS 5.5.7.7b
        Cause_v := CauseNone_c;
        if State = StateRun_c then
            if Cfg_LinkDisabled = '1' then
                Cause_v := CauseLinkDisabled_c;
            elsif Rx_Disconnect = '1' then
                Cause_v := CauseDisconnect_c;
            elsif Rx_ParityErr = '1' then
                Cause_v := CauseParity_c;
            elsif Rx_EscErr = '1' then
                Cause_v := CauseEsc_c;
            elsif Fc_CreditErr = '1' then
                Cause_v := CauseCredit_c;
            end if;
        end if;

        case r.Fsm is

            when Normal_s =>
                null;

            when Starting_s =>
                -- The recovery actions are registered one cycle after the start
                v.Fsm := Recovery_s;

            when Recovery_s =>
                -- ECSS 5.5.8.4b: back to Normal when all recovery actions are complete
                if Tx_RecBusy = '0' and Rx_RecBusy = '0' then
                    v.Fsm := Normal_s;
                end if;

            when others =>
                v.Fsm := Normal_s;

        end case;

        -- ECSS 5.5.8.3b: Normal to Recovery; a new error during the recovery restarts the actions
        if Cause_v /= CauseNone_c then
            v.Fsm   := Starting_s;
            v.Start := '1';
            v.Cause := Cause_v;
        end if;

        -- ECSS 5.5.8.2
        if Cfg_PortReset = '1' then
            v.Fsm   := Normal_s;
            v.Start := '0';
        end if;

        r_next <= v;
    end process;

    Rec_Start     <= r.Start;
    Stat_Recovery <= '0' when r.Fsm = Normal_s else '1';
    Stat_Cause    <= r.Cause;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm   <= Normal_s;
                r.Start <= '0';
                r.Cause <= CauseNone_c;
            end if;
        end if;
    end process;

end architecture;
