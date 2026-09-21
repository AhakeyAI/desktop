# Frozen compatibility fixtures

- `phase33-local-draft.v1.json`: unchanged bytes from the Phase 3.3 offline replay-final run, isolated settings folder `205b4a07d82941cc9d8f4967d19808d7`. Schema 1, four profiles, legacy `Oled` property, brightness 32. Contains synthetic defaults, no hardware identifiers.
- `phase2-settings.v1.json`: unchanged bytes from Phase 2 QA round2, isolated folder `72cb9047bceb4470a488f154916bc39b`. Codex selection and multilingual synthetic local key name. Phase 2 persisted settings, not the later local-draft envelope.

The nonempty-assets test derives an explicitly synthetic variant of the frozen Phase 3.3 shape. It is not claimed as a physical readback or historical nonempty asset capture.
