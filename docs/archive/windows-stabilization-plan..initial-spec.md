> Historical reference only. Not a current architecture or status source.
>
> Archived on 2026-08-29 during final Windows delivery cleanup.

# Windows Stabilization Plan

> Repository: `AhakeyAI/desktop`
>
> Baseline branch: `eternal-dev`
>
> Recommended working branch: `windows-stabilization`
>
> Scope: **Windows Java client only** (`ahakeyconfig-win-java`)
>
> Document type: **living engineering document / long-term source of truth**
>
> This file must be kept in the working repository and updated continuously by maintainers and AI coding agents.

---

## 1. Purpose

This document is the long-term engineering source of truth for the Windows version of AhaKey Desktop.

The Windows client is intended to be a continuously operated and maintained product. The goal is therefore not only to fix the current defects, but also to prevent the codebase from drifting into a state where:

- the documented behavior no longer matches the real implementation;
- the same capability is implemented through multiple competing paths;
- UI reports success while the underlying operation actually failed;
- hardware approval behavior becomes unsafe or ambiguous;
- new developers or AI coding agents cannot understand which implementation is authoritative;
- large feature additions introduce regressions because existing invariants are not documented.

This document MUST remain in the repository and MUST be read before making substantial changes to the Windows client.

Suggested repository location:

```text
docs/windows-stabilization-plan.md
```

Recommended root-level `AGENTS.md` instruction:

```text
For all Windows work under ahakeyconfig-win-java, read
docs/windows-stabilization-plan.md before modifying code.

If a change alters Windows architecture, runtime behavior, supported workflows,
known limitations, verification status, or maintenance rules, update that document
in the same commit.
```

---

## 2. Long-term maintenance requirement

This project is a long-lived software product. Maintainability is a first-class requirement, not a secondary cleanup task.

All future Windows work MUST follow these rules:

1. **One authoritative implementation per capability.**  
   Avoid parallel legacy/new implementations unless an explicit compatibility reason is documented.

2. **Behavior before refactoring.**  
   Fix and verify user-visible functionality before performing broad structural refactors.

3. **No silent success.**  
   A UI action must not report success unless the underlying operation has actually succeeded.

4. **Fail-safe approval behavior.**  
   Hardware approval uncertainty must never silently become automatic approval.

5. **Explicit ownership of state.**  
   For each important state, document whether the source of truth is:
   - device;
   - local application state;
   - persistent local configuration;
   - IDE hook result;
   - compatibility bridge.

6. **Every substantial change updates this document.**  
   If a change modifies architecture, runtime flow, protocol assumptions, supported features, known limitations, validation rules, or cleanup status, this file must be updated in the same commit.

7. **AI-readable engineering context.**  
   This document must remain concise enough to be read by another AI agent before coding, but detailed enough to reconstruct the current runtime model and constraints.

8. **No undocumented replacement architecture.**  
   If a component is superseded, mark the old path as deprecated or remove it. Do not leave two plausible production paths without explaining which one is authoritative.

9. **Small, reviewable commits.**  
   Prefer one functional concern per commit. Avoid “rewrite Windows client” style changes.

10. **Tests and verification are part of the implementation.**  
    A feature is not considered fixed merely because it compiles.

---

## 3. Current product scope

The Windows application must reliably provide the following functional loops.

### 3.1 Device connection and configuration

```text
AhaKey Desktop
    ↓
USB / BLE
    ↓
AhaKey hardware
    ↓
read status / change mode / configure keys / OLED / lighting
```

Required outcomes:

- reliable USB/BLE connection;
- correct connection state;
- correct work mode synchronization;
- configuration write acknowledgements;
- safe reconnect behavior;
- no stale device state presented as current state.

---

### 3.2 AI approval

```text
Claude / Cursor / Codex / Kimi
        ↓
IDE Hook
        ↓
HookDispatchServer
        ↓
ApprovalService
        ↓
fresh physical lever state
        ↓
AUTO / MANUAL / UNKNOWN
        ↓
allow / ask / deny
```

Core invariant:

> Automatic approval is allowed only when a fresh, valid hardware state explicitly says AUTO.

Any of the following must NOT become automatic approval:

- device disconnected;
- state query timeout;
- stale cached AUTO;
- hook server unavailable;
- malformed hook payload;
- internal exception;
- compatibility bridge failure.

---

### 3.3 AI state → lighting / OLED

