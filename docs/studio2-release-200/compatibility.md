# Supported compatibility matrix

| Studio | OS | Device | MCU | Firmware | Protocol | Transport |
|---|---|---|---|---|---|---|
| 2.0.0 candidate | Windows x64 (Windows 11 acceptance pending) | AhaKey X1 / model 1 | CH582M | 1.4.8 exactly | 3.2 exactly | BLE for daily controls; USB required for display bulk upload |

The current-device identity is read through 00/9F. Status and capability major/minor must agree, model must be 1, protocol 3.2 and firmware patch 8. Capabilities must include the expected 0x7FF contract; per-feature task/sleep capability gates also apply. Unknown, legacy 1.0.0/1.1.0, and runtime/TaskPictureV3 devices cannot authorize physical writes in this release. Historical diagnostic parsers and tests do not confer product support.

Display contract: four profiles, four asset types, maximum 12 frames, 160×80 RGB565 (25,600 bytes), seven 4 KiB sectors per frame (28,672-byte stride), physical NOR 8,388,608 bytes / 292 physical slots, capacities 8/12/12/12. Fixed allocated profile assets occupy 176 slots. Missing or conflicting live 9C fields block upload before erase/pixels.

Source references: firmware eternal-dev bc4f6e40dc11b486af9cedba528d24844e6225a9; package provenance f1903791f2119d02f71eb92afe9efbb360edb06a. These identify the supplied source contract, not a new physical verification or a redistribution grant. No firmware update is part of this candidate.
