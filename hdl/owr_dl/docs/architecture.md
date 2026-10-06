# owr_dl: Architecture and Design Description

## 1. Block diagram

```text
 UserClk          |                         LinkClk
                  |
 TxUser_* ----> [DL-1 olo_ft_fifo_async] --> DL-5 owr_dl_tx -----------------> TxChar_Kind/Data (EN-1)
                  |        (DED -> EEP)       ^  ^   ^  |  SentNull/Fct/NChar   <- TxChar_Ack
                  |                  TxBc_* --+  |   |  +----> DL-4 owr_dl_fc --> FctRequest, credits
                  |                              |   |                 ^  ^
 RxUser_* <-- (DED containment) <-- [DL-2] <-- DL-6 owr_dl_rx <------- | -+-- RxChar_* (EN-2)
                  |                    In_Level ---------------------- +
                  |                            DL-3 owr_dl_lsm <-- RxChar_*, errors, Cfg_*, SentNull/Fct
                  |                              |  TxEnable, RxEnable, State
                  |                            DL-7 owr_dl_rec --> Rec_Start (DL-5, DL-6), cause
```

## 2. Link state machine (DL-3, `owr_dl_lsm`)

```text
              PortReset (any state)
                    |
                    v                  6.4 us AND NOT LinkDisabled
              +------------+ ----------------------------------> +-----------+
              | ErrorReset |                                     | ErrorWait | -- 12.8 us --+
              +------------+ <---------------------------------- +-----------+              |
                 ^  ^  ^  ^      err OR FCT/N-Char/BC                                       v
                 |  |  |  |                                                            +-------+
                 |  |  |  +----------------- err OR FCT/N-Char/BC -------------------- | Ready |
                 |  |  |                                                              +-------+
                 |  |  +-- err OR FCT/N-Char/BC OR 12.8 us --- +---------+ <-- LinkStart OR |
                 |  |                                          | Started |   (AutoStart AND gotNull)
                 |  |                                          +---------+
                 |  |                                               | gotNull AND Sent Null
                 |  +-- err OR N-Char/BC OR 12.8 us -- +------------+ <-+
                 |                                     | Connecting |
                 |                                     +------------+
                 |                                          | gotFCT AND Sent FCT
                 +-- err OR credit error ----------- +-----+ <-+
                                                     | Run |
                                                     +-----+
 err = LinkDisabled OR disconnect OR parity error OR ESC error
```

| State | Transmit Enable | Receive Enable | Characters sent | Timer |
| --- | --- | --- | --- | --- |
| ErrorReset | 0 | 0 | none | 6.4 us from entry |
| ErrorWait | 0 | 1 | none | 12.8 us from entry |
| Ready | 0 | 1 | none | none |
| Started | 1 | 1 | Nulls | 12.8 us from entry |
| Connecting | 1 | 1 | FCTs and Nulls | 12.8 us from entry |
| Run | 1 | 1 | Broadcast codes, FCTs, N-Chars, Nulls | none |

One down-counter serves all timers; it is loaded on entry to ErrorReset (6.4 us), ErrorWait, Started and Connecting
(12.8 us). With `ClkFreq_g` = 100 MHz the timers are 640 and 1280 cycles. The exit conditions of each state are
evaluated in the order of the standard (an error before a received character before the normal exit). gotFCT, Sent
Null and Sent FCT are flags: gotFCT is set by an FCT received in Connecting and cleared in ErrorReset, Sent Null is
cleared on entry to Started, Sent FCT on entry to Connecting. FCT, N-Char and broadcast code "received" are the
one-cycle events of EN-2; EN-2 passes characters only after gotNull. The `when others` branch returns to ErrorReset.

## 3. Flow control manager (DL-4, `owr_dl_fc`)

| Counter | Increment | Decrement | Zero |
| --- | --- | --- | --- |
| Transmit credit (0 to 56) | +8 per FCT received in Connecting or Run; above 56: credit error, saturates | -1 per N-Char sent | In ErrorReset |
| Receive credit (0 to 56) | +8 per FCT sent | -1 per N-Char received in Run; at zero: credit error, the N-Char is not stored | In ErrorReset |

`FctRequest` = (Connecting or Run) and receive credit <= 48 and room >= receive credit + 8, with room = depth - fill
level - 1 (an N-Char on its way into the FIFO) - pending EEP. The fill level is `In_Level` of the receive FIFO, which
counts read words only after their pointer has crossed back, so the room is never overestimated. `CreditErr` is a
registered event. A credit error caused by an N-Char is decided with the same registered credit that DL-6 uses to
store it.

With a receive FIFO of 64 N-Chars, the reserved place for the EEP of a recovery is always free: an FCT is only sent
while fill level + credit <= 55, so the FIFO holds at most 63 N-Chars when all credit is used.

