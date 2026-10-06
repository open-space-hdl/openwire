---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Control object of the Data-Strobe far-end models (owr_tb_ds_bfm) shared by the models and the test
-- sequencers, and helpers that use it.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_tb_ds_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_tb_farend_pkg is

    shared variable FarEnd_v : TbFarEnd_t;

    -- Waits until the transmit queue of the model is empty and the last character has been sent
    procedure tbWaitTxEmpty (idx : natural);

    -- Number of received characters of one kind in the log, starting at entry first
    impure function tbRxCountKind (
        idx   : natural;
        kind  : TbCharKind_t;
        first : natural := 0) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_tb_farend_pkg is

    procedure tbWaitTxEmpty (idx : natural) is
    begin

        while FarEnd_v.txCount(idx) > 0 loop
            wait for 10 ns;
        end loop;

        -- Longest character: 14 bits
        wait for 14 * FarEnd_v.getBitPeriod(idx);
    end procedure;

    impure function tbRxCountKind (
        idx   : natural;
        kind  : TbCharKind_t;
        first : natural := 0) return natural is
        variable Cnt_v : natural := 0;
    begin

        for i in first to FarEnd_v.rxCount(idx) - 1 loop
            if FarEnd_v.rxGet(idx, i).Kind = kind then
                Cnt_v := Cnt_v + 1;
            end if;
        end loop;

        return Cnt_v;
    end function;

end package body;