```text
IDE event
    ↓
Task / state mapping
    ↓
running / waiting-error / completed / idle
    ↓
LED / OLED / GIF state
```

Required outcomes:

- received IDE state must reliably reach the device;
- failures must not be silently swallowed;
- single-task / multi-task UI selection must be clearly represented;
- multi-task task-recognition or LED remapping is NOT part of the current stabilization scope.

---

### 3.4 GIF upload

```text
User GIF
    ↓
preflight
    ↓
validate / offer automatic optimization
    ↓
frame extraction / resize / timing conversion
    ↓
RGB565
    ↓
Flash write
    ↓
save configuration
    ↓
readback verification
```

Required outcomes:

- predictable upload rules;
- automatic optimization for unsupported files with explicit user consent;
- no accidental overwrite of unrelated animation slots;
- preserved playback duration as closely as hardware allows;
- bounded timeout;
- clear success/failure result.

---

### 3.5 Windows voice input

```text
Voice key down
    ↓
start recording

Voice key up
    ↓
stop recording
    ↓
speech recognition
    ↓
optional text post-processing
    ↓
text injection into foreground application
```

Required outcomes:

- low-level keyboard hook returns quickly;
- no repeated recording start on auto-repeat;
- correct F17/F18 mapping;
- reliable stop behavior;
- native resources released;
- UI only exposes implemented features.

---

### 3.6 Firmware and software lifecycle

Includes:

- firmware flashing;
- firmware version compatibility;
- BLE bridge process lifecycle;
- application shutdown;
- single-instance handling;
- application updates;
- local persistent settings.

SHA-256 validation is explicitly **not required** for the current scope.

---

## 4. Branching strategy

Do not return to `main` as the implementation baseline.

Use:

```text
eternal-dev
    ↓
windows-stabilization
    ↓
small functional commits
    ↓
verification
    ↓
merge back to eternal-dev
```

Rationale:

- `eternal-dev` already contains the Windows functionality and UI direction that must be preserved;
- `main` contains historical defects as well;
- rebuilding new functionality from `main` would duplicate work and increase regression risk.

Recommended setup:

```bash
git fetch origin
git checkout eternal-dev
git pull origin eternal-dev
git checkout -b windows-stabilization
```

---

## 5. Priority P0 — core correctness and safety

### 5.1 Approval must be fail-safe

Current risk:

- `queryStatusAndWait()` may time out and continue using cached state;
- disconnect does not guarantee that previous AUTO state cannot remain authoritative;
- stale AUTO can therefore be mistaken for current AUTO.

Required design:

```java
enum ApprovalState {
    AUTO,
    MANUAL,
    UNKNOWN,
    DISCONNECTED,
    STALE
}
```

Recommended result object:

```java
final class ApprovalSnapshot {
    ApprovalState state;
    boolean connected;
    boolean fresh;
    long timestampMillis;
}
```

Rule:

```text
fresh AUTO
    → automatic approval

anything else
    → ask / manual confirmation / deny
```

Acceptance:

- unplugging the keyboard while last state was AUTO must never produce automatic approval;
- state query timeout must never produce automatic approval;
- old cached AUTO must never be treated as fresh AUTO.

---

### 5.2 Cursor fail-open must be removed

Current risk:

When the AhaKey hook server does not respond, generated Cursor hook logic can return:

```json
{"permission":"allow"}
```

Required behavior:

- no response → ask or deny;
- server unavailable → ask or deny;
- malformed response → ask or deny;
- only explicit fresh AUTO → allow.

Acceptance:

- terminate AhaKey Desktop and trigger a Cursor permission event;
- result must never be automatic allow.

---

### 5.3 Claude must use fresh hardware approval state

Current issue:

Claude approval path does not force the same fresh state check used by some other IDE integrations.

Required:

All approval-relevant IDE events must call the same `ApprovalService`.

No IDE adapter may decide independently whether stale cached hardware state is acceptable.

---

### 5.4 Work-mode synchronization race

Current issue:

`StudioController.applyBleStatus()` can update the UI using an old device `workMode` before checking `pendingUserMode`.

Required order:

```text
receive reportedMode
    ↓
check pendingUserMode first
    ↓
old response?
    → ignore
new selected mode confirmed?
    → clear pending + apply
no pending?
    → normal device sync
```

There should be one authoritative work-mode synchronization path.

Acceptance:

Rapid Mode0 → Mode1 → Mode2 switching must not jump back to an old mode because of delayed device responses.

