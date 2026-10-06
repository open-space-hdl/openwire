---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register file of the OpenWire MIB (MG-1) with the EDAC monitor (MG-3) in LinkClk: configuration,
-- control and status parameters of ECSS-E-ST-50-12C Rev.1 clause 5.7 for a node, sticky flags,
-- counters, broadcast service requests and the interrupt output.
--
-- Documentation: hdl/owr_mib/docs/architecture.md, hdl/owr_mib/docs/register_map.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.owr_pkg.all;
    use work.owr_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_mib_regs is
    generic (
        LinkClkFreq_g   : real                    := 100.0e6;
        TxFifoDepth_g   : positive                := 64;
        RxFifoDepth_g   : positive                := 64;
        TimeCodes_g     : boolean                 := true;
        Interrupts_g    : boolean                 := true;
        IntTimerWidth_g : positive range 1 to 30  := 16;
        LinkDisabled_g  : boolean                 := false;
        LinkStart_g     : boolean                 := false;
        AutoStart_g     : boolean                 := false;
        RunDiv_g        : positive range 1 to 255 := 1
    );
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Register bus
        Rb_Addr          : in    std_logic_vector(7 downto 0);
        Rb_Wr            : in    std_logic;
        Rb_ByteEna       : in    std_logic_vector(3 downto 0);
        Rb_WrData        : in    std_logic_vector(31 downto 0);
        Rb_Rd            : in    std_logic;
        Rb_RdData        : out   std_logic_vector(31 downto 0);
        Rb_RdValid       : out   std_logic;
        -- Configuration and control
        Cfg_PortReset    : out   std_logic;
        Cfg_LinkDisabled : out   std_logic;
        Cfg_LinkStart    : out   std_logic;
        Cfg_AutoStart    : out   std_logic;
        Cfg_DriverEn     : out   std_logic;
        Cfg_ReceiverEn   : out   std_logic;
        Cfg_Loopback     : out   std_logic;
        Cfg_RunDiv       : out   std_logic_vector(7 downto 0);
        Cfg_AckMode      : out   std_logic;
        Cfg_IntTick      : out   std_logic_vector(15 downto 0);
        Cfg_IntHoldoff   : out   std_logic_vector(IntTimerWidth_g - 1 downto 0);
        Cfg_AckDelay     : out   std_logic_vector(IntTimerWidth_g - 1 downto 0);
        -- Requests of the broadcast services
        Mib_TcValid      : out   std_logic;
        Mib_TcValue      : out   std_logic_vector(5 downto 0);
        Mib_IntValid     : out   std_logic;
        Mib_IntIid       : out   std_logic_vector(4 downto 0);
        Mib_AckValid     : out   std_logic;
        Mib_AckIid       : out   std_logic_vector(4 downto 0);
        -- Status
        Stat_State       : in    LinkState_t;
        Stat_Recovery    : in    std_logic;
        Stat_GotNull     : in    std_logic;
        Stat_Spill       : in    std_logic;
        Stat_Cause       : in    ErrCause_t;
        Stat_TxCredit    : in    std_logic_vector(5 downto 0);
        Stat_RxCredit    : in    std_logic_vector(5 downto 0);
        Stat_TxLevel     : in    std_logic_vector(15 downto 0);
        Stat_RxLevel     : in    std_logic_vector(15 downto 0);
        Stat_TimeCode    : in    std_logic_vector(5 downto 0);
        Stat_IntActive   : in    std_logic_vector(31 downto 0);
        -- Events
        Ev_Disconnect    : in    std_logic;
        Ev_ParityErr     : in    std_logic;
        Ev_EscErr        : in    std_logic;
        Ev_CreditErr     : in    std_logic;
        Ev_TcValid       : in    std_logic;
        Ev_TcInvalid     : in    std_logic;
        Ev_IntRx         : in    std_logic;
        Ev_AckRx         : in    std_logic;
        Ev_AckRxIid      : in    std_logic_vector(4 downto 0);
        Ev_BcDiscarded   : in    std_logic;
        Ev_BcIgnored     : in    std_logic;
        Ev_IntReqDisc    : in    std_logic;
        Ev_AckReqDisc    : in    std_logic;
        Ev_IndOverflow   : in    std_logic;
        Ev_RxOverflow    : in    std_logic;
        -- EDAC: events of the 6 channels (in LinkClk) and injection commands
        Ecc_Sec          : in    std_logic_vector(5 downto 0);
        Ecc_Ded          : in    std_logic_vector(5 downto 0);
        Inj_Valid        : out   std_logic_vector(5 downto 0);
        Inj_Double       : out   std_logic;
        -- Interrupt
        Irq              : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_mib_regs is

    constant InitDiv_c    : positive                     := initDivider(LinkClkFreq_g);
    constant IntTick_c    : natural                      := maximum(1, timeCycles(1.0e-6, LinkClkFreq_g));
    constant KHz_c        : natural                      := integer(LinkClkFreq_g / 1000.0);
    constant TimerWidth_c : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(IntTimerWidth_g, 5));

    type TwoProcess_r is record
        -- Configuration
        LinkDisabled : std_logic;
        LinkStart    : std_logic;
        AutoStart    : std_logic;
        DriverEn     : std_logic;
        ReceiverEn   : std_logic;
        Loopback     : std_logic;
        RunDiv       : std_logic_vector(7 downto 0);
        AckMode      : std_logic;
        IntTick      : std_logic_vector(15 downto 0);
        Holdoff      : std_logic_vector(IntTimerWidth_g - 1 downto 0);
        AckDelay     : std_logic_vector(IntTimerWidth_g - 1 downto 0);
        ErrIrqEn     : std_logic_vector(3 downto 0);
        EvtIrqEn     : std_logic_vector(13 downto 0);
        EccSelect    : std_logic_vector(2 downto 0);
        -- Commands
        PortReset    : std_logic;
        TcValid      : std_logic;
        TcValue      : std_logic_vector(5 downto 0);
        IntValid     : std_logic;
        IntIid       : std_logic_vector(4 downto 0);
        AckValid     : std_logic;
        AckIid       : std_logic_vector(4 downto 0);
        InjValid     : std_logic_vector(5 downto 0);
        InjDouble    : std_logic;
        EccClr       : std_logic;
        EccRdClr     : std_logic;
        -- Status
        Errors       : std_logic_vector(3 downto 0);
        Events       : std_logic_vector(13 downto 0);
        AckRcvd      : std_logic_vector(31 downto 0);
        CntDisc      : unsigned(7 downto 0);
        CntParity    : unsigned(7 downto 0);
        CntEsc       : unsigned(7 downto 0);
        CntCredit    : unsigned(7 downto 0);
        CntRun       : unsigned(15 downto 0);
        CntRecovery  : unsigned(15 downto 0);
        CntTcValid   : unsigned(15 downto 0);
        CntTcInvalid : unsigned(15 downto 0);
        PrevRun      : std_logic;
        PrevRecovery : std_logic;
        -- Read port: address registered, data one cycle later (the EDAC monitor has a read latency of one cycle)
        RdPend       : std_logic;
        RdAddr       : natural range 0 to 255;
        RdValid      : std_logic;
        RdData       : std_logic_vector(31 downto 0);
        Irq          : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- EDAC monitor
    signal EccDedSticky : std_logic_vector(5 downto 0);
    signal EccEvtSec    : std_logic;
    signal EccEvtDed    : std_logic;
    signal EccSecCnt    : std_logic_vector(15 downto 0);
    signal EccDedCnt    : std_logic_vector(15 downto 0);

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- Saturating increment
    function incSat (cnt : unsigned) return unsigned is
    begin
        if cnt = (cnt'range => '1') then
            return cnt;
        else
            return cnt + 1;
        end if;
    end function;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Wr_v    : boolean;
        variable Addr_v  : natural range 0 to 255;
        variable Data_v  : std_logic_vector(31 downto 0);
        variable Rd_v    : std_logic_vector(31 downto 0);
        variable Run_v   : std_logic;
        variable EvSet_v : std_logic_vector(13 downto 0);
        variable ErSet_v : std_logic_vector(3 downto 0);
    begin
        v           := r;
        v.PortReset := '0';
        v.TcValid   := '0';
        v.IntValid  := '0';
        v.AckValid  := '0';
        v.InjValid  := (others => '0');
        v.EccClr    := '0';
        v.EccRdClr  := '0';
        v.RdValid   := '0';
        v.RdPend    := Rb_Rd;

        Addr_v := to_integer(unsigned(Rb_Addr(7 downto 2) & "00"));
        if Rb_Rd = '1' then
            v.RdAddr := Addr_v;
        end if;
        Wr_v := Rb_Wr = '1';
        -- Registers are written as 32-bit words; the byte enables are not used
        Data_v := Rb_WrData;

        -- Events and counters
        ErSet_v := Ev_CreditErr & Ev_EscErr & Ev_ParityErr & Ev_Disconnect;
        Run_v   := toSl(Stat_State = StateRun_c);
        EvSet_v := EccEvtDed & EccEvtSec & Ev_RxOverflow & Ev_IndOverflow & Ev_AckReqDisc & Ev_IntReqDisc &
                   Ev_BcIgnored & Ev_BcDiscarded & Ev_AckRx & Ev_IntRx & Ev_TcInvalid & Ev_TcValid &
                   (r.PrevRun and not Run_v) & (Run_v and not r.PrevRun);

        if Ev_Disconnect = '1' then
            v.CntDisc := incSat(r.CntDisc);
        end if;
        if Ev_ParityErr = '1' then
            v.CntParity := incSat(r.CntParity);
        end if;
        if Ev_EscErr = '1' then
            v.CntEsc := incSat(r.CntEsc);
        end if;
        if Ev_CreditErr = '1' then
            v.CntCredit := incSat(r.CntCredit);
        end if;
        if Run_v = '1' and r.PrevRun = '0' then
            v.CntRun := incSat(r.CntRun);
        end if;
        if Stat_Recovery = '1' and r.PrevRecovery = '0' then
            v.CntRecovery := incSat(r.CntRecovery);
        end if;
        if Ev_TcValid = '1' then
            v.CntTcValid := incSat(r.CntTcValid);
        end if;
        if Ev_TcInvalid = '1' then
            v.CntTcInvalid := incSat(r.CntTcInvalid);
        end if;
        v.PrevRun      := Run_v;
        v.PrevRecovery := Stat_Recovery;

        -- Writes (W1C before the set of the same cycle, so that an event is never lost)
        if Wr_v then

            case Addr_v is

                when RegPortCtrl_c =>
                    v.PortReset    := Data_v(PortCtrlPortReset_c);
                    v.LinkDisabled := Data_v(PortCtrlLinkDisabled_c);
                    v.LinkStart    := Data_v(PortCtrlLinkStart_c);
                    v.AutoStart    := Data_v(PortCtrlAutoStart_c);
                    v.DriverEn     := Data_v(PortCtrlDriverEn_c);
                    v.ReceiverEn   := Data_v(PortCtrlReceiverEn_c);
                    v.Loopback     := Data_v(PortCtrlLoopback_c);

                when RegLinkSpeed_c =>
                    v.RunDiv := Data_v(LinkSpeedRunDivHi_c downto LinkSpeedRunDivLo_c);

                when RegErrors_c =>
                    v.Errors := r.Errors and not Data_v(3 downto 0);

                when RegErrorCounts_c =>
                    v.CntDisc   := (others => '0');
                    v.CntParity := (others => '0');
                    v.CntEsc    := (others => '0');
                    v.CntCredit := (others => '0');

                when RegLinkCounts_c =>
                    v.CntRun      := (others => '0');
                    v.CntRecovery := (others => '0');

                when RegEvents_c =>
                    v.Events := r.Events and not Data_v(13 downto 0);

                when RegErrorsIrqEn_c =>
                    v.ErrIrqEn := Data_v(3 downto 0);

                when RegEventsIrqEn_c =>
                    v.EvtIrqEn := Data_v(13 downto 0);

                when RegTcSend_c =>
                    v.TcValid := '1';
                    v.TcValue := Data_v(TcSendValueHi_c downto TcSendValueLo_c);

                when RegTcCounts_c =>
                    v.CntTcValid   := (others => '0');
                    v.CntTcInvalid := (others => '0');

                when RegIntCtrl_c =>
                    v.AckMode := Data_v(IntCtrlAckMode_c);

                when RegIntTick_c =>
                    v.IntTick := Data_v(15 downto 0);

                when RegIntHoldoff_c =>
                    v.Holdoff := Data_v(IntTimerWidth_g - 1 downto 0);

                when RegIntAckDelay_c =>
                    v.AckDelay := Data_v(IntTimerWidth_g - 1 downto 0);

                when RegIntSend_c =>
                    v.IntValid := '1';
                    v.IntIid   := Data_v(IntSendIidHi_c downto IntSendIidLo_c);

                when RegIntAck_c =>
                    v.AckValid := '1';
                    v.AckIid   := Data_v(IntAckIidHi_c downto IntAckIidLo_c);

                when RegAckReceived_c =>
                    v.AckRcvd := r.AckRcvd and not Data_v;

                when RegEccStatus_c =>
                    v.EccClr := '1';

                when RegEccSelect_c =>
                    v.EccSelect := Data_v(EccSelectChannelHi_c downto EccSelectChannelLo_c);

                when RegEccCount_c =>
                    v.EccRdClr := '1';

                when RegEccInject_c =>
                    if Data_v(EccInjectSingle_c) = '1' or Data_v(EccInjectDouble_c) = '1' then

                        for i in 0 to 5 loop
                            if to_integer(unsigned(Data_v(EccInjectChannelHi_c downto EccInjectChannelLo_c))) = i then
                                v.InjValid(i) := '1';
                            end if;
                        end loop;

                        v.InjDouble := Data_v(EccInjectDouble_c);
                    end if;

                when others =>
                    null;

            end case;

        end if;

        -- Sticky flags set by events
        v.Errors := v.Errors or ErSet_v;
        v.Events := v.Events or EvSet_v;
        if Ev_AckRx = '1' then
            v.AckRcvd(to_integer(unsigned(Ev_AckRxIid))) := '1';
        end if;

        -- Reads
        Rd_v := (others => '0');

        case r.RdAddr is

            when RegId_c =>
                Rd_v := RegMapId_c;

            when RegGenerics_c =>
                Rd_v(GenericsTimeCodes_c)                                        := toSl(TimeCodes_g);
                Rd_v(GenericsInterrupts_c)                                       := toSl(Interrupts_g);
                Rd_v(GenericsIntTimerWidthHi_c downto GenericsIntTimerWidthLo_c) := TimerWidth_c;

            when RegFifoDepths_c =>
                Rd_v(FifoDepthsTxHi_c downto FifoDepthsTxLo_c) := std_logic_vector(to_unsigned(TxFifoDepth_g, 16));
                Rd_v(FifoDepthsRxHi_c downto FifoDepthsRxLo_c) := std_logic_vector(to_unsigned(RxFifoDepth_g, 16));

            when RegClkFreq_c =>
                Rd_v := std_logic_vector(to_unsigned(KHz_c, 32));

            when RegPortCtrl_c =>
                Rd_v(PortCtrlLinkDisabled_c) := r.LinkDisabled;
                Rd_v(PortCtrlLinkStart_c)    := r.LinkStart;
                Rd_v(PortCtrlAutoStart_c)    := r.AutoStart;
                Rd_v(PortCtrlDriverEn_c)     := r.DriverEn;
                Rd_v(PortCtrlReceiverEn_c)   := r.ReceiverEn;
                Rd_v(PortCtrlLoopback_c)     := r.Loopback;

            when RegLinkSpeed_c =>
                Rd_v(LinkSpeedRunDivHi_c downto LinkSpeedRunDivLo_c)   := r.RunDiv;
                Rd_v(LinkSpeedInitDivHi_c downto LinkSpeedInitDivLo_c) := std_logic_vector(to_unsigned(InitDiv_c, 8));

            when RegPortStatus_c =>
                Rd_v(PortStatusLinkStateHi_c downto PortStatusLinkStateLo_c) := Stat_State;
                Rd_v(PortStatusRecovery_c)                                   := Stat_Recovery;
                Rd_v(PortStatusGotNull_c)                                    := Stat_GotNull;
                Rd_v(PortStatusSpill_c)                                      := Stat_Spill;
                Rd_v(PortStatusLastCauseHi_c downto PortStatusLastCauseLo_c) := Stat_Cause;

            when RegCredit_c =>
                Rd_v(CreditTxCreditHi_c downto CreditTxCreditLo_c) := Stat_TxCredit;
                Rd_v(CreditRxCreditHi_c downto CreditRxCreditLo_c) := Stat_RxCredit;

            when RegFifoLevels_c =>
                Rd_v(FifoLevelsTxHi_c downto FifoLevelsTxLo_c) := Stat_TxLevel;
                Rd_v(FifoLevelsRxHi_c downto FifoLevelsRxLo_c) := Stat_RxLevel;

            when RegErrors_c =>
                Rd_v(3 downto 0) := r.Errors;

            when RegErrorCounts_c =>
                Rd_v := std_logic_vector(r.CntCredit & r.CntEsc & r.CntParity & r.CntDisc);

            when RegLinkCounts_c =>
                Rd_v := std_logic_vector(r.CntRecovery & r.CntRun);

            when RegEvents_c =>
                Rd_v(13 downto 0) := r.Events;

            when RegErrorsIrqEn_c =>
                Rd_v(3 downto 0) := r.ErrIrqEn;

            when RegEventsIrqEn_c =>
                Rd_v(13 downto 0) := r.EvtIrqEn;

            when RegIrqStatus_c =>
                Rd_v(IrqStatusIrq_c) := r.Irq;

            when RegTimeCode_c =>
                Rd_v(TimeCodeValueHi_c downto TimeCodeValueLo_c) := Stat_TimeCode;

            when RegTcCounts_c =>
                Rd_v := std_logic_vector(r.CntTcInvalid & r.CntTcValid);

            when RegIntCtrl_c =>
                Rd_v(IntCtrlAckMode_c) := r.AckMode;

            when RegIntTick_c =>
                Rd_v(15 downto 0) := r.IntTick;

            when RegIntHoldoff_c =>
                Rd_v(IntTimerWidth_g - 1 downto 0) := r.Holdoff;

            when RegIntAckDelay_c =>
                Rd_v(IntTimerWidth_g - 1 downto 0) := r.AckDelay;

            when RegIntActive_c =>
                Rd_v := Stat_IntActive;

            when RegAckReceived_c =>
                Rd_v := r.AckRcvd;

            when RegEccStatus_c =>
                Rd_v(5 downto 0) := EccDedSticky;

            when RegEccSelect_c =>
                Rd_v(EccSelectChannelHi_c downto EccSelectChannelLo_c) := r.EccSelect;

            when RegEccCount_c =>
                Rd_v := EccDedCnt & EccSecCnt;

            when others =>
                null;

        end case;

        if r.RdPend = '1' then
            v.RdValid := '1';
            v.RdData  := Rd_v;
        end if;

        -- Interrupt output
        v.Irq := toSl((r.Errors and r.ErrIrqEn) /= "0000" or (r.Events and r.EvtIrqEn) /= (13 downto 0 => '0'));

        r_next <= v;
    end process;

    -- Outputs
    Rb_RdData        <= r.RdData;
    Rb_RdValid       <= r.RdValid;
    Cfg_PortReset    <= r.PortReset;
    Cfg_LinkDisabled <= r.LinkDisabled;
    Cfg_LinkStart    <= r.LinkStart;
    Cfg_AutoStart    <= r.AutoStart;
    Cfg_DriverEn     <= r.DriverEn;
    Cfg_ReceiverEn   <= r.ReceiverEn;
    Cfg_Loopback     <= r.Loopback;
    Cfg_RunDiv       <= r.RunDiv;
    Cfg_AckMode      <= r.AckMode;
    Cfg_IntTick      <= r.IntTick;
    Cfg_IntHoldoff   <= r.Holdoff;
    Cfg_AckDelay     <= r.AckDelay;
    Mib_TcValid      <= r.TcValid;
    Mib_TcValue      <= r.TcValue;
    Mib_IntValid     <= r.IntValid;
    Mib_IntIid       <= r.IntIid;
    Mib_AckValid     <= r.AckValid;
    Mib_AckIid       <= r.AckIid;
    Inj_Valid        <= r.InjValid;
    Inj_Double       <= r.InjDouble;
    Irq              <= r.Irq;

    -- MG-3 EDAC monitor: the selected channel is read in every cycle
    i_ecc : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g     => 6,
            CounterWidth_g => 16
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            Clr        => r.EccClr,
            In_EccSec  => Ecc_Sec,
            In_EccDed  => Ecc_Ded,
            DedSticky  => EccDedSticky,
            Evt_Sec    => EccEvtSec,
            Evt_Ded    => EccEvtDed,
            Rd_Channel => r.EccSelect,
            Rd_Ena     => '1',
            Rd_Clr     => r.EccRdClr,
            Rd_SecCnt  => EccSecCnt,
            Rd_DedCnt  => EccDedCnt,
            Rd_Valid   => open
        );

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.LinkDisabled <= toSl(LinkDisabled_g);
                r.LinkStart    <= toSl(LinkStart_g);
                r.AutoStart    <= toSl(AutoStart_g);
                r.DriverEn     <= '1';
                r.ReceiverEn   <= '1';
                r.Loopback     <= '0';
                r.RunDiv       <= std_logic_vector(to_unsigned(RunDiv_g, 8));
                r.AckMode      <= '0';
                r.IntTick      <= std_logic_vector(to_unsigned(IntTick_c, 16));
                r.Holdoff      <= (others => '0');
                r.AckDelay     <= (others => '0');
                r.ErrIrqEn     <= (others => '0');
                r.EvtIrqEn     <= (others => '0');
                r.EccSelect    <= (others => '0');
                r.PortReset    <= '0';
                r.TcValid      <= '0';
                r.IntValid     <= '0';
                r.AckValid     <= '0';
                r.InjValid     <= (others => '0');
                r.InjDouble    <= '0';
                r.EccClr       <= '0';
                r.EccRdClr     <= '0';
                r.Errors       <= (others => '0');
                r.Events       <= (others => '0');
                r.AckRcvd      <= (others => '0');
                r.CntDisc      <= (others => '0');
                r.CntParity    <= (others => '0');
                r.CntEsc       <= (others => '0');
                r.CntCredit    <= (others => '0');
                r.CntRun       <= (others => '0');
                r.CntRecovery  <= (others => '0');
                r.CntTcValid   <= (others => '0');
                r.CntTcInvalid <= (others => '0');
                r.PrevRun      <= '0';
                r.PrevRecovery <= '0';
                r.RdPend       <= '0';
                r.RdValid      <= '0';
                r.Irq          <= '0';
            end if;
        end if;
    end process;

end architecture;
