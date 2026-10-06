---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types of the Network layer testbench: inputs and outputs of one owr_ni instance and the log
-- indices of its sent codes and indications.
--
-- Documentation: hdl/owr_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_ni_tb_pkg is

    constant EccWidth_c : positive := eccCodewordWidth(8);

    type NiIn_t is record
        -- User requests (UserClk)
        TcData      : std_logic_vector(5 downto 0);
        TcValid     : std_logic;
        IntData     : std_logic_vector(4 downto 0);
        IntValid    : std_logic;
        AckData     : std_logic_vector(4 downto 0);
        AckValid    : std_logic;
        -- Ready of the indication ports (UserClk)
        IndReady    : std_logic;
        -- MIB (LinkClk)
        MibTcValid  : std_logic;
        MibTcValue  : std_logic_vector(5 downto 0);
        MibIntValid : std_logic;
        MibIntIid   : std_logic_vector(4 downto 0);
        MibAckValid : std_logic;
        MibAckIid   : std_logic_vector(4 downto 0);
        PortReset   : std_logic;
        AckMode     : std_logic;
        IntTick     : std_logic_vector(15 downto 0);
        IntHoldoff  : std_logic_vector(15 downto 0);
        AckDelay    : std_logic_vector(15 downto 0);
        -- Data Link layer model: ready of the broadcast slot, discard outside Run, received codes
        DlReady     : std_logic;
        DlDiscard   : std_logic;
        RxData      : std_logic_vector(7 downto 0);
        RxValid     : std_logic;
        -- Error injection
        InjReqFlip  : std_logic_vector(EccWidth_c - 1 downto 0);
        InjReqValid : std_logic;
        InjIndFlip  : std_logic_vector(EccWidth_c - 1 downto 0);
        InjIndValid : std_logic;
    end record;

    constant NiInInit_c : NiIn_t := (
        TcData      => (others => '0'),
        TcValid     => '0',
        IntData     => (others => '0'),
        IntValid    => '0',
        AckData     => (others => '0'),
        AckValid    => '0',
        IndReady    => '1',
        MibTcValid  => '0',
        MibTcValue  => (others => '0'),
        MibIntValid => '0',
        MibIntIid   => (others => '0'),
        MibAckValid => '0',
        MibAckIid   => (others => '0'),
        PortReset   => '0',
        AckMode     => '0',
        IntTick     => x"0001",
        IntHoldoff  => x"0000",
        AckDelay    => x"0000",
        DlReady     => '1',
        DlDiscard   => '0',
        RxData      => (others => '0'),
        RxValid     => '0',
        InjReqFlip  => (others => '0'),
        InjReqValid => '0',
        InjIndFlip  => (others => '0'),
        InjIndValid => '0'
    );

    type NiOut_t is record
        TcReady    : std_logic;
        IntReady   : std_logic;
        AckReady   : std_logic;
        TimeCode   : std_logic_vector(5 downto 0);
        IntActive  : std_logic_vector(31 downto 0);
        CntTcValid : natural;
        CntTcInv   : natural;
        CntIntRx   : natural;
        CntAckRx   : natural;
        CntIntDisc : natural;
        CntAckDisc : natural;
        CntIgnored : natural;
        CntIndOvf  : natural;
        CntReqSec  : natural;
        CntReqDed  : natural;
        CntIndSec  : natural;
        CntIndDed  : natural;
        LastAckIid : std_logic_vector(4 downto 0);
    end record;

    constant NiOutInit_c : NiOut_t := (
        TcReady    => '0',
        IntReady   => '0',
        AckReady   => '0',
        TimeCode   => (others => '0'),
        IntActive  => (others => '0'),
        CntTcValid => 0,
        CntTcInv   => 0,
        CntIntRx   => 0,
        CntAckRx   => 0,
        CntIntDisc => 0,
        CntAckDisc => 0,
        CntIgnored => 0,
        CntIndOvf  => 0,
        CntReqSec  => 0,
        CntReqDed  => 0,
        CntIndSec  => 0,
        CntIndDed  => 0,
        LastAckIid => (others => '0')
    );

    -- Logs in owr_tb_ds_pkg.FarEnd_v: codes passed to the Data Link layer and indications (kind and value) of
    -- instance 1 (all services) and instance 2 (no services)
    constant LogTx1_c  : natural := 0;
    constant LogInd1_c : natural := 1;
    constant LogTx2_c  : natural := 2;
    constant LogInd2_c : natural := 3;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_ni_tb_pkg is

end package body;