---

### 5.5 Hook installation must preserve third-party hooks

Current risk:

Claude/Cursor/Codex install/uninstall logic may replace or delete entire hook sections.

Required:

- parse existing configuration;
- identify only AhaKey-owned entries;
- append only if missing;
- remove only AhaKey-owned entries;
- preserve all unrelated hooks and configuration.

AhaKey hook identity should be detectable by a stable path or marker such as:

```text
.ahakey/hooks/ahakey-*.ps1
```

Acceptance:

Create third-party hooks before installing AhaKey. Install and uninstall AhaKey. Third-party hooks must remain byte-for-byte or semantically unchanged.

---

### 5.6 Bundled firmware version must satisfy GIF requirements

Current conflict:

- bundled firmware UI references `1.4.0`;
- GIF upload requires firmware capability corresponding to `1.4.3` or newer.

Required:

Use a bundled firmware version that supports all currently exposed GIF features.

Do not maintain contradictory version requirements in separate classes.

Add one shared firmware capability definition.

---

## 6. Priority P1 — GIF upload stabilization and enhancement

### 6.1 Centralize GIF upload rules

Create one authoritative rules source, e.g.:

```text
GifUploadRules
```

Current product rules:

```text
maximum source file size: 2 MB
device canvas: 160 × 80
default animation: maximum 8 frames
running animation: maximum 12 frames
waiting/error animation: maximum 12 frames
completed animation: maximum 12 frames
```

All UI labels, preflight validation, encoder behavior, error text, and tests must read from the same rule source.

Do not duplicate frame-limit numbers or file-size text across classes.

---

### 6.2 Automatic GIF optimization

When a selected GIF does not satisfy device constraints, do not immediately reject it.

Perform preflight and show a confirmation dialog describing the mismatch.

Example:

```text
The selected GIF exceeds device limits:

File size: 3.4 MB (limit: 2 MB)
Frames: 31 (limit for this state: 12)
Resolution: 320 × 160 (device: 160 × 80)

AhaKey can automatically optimize this GIF by resizing and reducing frames
while preserving the overall playback duration as closely as possible.

[Optimize and upload] [Cancel]
```

If the user accepts:

1. decode GIF;
2. read frame count and timing;
3. scale to 160×80;
4. preserve aspect ratio;
5. sample frames across the original timeline;
6. limit frames according to the target asset;
7. calculate a new frame interval that approximates the original total duration;
8. encode to device RGB565 format;
9. upload.

Do NOT require the optimized intermediate result to be written as another GIF file unless needed for debugging.

---

### 6.3 Do not hard-code 12 FPS

Current upload flow uses fixed 12 FPS.

Required:

- derive timing from the source GIF;
- if the protocol only supports one frame interval per animation, compute a reasonable interval from total duration / output frame count;
- preserve total playback duration as closely as hardware permits.

---

### 6.4 Remember the last selected GIF file

Each time the GIF file chooser opens:

- default to the last file used by the user;
- if that file no longer exists, open its parent directory if available;
- otherwise fall back to a reasonable default directory.

A single global “last selected GIF” setting is sufficient.

Do not create sixteen independent recent-file settings for every mode/state unless future UX requires it.

---

### 6.5 Prevent accidental batch overwrite

Current conceptual problem:

Opening the animation dialog may populate selections with bundled GIFs, which can cause “write all current animations” to overwrite device content that the user did not intend to modify.

Required state model:

```text
deviceCurrent
selectedFile
dirty
```

Opening the window:

```text
selectedFile = null
dirty = false
```

Choosing a custom file:

```text
selectedFile = file
dirty = true
```

Batch action should be renamed to:

```text
Write all modified animations
```

and only process:

```text
dirty == true
```

Bundled restore remains a separate explicit action.

---

### 6.6 GIF upload timeout and readback

Batch upload must not use an unbounded `await()`.

Required:

- bounded timeout;
- clear timeout error;
- UI must return from busy state;
- retry should be possible.

After writing and saving animation metadata:

```text
saveConfig
    ↓
read asset state
    ↓
verify startIndex / frameCount / frameInterval
    ↓
report success
```

No SHA validation is required.

---

### 6.7 Remove or fix misleading legacy GIF APIs

Review:

```text
previewGif()
uploadStaticImage()
```

If unused, remove them.

If retained:

- `previewGif()` must not silently perform permanent flash writes while being named “preview”;
- `uploadStaticImage()` must have the same persistence and verification semantics as the main upload path.