## 4. Transmit scheduler (DL-5, `owr_dl_tx`)

The presented character is combinational from the state, the flow control and the FIFO head:

| State | Presented character |
| --- | --- |
| Started | Null |
| Connecting | FCT if `FctRequest`, otherwise Null |
| Run | Broadcast code if the slot holds one, otherwise FCT if `FctRequest`, otherwise the N-Char at the head of the transmit FIFO if there is credit and no discard is running (EEP if it has a double error), otherwise Null |
| Others | Null (transmitter disabled) |

On `TxChar_Ack` the slot is emptied (broadcast code), `SentFct` or `SentNull` is pulsed, or the N-Char is popped and
`SentNChar` pulsed. `InPacket` is set when a data character is sent and cleared by a marker.

| Register | Set | Cleared |
| --- | --- | --- |
| Broadcast slot | Valid broadcast code in Run while the slot is empty (`TxBc_Ready` = slot empty); outside Run the code is accepted and `TxBc_Discarded` pulsed | Code taken by the transmitter, ErrorReset, port reset |
| `Spill` | `Rec_Start` with `InPacket`; N-Char with double error sent as EEP | Marker without double error popped, port reset |
| `RecSpill` (`Rec_Busy`) | `Rec_Start` with `InPacket` | With `Spill`, port reset |

While `Spill` is set every valid FIFO word is popped and no N-Char is presented; Nulls, FCTs and broadcast codes are
still sent.

## 5. Receive handler (DL-6, `owr_dl_rx`)

In Run a received N-Char with receive credit is loaded into the write register of the receive FIFO (data, EOP 0x100,
EEP 0x101); `InPacket` follows the last character loaded. A received broadcast code in Run is passed as a one-cycle
event. On `Rec_Start` with `InPacket` the EEP is pending and loaded as soon as the write register is free; it stays in
the register until the FIFO accepts it. `Rec_Busy` = EEP pending or write register full. An N-Char that finds the
write register full (impossible with correct credits) is dropped and reported by `Ev_Overflow`.

## 6. Link error recovery (DL-7, `owr_dl_rec`)

```text
            error in Run (cause)                one cycle               DL-5 and DL-6 not busy
 Normal ------------------------> Starting ---------------> Recovery --------------------------> Normal
   ^          Rec_Start pulse                                   |  error in Run: Starting again
   +------------------------------- port reset (any state) -----+
```

The cause is recorded in the order of ECSS 5.5.7.7b: LinkDisabled, disconnect, parity error, ESC error, credit
error. `Starting` waits one cycle because the recovery actions of DL-5 and DL-6 are registered.

## 7. FIFOs (DL-1, DL-2) and double error containment

Both FIFOs are `olo_ft_fifo_async` of 9-bit N-Chars with `ReadyRstState_g` = '0'. The `LinkClk` sides are reset by
`Rst` or port reset; the reset crossing inside the FIFO resets the user sides. ECC events count once per word read
(flag AND valid AND ready). On the user side of the receive FIFO a word with a double error is passed as an EEP;
after it is taken, the FIFO is read without passing words up to and including the next marker without double error.

## 8. Ports of `owr_dl`

| Signal | Direction | Domain | Description |
| --- | --- | --- | --- |
| `TxUser_Data/Valid/Ready` | In/In/Out | UserClk | N-Chars to send (bit 8 = marker, EOP 0x100, EEP 0x101) |
| `RxUser_Data/Valid/Ready` | Out/Out/In | UserClk | Received N-Chars |
| `TxBc_Data/Valid/Ready`, `TxBc_Discarded` | In/In/Out/Out | LinkClk | Broadcast codes from the Network layer |
| `RxBc_Data/Valid` | Out | LinkClk | Received broadcast codes (one-cycle event) |
| `TxEnable`, `RxEnable`, `TxRun` | Out | LinkClk | Encoding layer control |
| `TxChar_*`, `RxChar_*`, `Rx_*` | | LinkClk | Encoding layer characters and status |
| `Cfg_PortReset` (pulse), `Cfg_LinkDisabled`, `Cfg_LinkStart`, `Cfg_AutoStart` | In | LinkClk | Management parameters |
| `Stat_*`, `Ev_*` | Out | LinkClk | State, recovery, cause, credits, FIFO levels, discard, credit error, overflow |
| `Ecc_TxSec/Ded` | Out | LinkClk | ECC events of the transmit FIFO |
| `Ecc_RxSec/Ded` | Out | UserClk | ECC events of the receive FIFO |
| `Inj_TxBitFlip/Valid` | In | UserClk | Error injection into the transmit FIFO |
| `Inj_RxBitFlip/Valid` | In | LinkClk | Error injection into the receive FIFO |
