#!/usr/bin/env python3
"""Exercise the HW1 production macro sender without a keyboard or private source upload.

Default success means release-failure recovery passed. --expect-known-failure instead
checks the archived defect, and explicitly reports fixed=false. New firmware transport
APIs may require adapting the host shim; build failures never count as a passing case.
"""

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile


PSK_HEADER = r"""
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define KEYBOARD_WITH_LWRB
extern const uint8_t report_map_all[105], report_map_six_key[1];
extern const uint16_t report_map_six_key_len;
void MY_USB_HID_SEND_REPORT(uint8_t *, uint16_t);
"""
MAIN_HEADER = r"""
#pragma once
#define PRINT(...) ((void)0)
unsigned long TMOS_GetSystemClock(void);
"""
HARNESS = r"""
#include <stdio.h>
#include <stdlib.h>
#include "keyboard.h"
const uint8_t report_map_all[105]={0}, report_map_six_key[1]={0};
const uint16_t report_map_six_key_len=1;
static unsigned ticks, reports, failed, down_edges, up_edges, unsupported;
static int fail_release, seen_enter;
static uint8_t host[9];
unsigned long TMOS_GetSystemClock(void) { return ticks * 3; }
static int enter(const uint8_t *r) {
    for (unsigned i=3; i<9; i++) if (r[i]==0x28) return 1;
    return 0;
}
void MY_USB_HID_SEND_REPORT(uint8_t *r, uint16_t n) {
    if (n!=9 || r[0]!=1) { unsupported++; return; }
    reports++;
    if (fail_release && seen_enter && !enter(r)) {
        fail_release=0; failed++; return;
    }
    int before=enter(host), after=enter(r);
    down_edges += !before && after;
    up_edges += before && !after;
    memcpy(host,r,9);
    if (after) seen_enter=1;
}
static void tick(void) { ticks++; send_keyboard_data(); }
int main(int argc, char **argv) {
    if (argc!=3) return 2;
    int fault=atoi(argv[1]), pattern=atoi(argv[2]);
    uint8_t minimal[]={DOWN_KEY,0x28,UP_KEY,0x28};
    uint8_t readback[]={DOWN_KEY,0x51,UP_KEY,0x51,
        DOWN_KEY,0x51,UP_KEY,0x51,DOWN_KEY,0x28,UP_KEY,0x28};
    uint8_t screenshot[]={DOWN_KEY,0x51,UP_KEY,0x51,DELAY,5,
        DOWN_KEY,0x51,UP_KEY,0x51,DELAY,5,DOWN_KEY,0x28,UP_KEY,0x28};
    uint8_t *macros[]={minimal,readback,screenshot};
    unsigned sizes[]={sizeof(minimal),sizeof(readback),sizeof(screenshot)};
    if (pattern<0 || pattern>2) return 2;
    keyboard_init();
    if (keyboard_state.report_length!=9 || keyboard_state.mode!=SIX_KEY) return 2;
    fail_release=fault;
    kbd_write_command_list(macros[pattern],sizes[pattern]);
    for (unsigned i=0; i<1000; i++) tick();
    int stuck=enter(host), internal=enter((uint8_t *)&tkeyboard_buff);
    unsigned initial_reports=reports;
    if (!seen_enter || unsupported || (fault && failed!=1)) return 2;
    if (!fault && (down_edges!=1 || up_edges!=1)) return 2;
    if (stuck) {
        keyboard_press_key_code_1(0x28,1); tick();
        keyboard_press_key_code_1(0x28,0);
        for (unsigned i=0; i<10; i++) tick();
    }
    printf("{\"hostEnterAfter1000Ticks\":%s,\"internalEnter\":%s,"
        "\"reportsBeforeRecovery\":%u,\"failedRelease\":%u,"
        "\"hostEnterAfterRecovery\":%s}\n",
        stuck?"true":"false",internal?"true":"false",initial_reports,failed,
        enter(host)?"true":"false");
    return stuck ? 1 : 0;
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware-repo", type=pathlib.Path, required=True)
    parser.add_argument("--revision", required=True, help="Explicit HW1 source commit")
    parser.add_argument("--expect-known-failure", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    compiler = shutil.which("clang")
    if compiler is None:
        parser.error("clang with ASan/UBSan support is required")
    repo = args.firmware_repo.resolve(strict=True)

    def git(*argv):
        return subprocess.run(["git", "-C", str(repo), *argv], check=True,
                              capture_output=True, timeout=30).stdout

    revision = git("rev-parse", "--verify", "--end-of-options",
                   args.revision + "^{commit}").decode().strip()
    hashes, cases = {}, []
    with tempfile.TemporaryDirectory(prefix="ahakey-enter-release-") as directory:
        work = pathlib.Path(directory)
        for name in ("keyboard.c", "keyboard.h", "lwrb.c", "lwrb.h"):
            payload = git("show", revision + ":APP/hid_dev/" + name)
            hashes[name] = hashlib.sha256(payload).hexdigest()
            (work / name).write_bytes(payload)
        for name, payload in (("psk_hid.h", PSK_HEADER), ("main.h", MAIN_HEADER),
                              ("probe.c", HARNESS)):
            (work / name).write_text(payload)
        build = subprocess.run(
            [compiler, "-std=c99", "-g", "-fsanitize=address,undefined",
             "keyboard.c", "lwrb.c", "probe.c", "-o", "probe"],
            cwd=work, capture_output=True, text=True, timeout=60)
        if build.returncode:
            raise RuntimeError("Host shim does not compile against this revision:\n" +
                               build.stderr[-6000:])
        for pattern, name in enumerate(("minimal-enter-pair", "six-step-readback-shape",
                                        "eight-step-screenshot-shape")):
            for fault in (False, True):
                result = subprocess.run([str(work / "probe"), str(int(fault)), str(pattern)],
                                        capture_output=True, text=True, timeout=10)
                if result.returncode not in (0, 1) or result.stderr:
                    raise RuntimeError("Invalid harness execution or sanitizer finding:\n" +
                                       result.stderr + result.stdout)
                observation = json.loads(result.stdout)
                cases.append(dict(macro=name, oneReleaseFailureInjected=fault,
                                  exitCode=result.returncode, **observation))
    controls_ok = all(not c["hostEnterAfter1000Ticks"] and not c["internalEnter"]
                      for c in cases if not c["oneReleaseFailureInjected"])
    fixed = controls_ok and all(not c["hostEnterAfter1000Ticks"] and not c["internalEnter"]
                               for c in cases)
    reproduced = controls_ok and all(
        c["hostEnterAfter1000Ticks"] and not c["internalEnter"] and
        not c["hostEnterAfterRecovery"]
        for c in cases if c["oneReleaseFailureInjected"])
    verdict = reproduced if args.expect_known_failure else fixed
    report = dict(schemaVersion=1, sourceCommit=revision, sourceSHA256=hashes,
                  mode="known-defect-check" if args.expect_known_failure else "verify-fix",
                  expectationMet=verdict, fixed=fixed, knownDefectReproduced=reproduced,
                  actualDeviceTransportFailureCodeCaptured=False, hardwareAccess=False,
                  cases=cases)
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded)
    print(encoded, end="")
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