---

## 7. Priority P1 — lighting and OLED runtime behavior

### 7.1 Lighting configuration writeback

Current configuration write flow has ACK handling, but lighting configuration does not have the same explicit readback verification used by some other settings.

Where protocol support exists, prefer:

```text
SET
    ↓
SAVE
    ↓
GET
    ↓
COMPARE
```

If firmware lacks GET support, document the limitation here rather than pretending full verification exists.

---

### 7.2 Do not silently swallow runtime lighting errors

Runtime AI-state → device display/lighting updates must expose degraded synchronization.

Recommended state:

```java
enum LightSyncStatus {
    SYNCED,
    DEGRADED,
    DISCONNECTED,
    ERROR
}
```

Repeated device-write failures should be surfaced to UI/logging in a user-actionable way.

Avoid broad:

```java
catch (Exception ignored) {}
```

in important runtime state propagation.

---

### 7.3 Single-task / multi-task controls

UI requirement:

Move the existing single-task / multi-task control from the top area into the lighting settings module.

Current stabilization scope:

- move the UI control;
- preserve existing binding and command behavior;
- do NOT redesign multi-task task identification;
- do NOT redesign task-to-LED mapping;
- do NOT introduce a new multi-task protocol.

---

### 7.4 AI state → screen animation shortcut

Add a clear navigation button in the AI state configuration area:

```text
Screen animation settings →
```

The button should open the existing screen animation UI.

Prefer opening the animation page directly on the currently selected Mode.

This is a navigation improvement only; it should not create another animation configuration implementation.

---

### 7.5 Default GIF asset style

All bundled default animations should follow one visual system:

```text
160 × 80 canvas
sticker style
pixel-art style
outer shadow / clear outline
small color palette
simple motion
small frame count
single GIF size: typically tens of KB
```

State language should remain visually consistent:

```text
idle/default       → calm
running            → active motion
waiting/error      → warning / pause
completed          → clear success feedback
```

Different Modes may vary in character/theme/main color but should not feel like unrelated art packs.

---

## 8. Priority P1 — Windows voice

### 8.1 Low-level keyboard hook must remain lightweight

The low-level keyboard callback must not directly perform operations that can block for seconds.

Current risk:

`voice key up → stopRecording() → stopListening() → join(...)`

Required:

```text
WH_KEYBOARD_LL callback
    ↓
identify down/up
    ↓
enqueue voice command
    ↓
return immediately
```

Worker thread:

```text
START_RECORDING
STOP_RECORDING
recognition
```

---

### 8.2 Fix direct voice key bugs

Required fixes:

- “record 3 seconds” must use 3000 ms, not 3 ms;
- use one authoritative F18 virtual-key constant;
- remove incorrect low-level-hook repeat-bit logic;
- use explicit pressed-state tracking:
  - first KEYDOWN starts;
  - repeated KEYDOWN ignored;
  - KEYUP stops;
  - duplicate KEYUP ignored.

---

### 8.3 Simplify keyboard text injection

If normal text is injected via Unicode, do not mix it unnecessarily with legacy CapsLock/Shift/OEM character mapping.

Review and remove dead or misleading logic such as:

- incorrect CapsLock toggle detection;
- unnecessary `charToVkCode()` mapping;
- unused OEM constants;
- redundant Shift wrapping around Unicode characters.

Keep special handling only where needed, such as Enter/Tab.

---

### 8.4 Release ONNX native resources

All `OnnxTensor` instances created per inference must use deterministic cleanup, preferably try-with-resources.

Long-running voice use must not accumulate native tensor resources.

---

### 8.5 AhaType must not be a fake feature

Current rule:

If the AhaType text-processing step is still a TODO that simply returns the original text, either:

- implement the real processor; or
- hide/disable the UI option until implemented.

Do not expose a toggle that has no effect.

---

## 9. Priority P1 — process lifecycle and persistence

### 9.1 BLE driver ownership

Normal application shutdown must only stop the BLE bridge process owned by the current application instance.

Do not use global process-name termination for normal exit.

Allowed exception:

A clearly labeled, explicitly user-triggered recovery action may intentionally kill all stale bridge processes.

---

### 9.2 One shutdown path

All exit/restart flows must call the same lifecycle shutdown service.

This includes:

- tray exit;
- normal application exit;
- language-change restart;
- update restart;
- future restart commands.

Views must not directly call:

