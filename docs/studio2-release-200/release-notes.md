# AhaKey Windows Studio 2.0.0 release candidate

Target: Windows x64, AhaKey X1 / CH582M, firmware 1.4.8, protocol 3.2. Firmware, protocol and Studio versions are separate. Devices outside this identity may be inspected but physical writes are blocked. No firmware update is required for 1.4.8 users. No firmware is included or flashed.

Hardware profile changes (9B) update the connected profile and integration routing, without replacing the selected editor profile or writing drafts. Explicit profile activation always sends 92 and confirms a fresh observation.

USB images and GIF uploads query live 9C geometry before binding checks, erase or pixel transfer. All four profiles and asset types use fixed allocations: capacities 8/12/12/12, RGB565 160×80, 25,600 pixel bytes, 28,672-byte stride. Uploads overwrite allocated sectors, are not atomic, and cannot roll back pixels. Interrupted results require inspection and explicit reconnect, never automatic retry.

Settings includes device automatic sleep (0/5/10/15/30 minutes); applying writes 95 then shared save 04 and confirms with 95. Shared save can persist other pending device settings.

Integrations offers an explicit per-connection multiple-task mode, with four owned slots, priority for errors/attention, and 10-second heartbeat. Display mode 98 dirties shared device configuration and can be persisted by a later 04; disabling restores single mode. Other tasks remain on the PC. Occupied slots are not taken over. Reconnect or expired ownership requires explicit enable again. Stop/exit releases owned slots where the same connection remains available; an unconfirmed cleanup is reported and firmware expires slots after 30 seconds without heartbeat.

Voice routing retains the simple F18 action and adds optional short/long actions using native Windows down/up. Actions run on release; repeat is suppressed. Disable, project/context change and Windows session change cancel pending input. Voice actions execute only after explicit enable and key press; no microphone starts on enable. K1 is never remapped through 73/97.

Packages: per-user self-contained MSI and portable ZIP. MSI uses internal version 2.0.100 to upgrade alpha.9's 2.0.90; Studio product version is 2.0.0. Packages are unsigned unless a separately authorized signing run is recorded. Stable publication awaits the owner's decision and the acceptance matrix.
