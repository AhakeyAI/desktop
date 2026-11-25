#!/usr/bin/env python3
"""Korean catalog helper for the AhaKey Studio Windows client.

The client has two catalogs per language:
  messages_<lang>.properties  keyed UI text (LanguageManager.text / getString)
  legacy_<lang>.properties    Chinese source text -> translation, used by
                              LanguageManager.localize("中文") and, in the
                              connection log window, by Chinese log patterns.

Commands (run from ahakeyconfig-win-java/):
  python3 tools/i18n/ko_catalog.py missing [--logs] [--parts P.json ...] [FILE ...]
      Prints a JSON object {source: ""} of Chinese localize(...) literals
      (and with --logs, Chinese logger patterns) that have no Korean entry in
      legacy_ko.properties or in the given JSON parts. FILEs default to all
      Java sources.
  python3 tools/i18n/ko_catalog.py merge P.json [P.json ...]
      Merges JSON parts {source: korean} into legacy_ko.properties.
  python3 tools/i18n/ko_catalog.py check
      Verifies both Korean catalogs: no Chinese characters in values, the same
      %-format and {} placeholders as the source, and messages_ko covering
      every English key.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JAVA = os.path.join(ROOT, "src", "main", "java")
RES = os.path.join(ROOT, "src", "main", "resources")
LEGACY_KO = os.path.join(RES, "legacy_ko.properties")
HAN = re.compile(r"[㐀-鿿豈-﫿]")
FORMAT = re.compile(r"%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z%]")
SLF4J = re.compile(r"\{\}")
LOCALIZE = re.compile(r"(?<![A-Za-z0-9_$])localize\(")
LOGGER = re.compile(r"(?<![A-Za-z0-9_$])(?:logger|log|LOG|LOGGER)\.(?:trace|debug|info|warn|error)\(")


# ---------------------------------------------------------------- properties
def _unescape_properties(text):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            if n == "u" and i + 5 < len(text):
                out.append(chr(int(text[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append({"n": "\n", "t": "\t", "r": "\r", "f": "\f"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def read_properties(path):
    """Minimal java.util.Properties.load(Reader) compatible parser (UTF-8)."""
    result = {}
    if not os.path.exists(path):
        return result
    with open(path, encoding="utf-8") as handle:
        raw_lines = handle.read().split("\n")
    logical, buffer = [], ""
    for raw in raw_lines:
        line = raw.rstrip("\r")
        stripped = line.lstrip(" \t\f") if not buffer else line.lstrip(" \t\f")
        if not buffer and (not stripped or stripped[0] in "#!"):
            continue
        backslashes = len(stripped) - len(stripped.rstrip("\\"))
        if backslashes % 2 == 1:
            buffer += stripped[:-1]
            continue
        logical.append(buffer + stripped)
        buffer = ""
    if buffer:
        logical.append(buffer)
    for line in logical:
        i, key_end = 0, None
        while i < len(line):
            c = line[i]
            if c == "\\":
                i += 2
                continue
            if c in "=: \t\f":
                key_end = i
                break
            i += 1
        if key_end is None:
            result[_unescape_properties(line)] = ""
            continue
        key = line[:key_end]
        j = key_end
        while j < len(line) and line[j] in " \t\f":
            j += 1
        if j < len(line) and line[j] in "=:":
            j += 1
        while j < len(line) and line[j] in " \t\f":
            j += 1
        result[_unescape_properties(key)] = _unescape_properties(line[j:])
    return result


def _escape(text, is_key):
    out = []
    for index, c in enumerate(text):
        if c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif c == "\r":
            out.append("\\r")
        elif c == "\f":
            out.append("\\f")
        elif c == " " and (is_key or index == 0):
            out.append("\\ ")
        elif is_key and c in "=:#!":
            out.append("\\" + c)
        elif not is_key and index == 0 and c in "#!":
            out.append("\\" + c)
        else:
            out.append(c)
    return "".join(out)


def write_legacy(entries):
    with open(LEGACY_KO, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("# UTF-8 Korean translations for legacy literal UI text and Chinese log patterns.\n")
        handle.write("# Keys preserve the original Chinese source text. Edit through tools/i18n/ko_catalog.py merge.\n")
        for key in sorted(entries):
            handle.write(_escape(key, True) + "=" + _escape(entries[key], False) + "\n")


# ---------------------------------------------------------------- java scan
_ESC = {"n": "\n", "t": "\t", "r": "\r", "f": "\f", "b": "\b", "s": " ",
        '"': '"', "'": "'", "\\": "\\"}


def _parse_literal(source, i):
    """source[i] == '"'. Returns (value, end_index) or (None, i) for text blocks."""
    if source.startswith('"""', i):
        return None, i
    out, j = [], i + 1
    while j < len(source):
        c = source[j]
        if c == "\\":
            n = source[j + 1]
            if n == "u":
                k = j + 1
                while source[k] == "u":
                    k += 1
                out.append(chr(int(source[k:k + 4], 16)))
                j = k + 4
                continue
            if n in "01234567":
                k = j + 1
                digits = ""
                while k < len(source) and len(digits) < 3 and source[k] in "01234567":
                    digits += source[k]
                    k += 1
                out.append(chr(int(digits, 8)))
                j = k
                continue
            out.append(_ESC.get(n, n))
            j += 2
            continue
        if c == '"':
            return "".join(out), j + 1
        if c == "\n":
            return None, j
        out.append(c)
        j += 1
    return None, j