```java
System.exit(...)
```

without lifecycle cleanup.

---

### 9.3 Single-instance activation

Second launch behavior should be:

```text
detect existing instance
    ↓
send SHOW_WINDOW
    ↓
existing instance restores / focuses
    ↓
second instance exits
```

Do not make the second launch silently disappear when the first instance is hidden in the tray.

---

### 9.4 Persistent configuration must be atomic

For important local configuration such as `studio-draft.json`:

```text
write temporary file
    ↓
flush
    ↓
atomic move / safe replacement
```

On write failure:

- log;
- expose meaningful failure if user action depends on persistence;
- do not silently claim success.

Clarify persistent-state ownership:

```text
StudioStore   → current Studio configuration
Preferences   → small application preferences
ConfigStore   → remove/deprecate if obsolete
```

Avoid multiple competing persistent configuration implementations.

---

### 9.5 Save timeout must match real cancellation behavior

If a UI watchdog declares an operation timed out, either:

- cancel the underlying operation safely; or
- explicitly state that the operation may still be completing and prevent conflicting writes.

Do not show a terminal failure while the original write continues invisibly.

---

## 10. Priority P1/P2 — Hook stability and cleanup

### 10.1 Stable Hook endpoint

Current risk:

Hook server may move from 8765 to another port while existing generated hook scripts still point to the old port.

Preferred design:

- use one stable endpoint;
- or implement explicit endpoint discovery that existing scripts can query.

Avoid silent port migration that breaks previously installed hooks.

---

### 10.2 Align approval timeouts

UI manual approval timeout must be shorter than the IDE hook timeout.

Required invariant:

```text
approval dialog timeout < hook timeout
```

Leave enough margin for serialization / IPC / cleanup.

---

### 10.3 Installed state must mean actually installed

A hook installation is successful only when:

1. scripts were generated;
2. target config was safely updated;
3. expected files exist;
4. optional self-check passes.

Do not set `installed=true` merely because an install method was invoked.

---

### 10.4 Remove obsolete Hook stack after reference audit

Likely legacy candidates:

```text
HookClient
SocketServer
AgentManager hook-install placeholder logic
```

Before deletion:

- search all references;
- verify no packaging or compatibility path depends on them;
- add or update tests.

The authoritative production path should converge on:

```text
HookInstaller
HookDispatchServer
ApprovalService
IDE adapters
```

---

## 11. Kimi compatibility policy

Current code contains multiple Kimi-related mechanisms.

Goal:

There must be one authoritative approval decision center.

Preferred model:

```text
Kimi hook / compatibility bridge
        ↓
ApprovalService
        ↓
fresh hardware state
```

If `KimiAhaKeyBridge` remains for compatibility, it must delegate to `ApprovalService`.

If `KimiConfigLeverSync` is no longer necessary for supported Kimi versions, deprecate and remove it after verification.

Do not allow separate Kimi mechanisms to independently decide approval using different state sources.

---

## 12. Firmware flashing

Keep the current general flashing workflow where possible:

```text
select firmware
    ↓
validate firmware format
    ↓
enter ISP
    ↓
detect programmer / device
    ↓
flash
    ↓
programmer verification
    ↓
reconnect
    ↓
read firmware version
    ↓
confirm expected version
```

Required improvements:

- bundled firmware must satisfy GIF capability requirements;
- local firmware files should receive proper Intel HEX structural validation, not extension-only validation;
- remote/local/bundled validation should share the same parser where practical.

Explicit non-requirement:

```text
No SHA-256 validation is required in the current stabilization scope.
```

---

## 13. Software update policy

Application update flow should verify that the downloaded installer is structurally plausible and that installation/relaunch completes correctly.

SHA validation is NOT part of the current scope.

Do not let update-specific exit logic bypass the unified application lifecycle cleanup.

---

## 14. Out of scope for this stabilization cycle

Do NOT introduce the following unless separately approved:

- SHA-256 validation;
- major multi-task task-recognition redesign;
- new task-to-LED mapping architecture;
- major multi-task protocol redesign;
- full Windows client rewrite;
- migration back to Python or Rust as the production Windows client;
- unrelated UI redesign;
- broad refactoring whose only justification is code style.

---

## 15. Verification matrix

A fix is not complete until the relevant behavior is verified.

### 15.1 Approval

Test:

```text
AUTO + connected + fresh
MANUAL + connected + fresh
device disconnect while AUTO cached
query timeout
HookDispatchServer unavailable
malformed hook payload
Claude
Cursor
Codex
Kimi
```

