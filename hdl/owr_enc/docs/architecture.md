# owr_enc: Architecture and Design Description

## 1. Block diagram

```text
              owr_enc (LinkClk)
              +--------------------------------------------------------------+
 TxChar_* --->| EN-1 owr_enc_tx: bit timer -> encoder -> shift register      |---+--> Spw_DOut, Spw_SOut
 TxEnable --->|                  (parity)     (14 bit)   -> DS encoder       |   |
 TxRun ------>|                                                              |   |
 Cfg_RunDiv ->|                                                              |   | EN-3
              |                                                     +------+ |   | loopback
 Spw_DIn ---->|-------------------------------------------------->--| mux  |<----+
 Spw_SIn ---->|                                                     +------+ |
              | EN-2 owr_enc_rx: olo_intf_sync -> bit recovery -> Null      |
 RxEnable --->|                  (D XOR S change)    detection -> decoder  |--> RxChar_*, Rx_GotNull,
              |                  disconnect timer          (pending char)   |    Rx_ParityErr, Rx_EscErr,
              +--------------------------------------------------------------+    Rx_Disconnect
```

## 2. Transmitter (EN-1, `owr_enc_tx`)

### 2.1 Bit timer

`DivCnt` counts down every cycle; a bit boundary is the cycle with `DivCnt` = 0. At a bit boundary `DivCnt` is loaded
with the bit period minus one: `InitDiv_g` when `TxRun` = '0', `Cfg_RunDiv` (0 is treated as 1) when `TxRun` = '1'.
The divider of a bit is therefore fixed at its start; a rate change takes effect at the next bit boundary.

### 2.2 Encoder and serialiser

At a bit boundary with no bit left (`Remain` = 0) the transmitter takes the presented character (`Char_Ack` = '1'),
encodes it into up to 14 bits (table in the owr_pkg architecture) with the parity bit computed from `Acc`, the XOR of
the data or control bits of the previous character, and stores the XOR of the new character's bits in `Acc`. Every bit
boundary shifts one bit out. The Data-Strobe encoder sets data to the bit and toggles strobe when the bit equals the
current data value, so exactly one of the two signals changes per bit.

### 2.3 Enable, first Null and controlled reset

| Condition | Behaviour |
| --- | --- |
| Reset | Data and strobe '0', inactive |
| `TxEnable` = '1', inactive, data = strobe = '0' | Active; `Acc` = '0'; the next bit boundary is the current cycle |
| First character after activation | A Null is encoded regardless of the presented character (ECSS 5.4.5); the presented character is acknowledged only if it is a Null |
| `TxEnable` = '0' | Inactive; at each bit boundary strobe is reset if it is '1', otherwise data if it is '1' (ECSS 5.4.4d); with the initial rate outside Run the delay between the two is 100 ns |

The link state machine enables the transmitter only from Started, after at least 6.4 us in ErrorReset, so data and
strobe are '0' when it is enabled.

## 3. Receiver (EN-2, `owr_enc_rx`)

### 3.1 Sampling and bit recovery

`olo_intf_sync` synchronises data and strobe (`SyncStages_g` stages). The previous sample is kept in `PrevD`, `PrevS`;
an edge is a change of either signal, a bit is a change of data XOR strobe with the value of data. A simultaneous
change of both signals is an edge but no bit (ECSS 5.4.4f: no lock-up; the lost bit causes a parity error later).

### 3.2 Null detection and decoding

```text
            RxEnable = '0'                         Window = 011101000
 (reset) ----------------> searching (Window) ----------------------> decoding
                                ^                                       |  Parity_s -> Flag_s -> Bits_s (8 or 2)
                                |        RxEnable = '0'                  |      ^                    |
                                +----------------------------------------+      +--------------------+
```

Before gotNull every bit is shifted into the 9-bit `Window`; the Null sequence of ECSS Figure 5-18 asserts gotNull and
leaves the decoder after the parity bit of the next character. In `Flag_s` the parity check combines the stored parity
bit, the data-control flag and `PrevAcc` (XOR of the bits of the previous character). A complete character becomes
the pending character; it is released at the data-control flag of the next character if that parity check passes:

| Pending | ESC seen before | Output |
| --- | --- | --- |
| ESC | no | none, ESC seen |
| ESC | yes | ESC error |
| FCT | yes | Null |
| Data | yes | Broadcast code with the data |
| EOP or EEP | yes | ESC error |
| FCT, data, EOP, EEP | no | The character |

A parity error drops the pending character. Every error (parity, ESC, disconnect) sets `Halted`: no further character
or error until `RxEnable` is de-asserted, which resets the whole receiver including gotNull.

### 3.3 Disconnect

The first edge after `RxEnable` arms the timer (ECSS 5.4.8b); every edge restarts it. `DisconnectCycles_g` is computed
in `owr_enc` from the nominal 850 ns minus the synchroniser and edge detector latency, so that the disconnect is
reported between 727 ns and 1 us after the last edge on the line; elaboration fails when the clock frequency does not
allow this.

## 4. Port loopback (EN-3, `owr_enc`)

With `Cfg_Loopback` = '1' the receiver inputs are the transmitter outputs instead of `Spw_DIn`, `Spw_SIn`. The
outputs keep driving the line.

## 5. Ports of `owr_enc`

| Signal | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | In | `LinkClk` and its synchronous reset |
| `TxEnable`, `RxEnable` | 1 | In | Transmit Enable and Receive Enable of the link state machine |
| `TxRun` | 1 | In | '1' in the Run state: run divider |
| `Cfg_RunDiv` | 8 | In | Bit period in Run in clock cycles (link speed) |
| `Cfg_Loopback` | 1 | In | Port loopback |
| `TxChar_Kind`, `TxChar_Data` | 3, 8 | In | Presented character (always valid) |
| `TxChar_Ack` | 1 | Out | Character taken |
| `RxChar_Valid`, `RxChar_Kind`, `RxChar_Data` | 1, 3, 8 | Out | Received character or control code (one-cycle event) |
| `Rx_GotNull` | 1 | Out | gotNull level |
| `Rx_ParityErr`, `Rx_EscErr`, `Rx_Disconnect` | 1 | Out | Error events |
| `Spw_DOut`, `Spw_SOut` | 1 | Out | Data and strobe to the line driver |
| `Spw_DIn`, `Spw_SIn` | 1 | In | Data and strobe from the line receiver (asynchronous) |

## 6. Timing

| Item | Value |
| --- | --- |
| Transmit bit period | `InitDiv` or `Cfg_RunDiv` cycles; maximum rate = clock frequency |
| Receive latency | Synchroniser + 1 cycle to the bit; a character is passed two bits after its last bit (parity check of the next character) |
| Minimum edge separation at the receiver | One clock period plus the flip-flop window |
| Disconnect | 850 ns nominal, 727 ns to 1 us |
