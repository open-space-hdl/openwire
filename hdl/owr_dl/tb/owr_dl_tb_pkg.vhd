---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types and helpers of the Data Link layer testbench: control and status records of one port
-- (Encoding and Data Link layer), indices of the VVCs and of the far-end model instances.
--
-- Documentation: hdl/owr_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_dl_tb_pkg is

    constant EccWidth_c : positive := eccCodewordWidth(9);

    -- Control of one port
    type DlCtrl_t is record
        PortReset    : std_logic;
        LinkDisabled : std_logic;
        LinkStart    : std_logic;
        AutoStart    : std_logic;
        RunDiv       : std_logic_vector(7 downto 0);
        TxBcData     : std_logic_vector(7 downto 0);
        TxBcValid    : std_logic;
        InjTxFlip    : std_logic_vector(EccWidth_c - 1 downto 0);
        InjTxValid   : std_logic;
        InjRxFlip    : std_logic_vector(EccWidth_c - 1 downto 0);
        InjRxValid   : std_logic;
    end record;

    constant DlCtrlInit_c : DlCtrl_t := (
        PortReset    => '0',
        LinkDisabled => '0',
        LinkStart    => '0',
        AutoStart    => '0',
        RunDiv       => x"01",
        TxBcData     => x"00",
        TxBcValid    => '0',
        InjTxFlip    => (others => '0'),
        InjTxValid   => '0',
        InjRxFlip    => (others => '0'),
        InjRxValid   => '0'
    );

    -- Status of one port; event counters are counted by the harness
    type DlStat_t is record
        State       : LinkState_t;
        Recovery    : std_logic;
        Cause       : ErrCause_t;
        TxCredit    : natural;
        RxCredit    : natural;
        TxLevel     : natural;
        RxLevel     : natural;
        Spill       : std_logic;
        GotNull     : std_logic;
        TxBcReady   : std_logic;
        CntParity   : natural;
        CntEsc      : natural;
        CntDisc     : natural;
        CntCredit   : natural;
        CntBcDisc   : natural;
        CntRxBc     : natural;
        CntOverflow : natural;
        CntTxSec    : natural;
        CntTxDed    : natural;
        CntRxSec    : natural;
        CntRxDed    : natural;
        CntRun      : natural;
        CntRecovery : natural;
    end record;

    -- VVC instances
    constant VvcATx_c : natural := 0;
    constant VvcARx_c : natural := 1;
    constant VvcBTx_c : natural := 2;
    constant VvcBRx_c : natural := 3;

    -- Far-end model instance on the line of port A, logs of the received broadcast codes of A and B
    constant Far_c    : natural := 0;
    constant BcLogA_c : natural := 2;
    constant BcLogB_c : natural := 3;

    function stateStr (state : LinkState_t) return string;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_dl_tb_pkg is

    function stateStr (state : LinkState_t) return string is
    begin
        if state = StateErrorReset_c then
            return "ErrorReset";
        elsif state = StateErrorWait_c then
            return "ErrorWait";
        elsif state = StateReady_c then
            return "Ready";
        elsif state = StateStarted_c then
            return "Started";
        elsif state = StateConnecting_c then
            return "Connecting";
        elsif state = StateRun_c then
            return "Run";
        else
            return "invalid";
        end if;
    end function;

end package body;