Expected:

```text
only explicit fresh AUTO can auto-approve
```

Target regression test:

- 100 consecutive AUTO approval events → correct;
- 100 consecutive MANUAL events → require manual flow;
- device unavailable / state unavailable → 0 unintended auto approvals.

---

### 15.2 GIF

Test at minimum:

- valid GIF;
- >2MB GIF;
- >frame-limit GIF;
- oversized resolution;
- variable frame timing;
- last-selected-file restoration;
- user rejects optimization;
- user accepts optimization;
- upload timeout;
- reconnect during upload;
- batch upload with only one dirty asset;
- bundled restore;
- asset state readback.

---

### 15.3 Voice

Test:

- 100 press-hold-release cycles;
- repeated KEYDOWN;
- short press;
- long press;
- recognition error;
- model unavailable;
- application close during recognition;
- text injection with mixed Chinese/English/punctuation.

Expected:

- no lost keyboard hook;
- no duplicate recording;
- no stuck recording;
- no native resource accumulation.

---

### 15.4 Mode switching

Rapidly switch between modes while BLE status updates are in flight.

Expected:

- no UI rollback to stale mode;
- final UI mode matches confirmed device mode.

---

### 15.5 Hook installation

Before AhaKey install, create unrelated hooks.

Then:

```text
install AhaKey
restart application
uninstall AhaKey
```

Expected:

- unrelated hooks preserved;
- AhaKey hooks correctly added and removed;
- installed state remains accurate.

---

### 15.6 Firmware

Test:

- bundled supported firmware;
- valid local HEX;
- malformed local HEX;
- ISP device not found;
- programmer error;
- successful flash followed by reconnect and version confirmation.

---

## 16. Recommended implementation order

### Phase 1 — safety and correctness

```text
Approval fail-safe
Cursor fail-open
Claude fresh state
Mode synchronization race
Hook config preservation
Bundled firmware/GIF version conflict
```

### Phase 2 — GIF and display

```text
GIF rule centralization
automatic optimization
last selected file
timing preservation
dirty-only batch upload
timeout/readback
lighting/OLED sync visibility
UI navigation changes
default asset normalization
```

### Phase 3 — voice

```text
keyboard hook worker queue
F18 / 3ms / repeat fixes
ONNX cleanup
text injection simplification
AhaType real implementation or hide
```

### Phase 4 — lifecycle and persistence

```text
BLE driver ownership
unified shutdown
single-instance activation
atomic StudioStore persistence
save timeout semantics
```

### Phase 5 — cleanup

```text
obsolete HookClient / SocketServer audit
AgentManager placeholder cleanup
Kimi path convergence
small structural refactors
```

---

## 17. Commit discipline

Recommended commit pattern:

```text
fix(windows): make hardware approval fail-safe
fix(windows): preserve existing IDE hooks
fix(windows): stabilize work-mode synchronization
feat(windows): add GIF automatic optimization
fix(windows): preserve GIF timing and dirty-state uploads
fix(windows): stabilize Windows voice key handling
fix(windows): unify application shutdown
refactor(windows): remove obsolete hook socket stack
```

Every commit should:

1. contain one coherent functional concern;
2. compile;
3. run relevant tests;
4. include new/updated tests where practical;
5. update this document if runtime behavior, architecture, limitations, or verification status changed.

---

## 18. AI coding-agent workflow

Before modifying Windows code, an AI agent should:

1. read this document;
2. inspect the actual current implementation;
3. verify that the document still matches the code;
4. make the smallest functional change required;
5. compile/test;
6. review `git diff`;
7. update this document if behavior or architecture changed;
8. commit with a narrow message.

The AI must not assume that a TODO, class name, README statement, or old compatibility module represents the current authoritative runtime path.

When uncertain, trace:

```text
UI action
    ↓
controller/service
    ↓
transport/hook
    ↓
device or IDE
    ↓
response
```

before modifying behavior.

---

## 19. Living-document maintenance protocol

This section is mandatory for long-term maintainability.

### Every substantial PR/commit must update the relevant parts of this file when it changes:

- supported Windows features;
- runtime architecture;
- service ownership;
- hook flow;
- approval semantics;
- transport behavior;
- GIF limits or encoder behavior;
- firmware requirements;
- UI navigation relevant to functionality;
- compatibility paths;
- known defects;
- validation status;
- deprecated components.