def _skip_space(source, i):
    while i < len(source):
        if source[i] in " \t\r\n":
            i += 1
        elif source.startswith("//", i):
            i = source.find("\n", i)
            i = len(source) if i < 0 else i
        elif source.startswith("/*", i):
            i = source.find("*/", i)
            i = len(source) if i < 0 else i + 2
        else:
            break
    return i


def _literal_argument(source, i, require_close):
    """Concatenated string literals starting at i. Returns the value or None."""
    parts = []
    while True:
        i = _skip_space(source, i)
        if i >= len(source) or source[i] != '"':
            return None
        value, i = _parse_literal(source, i)
        if value is None:
            return None
        parts.append(value)
        i = _skip_space(source, i)
        if i < len(source) and source[i] == "+":
            i += 1
            continue
        if i < len(source) and (source[i] == ")" or (not require_close and source[i] == ",")):
            return "".join(parts)
        return None


def java_files(paths):
    if not paths:
        paths = [JAVA]
    for path in paths:
        path = os.path.abspath(path)
        if os.path.isdir(path):
            for directory, _, names in os.walk(path):
                for name in sorted(names):
                    if name.endswith(".java"):
                        yield os.path.join(directory, name)
        else:
            yield path


def scan(paths, include_logs):
    """Returns {source: [relative_path:line, ...]} for Chinese sources needing Korean."""
    found = {}
    for path in java_files(paths):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        patterns = [(LOCALIZE, True)] + ([(LOGGER, False)] if include_logs else [])
        for pattern, require_close in patterns:
            for match in pattern.finditer(source):
                line_start = source.rfind("\n", 0, match.start()) + 1
                prefix = source[line_start:match.start()].lstrip()
                if prefix.startswith("//") or prefix.startswith("*"):
                    continue
                value = _literal_argument(source, match.end(), require_close)
                if value is None or not HAN.search(value):
                    continue
                line = source.count("\n", 0, match.start()) + 1
                where = os.path.relpath(path, ROOT) + ":" + str(line)
                found.setdefault(value, []).append(where)
    return found


# ---------------------------------------------------------------- commands
def load_parts(paths):
    merged = {}
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        for key, value in data.items():
            if isinstance(value, str) and value.strip():
                merged[key] = value
    return merged


def placeholder_problems(source, translated):
    problems = []
    if HAN.search(translated):
        problems.append("Chinese characters remain")
    if FORMAT.findall(source) != FORMAT.findall(translated):
        problems.append("format placeholders differ: %s vs %s" % (FORMAT.findall(source), FORMAT.findall(translated)))
    if len(SLF4J.findall(source)) != len(SLF4J.findall(translated)):
        problems.append("{} placeholder count differs")
    return problems


def command_missing(args):
    include_logs = "--logs" in args
    parts, files, i = [], [], 0
    args = [a for a in args if a != "--logs"]
    while i < len(args):
        if args[i] == "--parts":
            parts.append(args[i + 1])
            i += 2
        else:
            files.append(args[i])
            i += 1
    known = read_properties(LEGACY_KO)
    known.update(load_parts(parts))
    found = scan(files, include_logs)
    missing = {source: "" for source in sorted(found) if source not in known}
    where = {source: found[source] for source in missing}
    json.dump({"missing": missing, "where": where}, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")
    sys.stderr.write("missing: %d\n" % len(missing))
    return 1 if missing else 0


def command_merge(args):
    entries = read_properties(LEGACY_KO)
    bad = 0
    for key, value in load_parts(args).items():
        problems = placeholder_problems(key, value)
        if problems:
            bad += 1
            sys.stderr.write("skip %r: %s\n" % (key, "; ".join(problems)))
            continue
        entries[key] = value
    write_legacy(entries)
    sys.stderr.write("legacy_ko entries: %d, skipped: %d\n" % (len(entries), bad))
    return 1 if bad else 0


def command_check(_args):
    failures = 0
    legacy = read_properties(LEGACY_KO)
    for key, value in legacy.items():
        for problem in placeholder_problems(key, value):
            failures += 1
            print("legacy_ko %r: %s" % (key, problem))
    english = read_properties(os.path.join(RES, "messages_en.properties"))
    korean = read_properties(os.path.join(RES, "messages_ko.properties"))
    for key, value in english.items():
        if key not in korean or not korean[key].strip():
            failures += 1
            print("messages_ko missing key: %s" % key)
            continue
        if HAN.search(korean[key]):
            failures += 1
            print("messages_ko %s: Chinese characters remain" % key)
        if FORMAT.findall(value) != FORMAT.findall(korean[key]):
            failures += 1
            print("messages_ko %s: format placeholders differ" % key)
    missing = [s for s in scan([], False) if s not in legacy]
    for source in missing:
        failures += 1
        print("localize literal without Korean: %r" % source)
    print("legacy_ko=%d messages_ko=%d/%d problems=%d" % (len(legacy), len(korean), len(english), failures))
    return 1 if failures else 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("missing", "merge", "check"):
        sys.stderr.write(__doc__)
        return 2
    return {"missing": command_missing, "merge": command_merge, "check": command_check}[argv[1]](argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
