# ROBOBLOQ / DX-Light USB protocol

USB HID, VID `0x1A86` (WCH), PID `0xFE07`, vendor usage page `0xFF00`, 64-byte reports without report IDs.
The same controller is sold under several names (ROBOBLOQ SyncLight, DX-Light, unbranded "screen sync" monitor bars).

## Packet

```
'R' 'B' | len | seq | action | payload… | checksum
```

- `len`: total length including header and checksum
- `seq`: rolling 1…254; replies echo it
- `checksum`: sum of all previous bytes mod 256
- zero-padded to 64 bytes per report

| Action | Code | Payload |
|---|---|---|
| per-LED frame | `0x80` | uses the `SC` header below |
| read device info | `0x82` | none (reply: LED count at byte 11, firmware at 21–23) |
| built-in effect | `0x85` | `type`, `index` (type 2 = dynamic effects 0…6, type 3 = music) |
| set LED ranges | `0x86` | repeated `[first, R, G, B, last]`, 1-based inclusive, max index 254 |
| brightness | `0x87` | 5…100 |
| effect speed | `0x8A` | 5…100, **lower is faster** |
| turn off | `0x97` | none |

Solid colour, as the official app sends it: `[1, R, G, B, n, n+1, 0, 0, 0, 254]` (LEDs past the strip are blanked).

## Per-LED frames

```
'S' 'C' | len (u16 BE) | seq | 0x80 | [first, R, G, B, last]… | checksum
```

Split across consecutive 64-byte reports. The official app uses at most 50 groups at about 25 fps.

## Behaviour notes (observed on a 75-LED bar, firmware 1.9.4)

- The bar remembers nothing across power loss and starts in its rainbow effect. Re-send everything after reconnecting.
- After a built-in effect (including the power-on rainbow) the bar appears to ignore per-LED frames until a `0x86` solid colour is sent, so Glowdeck primes with one. (Observed once, not yet confirmed.)
- After the Mac sleeps, the bar may reset while the HID handle stays open and writes keep succeeding. Glowdeck polls `0x82` every 10 s and reopens the device if it doesn't answer.

Sources: [light-control-rs docs/protocol.md](https://github.com/tanmaster/light-control-rs), [synclight-pro PROTOCOL.md](https://github.com/hacmiu/synclight-pro).