### Keep these sections current:

```text
Current Architecture
Known Issues
Fixed Issues
Compatibility Notes
Verification Status
Deprecated Components
Recent Engineering Decisions
```

### Do not delete historical context that is still useful.

When a problem is fixed:

- move it from “Known Issues” to “Fixed Issues”;
- record the commit hash;
- record the verification performed;
- record any remaining limitation.

When a design decision changes:

- describe the old behavior briefly;
- describe the new authoritative behavior;
- explain why;
- identify components affected.

---

## 20. Current architecture status

Authoritative Windows production implementation:

```text
ahakeyconfig-win-java
```

Other Windows implementations:

```text
ahakeyconfig-win-python
    → legacy/reference baseline unless explicitly reactivated

ahakeyconfig-win-rust
    → experimental/rewrite path unless explicitly promoted
```

Do not treat the three implementations as equal production clients.

---

## 21. Known issues status

Use this table as the active tracker.

| ID | Priority | Area | Issue | Status |
|---|---|---|---|---|
| WIN-001 | P0 | Approval | stale cached AUTO may be treated as current | Code + automated tests complete; hardware pending |
| WIN-002 | P0 | Cursor | hook server failure may explicitly allow | Code + automated tests complete; manual IDE pending |
| WIN-003 | P0 | Claude | approval path may not require fresh lever state | Code + automated tests complete; hardware pending |
| WIN-004 | P0/P1 | Mode | delayed device status can roll UI back | Code + automated tests complete; hardware pending |
| WIN-005 | P0 | Hooks | install/uninstall may overwrite unrelated hooks | Code + automated tests complete; manual IDE pending |
| WIN-006 | P0 | Firmware/GIF | bundled firmware capability conflicts with GIF requirement | Client/build gates complete; real firmware asset pending |
| WIN-007 | P1 | GIF | automatic optimization not implemented | Code + automated tests complete; hardware pending |
| WIN-008 | P1 | GIF | last selected file not remembered | Code complete; manual UI pending |
| WIN-009 | P1 | GIF | frame/file-size rules not fully centralized | Code + automated tests complete; hardware pending |
| WIN-010 | P1 | GIF | fixed 12 FPS ignores source timing | Code + automated tests complete; hardware pending |
| WIN-011 | P1 | GIF | batch upload can overwrite unmodified slots | Code complete; manual UI/hardware pending |
| WIN-012 | P1 | GIF | batch wait can be unbounded | Code complete; manual timeout pending |
| WIN-013 | P1 | GIF | final readback verification incomplete | Code + automated tests complete; hardware pending |
| WIN-014 | P1 | Voice | low-level hook can perform blocking stop path | Code complete; manual Windows hook pending |
| WIN-015 | P1 | Voice | 3ms/3s bug | Code complete; manual voice pending |
| WIN-016 | P1 | Voice | inconsistent F18 constant | Code complete; hardware pending |
| WIN-017 | P1 | Voice | repeat filtering logic incorrect | Code + automated tests complete; hardware pending |
| WIN-018 | P1 | Voice | ONNX input tensors not deterministically released | Code complete; model stress test pending |
| WIN-019 | P1 | AhaType | UI exposes TODO/no-op feature | Code complete (UI hidden); manual UI pending |
| WIN-020 | P1 | Lifecycle | normal exit may kill all BLE driver processes by image name | Code complete; manual process ownership pending |
| WIN-021 | P1 | Lifecycle | multiple exit paths bypass cleanup | Code + automated tests complete; manual exit paths pending |
| WIN-022 | P1 | Persistence | StudioStore write is not atomic | Code + automated tests complete; power-loss test pending |
| WIN-023 | P1 | Single-instance | second launch cannot restore existing window | Code complete; manual Windows launch pending |
| WIN-024 | P1/P2 | Hooks | dynamic port may invalidate installed hook scripts | Code + automated tests complete; installed-script upgrade pending |
| WIN-025 | P2 | Legacy | obsolete HookClient/SocketServer stack likely remains | Open |
| WIN-026 | P1/P2 | Kimi | multiple compatibility/approval paths remain | Open |
| WIN-027 | P1 | Lighting | runtime write failures can be silently swallowed | Code + automated tests complete; hardware failure injection pending |
| WIN-028 | P2 | Lighting | configuration readback coverage incomplete | Open |
| WIN-029 | P1 | Firmware | local HEX validation too weak | Code + automated tests complete; real HEX pending |
| WIN-030 | P1/P2 | Save | timeout UI and underlying operation cancellation semantics diverge | Code complete; hardware cancellation pending |

