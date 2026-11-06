#!/usr/bin/env python3
"""Builds FunnelRadar/Resources/Localizable.xcstrings from the Swift sources and scripts/l10n/<lang>.json.

    python3 scripts/l10n.py          write the catalog
    python3 scripts/l10n.py --check  fail if a string has no translation
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGUAGES = ["de", "es", "fr", "it", "ja", "ko", "pt-BR", "tr", "zh-Hans"]
CONTEXT = re.compile(
    r'(?:\b(?:Text|Button|Label|Toggle|Section|Picker|LabeledContent|ProgressView|ContentUnavailableView|DisclosureGroup|SecureField|TextField|EmptyNote)\(\s*'
    r'|String\(localized:\s*|title:\s*|text:\s*|help:\s*|subtitle:\s*|ChartCard\(title:\s*|picker\(|description: Text\(|case \.\w+(?:, \.\w+)*: |stat\([^,\n]+,\s*|\?\s+|\n\s*:\s+|\.help\(Text\()$'
)
SKIP = {"Day", "Value", "Date", "Series", "Users", "Trend", "Share", "Month", "DAU/MAU", "Start", "Index", "main", "FunnelRadar", "mp"}
KEEP = {"Checking access…", "Getting uv with Homebrew…", "Preparing Python…", "Installing mp…", "Checking the install…", "apps", "alerts", "queries this hour"}


def literals(source):
    """Yields (text before the literal, literal). Handles \\( ... ) with quotes inside."""
    i = 0
    while i < len(source):
        if source[i] != '"':
            if source.startswith("//", i):
                i = source.find("\n", i)
                if i < 0:
                    return
            i += 1
            continue
        start, i, out, depth = i, i + 1, "", 0
        while i < len(source):
            c = source[i]
            if c == "\\" and source[i + 1] == "(":
                depth, i = 1, i + 2
                while depth:
                    depth += {"(": 1, ")": -1}.get(source[i], 0)
                    i += 1
                out += "%@"
                continue
            if c == "\\":
                out += source[i + 1]
                i += 2
                continue
            if c == '"':
                break
            out += c
            i += 1
        yield source[max(0, start - 60):start], out
        i += 1


def keys():
    found = set()
    for path in glob.glob(os.path.join(ROOT, "FunnelRadar", "**", "*.swift"), recursive=True):
        if path.endswith("Snapshots.swift"):
            continue
        source = open(path, encoding="utf-8").read()
        for before, text in literals(source):
            if not text.strip() or "verbatim:" in before[-12:] or text in SKIP or text.endswith(".swift"):
                continue
            if ".value(" in before[-14:] or "systemName:" in before[-14:] or "systemImage:" in before[-14:] or "symbol:" in before[-9:]:
                continue
            if re.fullmatch(r"[a-z0-9.\-]+(\.[a-z0-9.\-]+)+", text) or text.startswith(("com.", "--")):
                continue
            if CONTEXT.search(before) or text in KEEP:
                found.add(text)
    return sorted(found)


def main():
    wanted = keys()
    tables = {}
    for language in LANGUAGES:
        path = os.path.join(ROOT, "scripts", "l10n", f"{language}.json")
        tables[language] = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    missing = [(l, k) for l in LANGUAGES for k in wanted if k not in tables[l]]
    if "--list" in sys.argv:
        print(json.dumps(wanted, ensure_ascii=False, indent=0))
        return
    if "--check" in sys.argv:
        for language, key in missing[:20]:
            print(f"missing {language}: {key}")
        unused = [(l, k) for l in LANGUAGES for k in tables[l] if k not in wanted]
        for language, key in unused[:20]:
            print(f"unused {language}: {key}")
        print(f"{len(wanted)} keys, {len(missing)} missing, {len(unused)} unused")
        sys.exit(1 if missing or unused else 0)
    strings = {}
    for key in wanted:
        localizations = {
            l: {"stringUnit": {"state": "translated", "value": tables[l][key]}} for l in LANGUAGES if key in tables[l]
        }
        strings[key] = {"localizations": localizations}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(os.path.join(ROOT, "FunnelRadar", "Resources", "Localizable.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"{len(wanted)} keys, {len(missing)} missing")


main()
