# Owner Preserve Foreign Input — WD-002 pom.xml — 2026-10-03

Owner clarified that `pom.xml` is a pre-existing external/historical dirty file from before WD-002 candidate preparation.

Preserve First instruction:
- Keep current `pom.xml` content.
- Do not restore, commit, stash, reset, checkout, or otherwise rewrite `pom.xml`.
- Do not include `pom.xml` in the WD-002 Git candidate.
- Treat `pom.xml` as a preserved foreign input only for candidate filtering, bound to its current content hash.

Accepted working-tree hash:
- `pom.xml`: `a163f73c11f38e4a2cd395a3f6a9322e6446e741732fe4abf34cc5bab889f734`

Scope:
- This record authorizes only the v1.1 Harness candidate preserved-foreign mechanism needed to unblock WD-002 candidate preparation.
- It does not reopen WD-002 product contract, review, DIB implementation, Firmware, or release scope.