---

## 22. Fixed issues

Move items here only after implementation and verification.

Format:

```text
### WIN-XXX — Title

Status: Fixed
Commit: <hash>
Verified by:
- <test>
- <manual scenario>

Notes:
- <remaining limitation if any>
```

Current verification record (2026-08-24):

- P0 transport sessions are immutable generations. USB close detaches under a short lock,
  calls `CancelIoEx`, closes only captured handles and waits outside the lock; stale readers,
  frames and callbacks cannot enter a new session.
- Physical status enters `WRITING` before I/O, but establishes its acceptance boundary only
  after USB `WriteFile` or BLE write+flush succeeds. Frames received before or exactly at that
  boundary are rejected; only a strictly later matching receiver/session frame can complete it.
  Failed writes, timed-out frames and stale sessions remain fail closed.
- Status queries, approval queries, OLED/GIF, configuration saves and recovery rebuilds share
  one fair lifecycle transaction gate. Unresolved state blocks new work; recovery is bounded,
  single-flight and delayed two seconds, and cannot start after manual disconnect/shutdown.
- GIFs at or below the frame limit preserve the identity source order. Only oversized inputs
  use strictly ordered timeline downsampling; resize/file/frame optimization still requires UI
  confirmation.
- Lighting writes propagate exceptions into one ordered coordinator result. UI success is emitted
  only after every step succeeds; TaskActivityService failures remain observable.
- `mvn clean test` and `mvn clean package`: 132 tests, 0 failures, 0 errors, 0 skipped;
  packaging completed successfully and the embedded artifact verifier reported
  `RELEASE_ARTIFACT_CONTENTS=OK`.
- All repository PowerShell files pass parser syntax validation. Local and overlay JAR content
  checks pass; the overlay reports `OVERLAY_VALIDATION=OK`.
- Software manual verification: pending. USB/BLE/voice/OLED hardware verification: pending.
  A real GIF-capable CH582 HEX and the formal installed release baseline assets are unavailable,
  so the installer and firmware release are not declared complete.

---

## 23. Deprecated components

Candidate components must not be deleted until reference audit and verification are complete.

Current candidates:

```text
HookClient
SocketServer
AgentManager hook installation placeholder
obsolete Kimi direct config-sync path if no longer required
misleading legacy GIF preview/static APIs if unused
```

Status:

```text
Audit required before removal.
```

---

## 24. Recent engineering decisions

### Decision 001 — Stabilize from `eternal-dev`

Use `eternal-dev` as the implementation baseline rather than returning to `main`.

Reason:

- new required functionality already exists in `eternal-dev`;
- `main` also contains historical defects;
- rebuilding from `main` increases duplicated work and risk.

### Decision 002 — No SHA validation in this cycle

SHA-256 validation is explicitly excluded from the current Windows stabilization scope.

### Decision 003 — No major multi-task redesign

Only move the single/multi-task UI control into the lighting settings area.

Do not redesign:

- task recognition;
- task-to-LED mapping;
- multi-task protocol.

### Decision 004 — Maintainability document is mandatory

This file is a persistent engineering artifact and must be kept current for future maintainers and AI agents.

A change that materially changes Windows behavior or architecture without updating this file is considered incomplete.

---

## 25. Definition of done for the stabilization cycle

The cycle is complete only when:

- hardware approval is demonstrably fail-safe;
- all supported IDE hooks behave consistently under failure;
- work-mode state does not race backward;
- hook installation preserves unrelated user configuration;
- GIF upload supports guided automatic optimization;
- GIF timing and slot ownership are predictable;
- Windows voice press/hold/release is stable;
- lighting/OLED sync failures are observable;
- bundled firmware supports exposed GIF functionality;
- normal exit only cleans up owned resources;
- single-instance behavior restores the existing window;
- important persistent configuration writes are safe;
- obsolete duplicate paths are either removed or explicitly documented;
- this document accurately reflects the final architecture;
- relevant automated/manual verification results are recorded.

---

## 26. Maintainer note

Do not optimize for “fewest files” or “largest refactor”.

Optimize for:

```text
clear ownership
predictable behavior
safe failure
small change surface
testability
readability by future humans and AI agents
```

The Windows client should remain understandable even after years of incremental changes.
