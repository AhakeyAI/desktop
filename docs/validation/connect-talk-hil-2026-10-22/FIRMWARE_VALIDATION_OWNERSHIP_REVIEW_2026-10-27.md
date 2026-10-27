# Firmware validation ownership — independent review

Base: `897324e`. First head: `00a8bdb`. Final head: `20b5bd8cbec43580e0c676cec838fc5ec97612ad`.

Spec: `docs/ahastudio/firmware-validation-ownership-2026-10-27.md` and existing firmware catalog contract. Standards: CONTRIBUTING and applicable Mac layout/conventions. Two independent code-review axes read frozen ranges; neither edited files or ran hardware commands.

## Standards

Initial and followup reviews found no substantive documented violations or judgement-call smells. The injected validator supports deterministic race tests; repeated ownership guards protect distinct completion paths. The isolated fake-tool option is proportionate to the cancellation regression.

## Spec

Initial diff had no introduced findings: UUID checks guard successful/cancelled/failed completions and cleanup; synchronous validating plus flashTask guard locks selection before staging yields. No scope creep.

Reviewer separately identified a pre-existing detection-to-erase cancellation reporting gap. An actual model plus isolated fake executable reproduced 1 test/3 failures before a cancellation check was added immediately before the destructive flag. The new test checks cancelled state, no destructive flag/recovery advice, and exactly one info command.

Followup review of `00a8bdb...20b5bd8`, and overall `897324e...20b5bd8`, found no remaining substantive findings. Selection ownership, staging lock, cleanup, revalidation and catalog matching remain intact. Final full suite: 930 passing tests. Actual installed UI, hardware and full release matrices remain outstanding.

Findings: Standards 0; Spec remaining 0. Neither review claims real ISP or final-release acceptance.
