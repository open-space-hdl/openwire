---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Flow control manager (DL-4) of the SpaceWire Data Link layer: transmit and receive credit
-- counters, FCT requests from the room in the receive FIFO and credit errors
-- (ECSS-E-ST-50-12C Rev.1 clauses 5.5.4 and 5.5.5).
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
entity owr_dl_fc is
    generic (
        RxFifoDepth_g : positive := 64
    );
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Link state
        State         : in    LinkState_t;
        -- Received characters of the Encoding layer
        RxChar_Valid  : in    std_logic;
        RxChar_Kind   : in    CharKind_t;
        -- Sent characters (transmit scheduler)
        Tx_FctSent    : in    std_logic;
        Tx_NCharSent  : in    std_logic;
        -- Receive FIFO fill level and pending EEP (receive handler)
        RxFifo_Level  : in    natural range 0 to RxFifoDepth_g;
        Rx_EepPending : in    std_logic;
        -- Outputs
        FctRequest    : out   std_logic;
        TxCreditAvail : out   std_logic;
        RxCreditAvail : out   std_logic;
        CreditErr     : out   std_logic;
        TxCredit      : out   std_logic_vector(5 downto 0);
        RxCredit      : out   std_logic_vector(5 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl_fc is

    type TwoProcess_r is record
        TxCredit  : natural range 0 to CreditMax_c;
        RxCredit  : natural range 0 to CreditMax_c;
        CreditErr : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Room in the receive FIFO beyond the outstanding credit
    signal Room     : integer range -CreditMax_c - 2 to RxFifoDepth_g;
    signal Reserved : natural range 0 to 2;

begin

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Active_v : boolean;
        variable NChar_v  : boolean;
    begin
        v           := r;
        v.CreditErr := '0';

        Active_v := State = StateConnecting_c or State = StateRun_c;
        NChar_v  := RxChar_Valid = '1' and (RxChar_Kind = KindData_c or RxChar_Kind = KindEop_c or
                                            RxChar_Kind = KindEep_c);

        -- Transmit credit (ECSS 5.5.4e, h, j)
        if Active_v and RxChar_Valid = '1' and RxChar_Kind = KindFct_c then
            if r.TxCredit > CreditMax_c - CreditPerFct_c then
                v.CreditErr := '1';
                v.TxCredit  := CreditMax_c;
            else
                v.TxCredit := r.TxCredit + CreditPerFct_c;
            end if;
        end if;
        if Tx_NCharSent = '1' and v.TxCredit /= 0 then
            v.TxCredit := v.TxCredit - 1;
        end if;

        -- Receive credit (ECSS 5.5.4l, n, 5.5.5a.1)
        if Tx_FctSent = '1' then
            -- Never above 56: FCTs are only requested up to a credit of 48 (the limit also covers delta cycles)
            v.RxCredit := minimum(CreditMax_c, r.RxCredit + CreditPerFct_c);
        end if;
        if State = StateRun_c and NChar_v then
            if r.RxCredit = 0 then
                v.CreditErr := '1';
            else
                v.RxCredit := v.RxCredit - 1;
            end if;
        end if;

        -- Both counters are zero in ErrorReset (ECSS 5.5.4g, m)
        if State = StateErrorReset_c then
            v.TxCredit := 0;
            v.RxCredit := 0;
        end if;

        r_next <= v;
    end process;

    -- FCT request (ECSS 5.5.4c, k, p): room for eight more N-Chars beyond the credit; one N-Char may be on its way
    -- into the FIFO and a pending EEP needs one place
    Reserved <= 2 when Rx_EepPending = '1' else 1;
    Room     <= RxFifoDepth_g - RxFifo_Level - Reserved - r.RxCredit;

    FctRequest <= '1' when (State = StateConnecting_c or State = StateRun_c) and
                           r.RxCredit <= CreditMax_c - CreditPerFct_c and Room >= CreditPerFct_c else
                  '0';

    TxCreditAvail <= '1' when r.TxCredit /= 0 else '0';
    RxCreditAvail <= '1' when r.RxCredit /= 0 else '0';
    CreditErr     <= r.CreditErr;
    TxCredit      <= std_logic_vector(to_unsigned(r.TxCredit, 6));
    RxCredit      <= std_logic_vector(to_unsigned(r.RxCredit, 6));

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.TxCredit  <= 0;
                r.RxCredit  <= 0;
                r.CreditErr <= '0';
            end if;
        end if;
    end process;

end architecture;
