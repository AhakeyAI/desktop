# AhaKey GIF layout test assets

These diagnostic GIFs match firmware 1.4.3 and AhaKey Studio 1.5.2.

| Asset | Frames | Per-profile offset |
|---|---:|---:|
| default | 8 | 0 |
| running | 12 | 8 |
| waiting-error | 12 | 20 |
| completed | 12 | 32 |

Each GIF is 160 x 80 pixels and uses a 100 ms frame interval. The visible
mode, state, and frame counter make it possible to verify that a write landed
in the intended partition and that animation order is correct.

Test order:

1. Flash `AhaKey-X1-firmware-1.4.3-ch582.hex`.
2. Reconnect the keyboard over normal USB and read the device version.
3. Open **More > Screen animation** in AhaKey Studio 1.5.2.
4. Select one mode and write its four GIFs from the matching directory.
5. Switch that mode through default, running, waiting/error, and completed.
6. Confirm that the OLED label and frame counter match the selected state.
