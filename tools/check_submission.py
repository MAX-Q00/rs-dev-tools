#!/usr/bin/env python3
"""Pre-submission check for an RS3 plugin: the file, manifest, code and listing
rules that RS Dev Tools' Submission Check tab cannot test from inside the game
(plugins have no file API). Sources: developer.runescape.com Submission process
and Plugin guidelines pages, the plugin developer Discord FAQ (rs-dev-tools
Help/FAQ) and release/modio/JAGEX-CHECKLIST.md.

Usage: check_submission.py PLUGIN_FOLDER [--listing DIR] [--zip FILE] [--desc FILE]
  --listing  mod.io listing folder (name.txt, summary.txt, description.txt,
             logo.png, version.txt). Default: release/modio/<folder name>.
  --zip      the zip you will upload (checks main.lua/plugin.json at the root).
Prints PASS / WARN / FAIL / MANUAL per rule. Exit 1 if anything FAILs."""
import json, re, sys, struct, subprocess, shutil, zipfile, pathlib, argparse

EULA = ("This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User "
        "Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated "
        "into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.")
PERMS = {"httpAccess", "chatAccess", "trackingAccess"}
OK_EXT = {".lua", ".json", ".png", ".ogg", ".txt", ".md"}
BAD_EXT = {".exe", ".dll", ".so", ".dylib", ".bat", ".cmd", ".ps1", ".sh", ".jar", ".vbs", ".scr", ".msi", ".com", ".py", ".js"}
JUNK = {".git", "__MACOSX", ".DS_Store", "Thumbs.db", "desktop.ini", ".vscode", ".idea"}
# API use that moderators review more closely (guidelines: "Subject to review" / Prohibited)
REVIEW = [
    (r"\bExecuteConsoleCommand\b", "sends console commands; Prohibited if it sends actions to the game, explain it"),
    (r"Event\.ChatMessage\b", "chat: needs chatAccess, a permission tag and a Permissions paragraph"),
    (r"(?<![.\w])http\w*\s*[.:(]", "HTTP: needs httpAccess, urls in plugin.json and data protection case 2/3"),
    (r"\bMiniMenu\w*", "menu customisation is Subject to review; adding entries that send actions is Prohibited"),
    (r"\bload\s*\(|\bloadstring\s*\(|string\.dump", "dynamic code loading reads as obfuscation"),
]
out = []
def R(level, area, rule, detail=""): out.append((level, area, rule, detail))
def png_size(p):
    b = p.read_bytes()[:24]
    return struct.unpack(">II", b[16:24]) if b[:8] == b"\x89PNG\r\n\x1a\n" else None
def ascii_ok(s): return all(ord(c) < 128 for c in s)

def check_manifest(f):
    mp = f / "plugin.json"
    if not mp.exists(): R("FAIL", "Manifest", "plugin.json present", "missing"); return None
    raw = mp.read_text(encoding="utf-8")
    if re.search(r",\s*[}\]]", raw): R("FAIL", "Manifest", "no trailing commas (FAQ 5)", "comma before } or ]")
    try: m = json.loads(raw)
    except Exception as e: R("FAIL", "Manifest", "valid JSON", str(e)); return None
    R("PASS", "Manifest", "valid JSON")
    n = m.get("name") or ""
    R("PASS" if 1 <= len(n) <= 50 and ascii_ok(n) else "FAIL", "Manifest", "name 1-50 ASCII", repr(n))
    v = str(m.get("version") or "")
    R("PASS" if re.fullmatch(r"\d+(\.\d+)*", v) else "FAIL", "Manifest", "version digits and dots only", v or "missing")
    e = m.get("contactEmailAddress") or ""
    R("PASS" if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", e) else "FAIL", "Manifest", "contactEmailAddress set (legal requirement, FAQ 10)", e or "missing")
    rp = m.get("requiredPermissions") or []
    R("PASS" if not rp else "WARN", "Manifest", "requiredPermissions empty (FAQ 1)", ", ".join(rp))
    bad = [p for k in ("requiredPermissions", "optionalPermissions") for p in (m.get(k) or []) if p not in PERMS]
    R("FAIL" if bad else "PASS", "Manifest", "permission names known", ", ".join(bad))
    for k in ("dependencies", "requiredDependencies", "optionalDependencies"):
        d = m.get(k)
        if d is None: continue
        if not isinstance(d, dict): R("FAIL", "Manifest", f"{k} is an object", type(d).__name__); continue
        names = [x for x in d.values() if not isinstance(x, int)]
        R("WARN" if names else "PASS", "Manifest", f"{k} use mod.io ID numbers (FAQ 9)", ", ".join(map(str, names)))
    if m.get("optionalPermissions") and "httpAccess" in m["optionalPermissions"] and not m.get("urls"):
        R("FAIL", "Manifest", "httpAccess has urls", "no urls map")
    return m

def check_files(f):
    files = [p for p in f.rglob("*")]
    junk = [str(p.relative_to(f)) for p in files if p.name in JUNK]
    R("FAIL" if junk else "PASS", "Files", "no hidden or system folders", ", ".join(junk[:5]))
    bad = [str(p.relative_to(f)) for p in files if p.is_file() and p.suffix.lower() in BAD_EXT]
    R("FAIL" if bad else "PASS", "Files", "no executables or scripts", ", ".join(bad[:5]))
    odd = [str(p.relative_to(f)) for p in files if p.is_file() and p.suffix.lower() not in OK_EXT | BAD_EXT and p.name not in JUNK]
    R("WARN" if odd else "PASS", "Files", "only .lua .json .png .ogg .txt .md", ", ".join(odd[:5]))
    big = []
    for p in files:
        if p.suffix.lower() == ".png":
            s = png_size(p)
            if s and (s[0] > 1024 or s[1] > 1024): big.append(f"{p.name} {s[0]}x{s[1]}")
    R("FAIL" if big else "PASS", "Files", "images at most 1024x1024", ", ".join(big))
    res = [p for p in files if p.suffix.lower() in (".png", ".ogg") and "resources" in p.parts]
    if res: R("WARN", "Files", "custom resources are Subject to review", f"{len(res)} image/sound file(s)")
    size = sum(p.stat().st_size for p in files if p.is_file())
    R("PASS" if size < 20 * 1024**3 else "FAIL", "Files", "under the 20 GB zip limit", f"{size/1024:.0f} KB")
    if not (f / "main.lua").exists(): R("FAIL", "Files", "main.lua at the top level", "missing")
    luac = shutil.which("luac5.4") or shutil.which("luac")
    errs = []
    for p in f.rglob("*.lua"):
        if luac:
            r = subprocess.run([luac, "-p", str(p)], capture_output=True, text=True)
            if r.returncode: errs.append(r.stderr.strip().splitlines()[0])
    if luac: R("FAIL" if errs else "PASS", "Files", "every .lua compiles (luac -p)", "; ".join(errs[:3]))
    else: R("MANUAL", "Files", "every .lua compiles", "luac not installed")

def code_only(s):
    """Lua source with comments and string literals blanked, so API names in
    help text or comments are not reported as use."""
    s = re.sub(r"--\[(=*)\[.*?\]\1\]", " ", s, flags=re.S)
    s = re.sub(r"\[(=*)\[.*?\]\1\]", '""', s, flags=re.S)
    s = re.sub(r'"(\\.|[^"\\\n])*"' + "|'(\\\\.|[^'\\\\\\n])*'", '""', s)
    return re.sub(r"--[^\n]*", " ", s)

def check_code(f):
    src = {p: p.read_text(encoding="utf-8", errors="ignore") for p in f.rglob("*.lua")}
    code = {p: code_only(s) for p, s in src.items()}
    allsrc = "\n".join(src.values())
    R("PASS" if "PluginShutdown" in allsrc else "WARN", "Code", "PluginShutdown defined (FAQ 13)")
    for pat, why in REVIEW:
        hits = [p.name for p, s in code.items() if re.search(pat, s)]
        # a global fetched by name (rawget(_G, "ExecuteConsoleCommand")) is still use
        name = re.match(r"\\b(\w+)", pat)
        if name: hits += [p.name for p, s in src.items() if not p.name.endswith("_data.lua") and re.search(r"rawget\(\s*_G\s*,\s*[\"']" + name.group(1), s)]
        if hits: R("WARN", "Code", why, ", ".join(sorted(set(hits))))
    lines = [l for s in src.values() for l in s.splitlines() if l.strip()]
    com = sum(1 for l in lines if l.strip().startswith("--"))
    ratio = com / max(1, len(lines))
    R("PASS" if ratio >= 0.05 else "WARN", "Code", "commented code (AI policy)", f"{ratio:.0%} comment lines")
    long = [p.name for p, s in src.items() if any(len(l) > 400 for l in s.splitlines()) and not p.name.endswith("_data.lua")]
    R("WARN" if long else "PASS", "Code", "no minified lines over 400 characters", ", ".join(long))

def check_listing(L, m):
    if not L or not L.exists(): R("MANUAL", "Listing", "listing folder", "none given; listing rules not checked"); return
    def rd(n):
        p = L / n
        return p.read_text(encoding="utf-8").strip() if p.exists() else None
    name, summ, desc, ver = rd("name.txt"), rd("summary.txt"), rd("description.txt"), rd("version.txt")
    if name is not None: R("PASS" if 1 <= len(name) <= 50 and ascii_ok(name) else "FAIL", "Listing", "plugin name 1-50 ASCII", name)
    if summ is not None: R("PASS" if 10 <= len(summ) <= 250 and ascii_ok(summ) else "FAIL", "Listing", "summary 10-250 ASCII", f"{len(summ)} chars")
    if ver is not None and m: R("PASS" if ver == str(m.get("version")) else "FAIL", "Listing", "upload version matches plugin.json", f"{ver} vs {m.get('version')}")
    logo = L / "logo.png"
    if logo.exists():
        s = png_size(logo)
        ok = s and s[0] >= 512 and s[1] >= 288 and abs(s[0] * 9 - s[1] * 16) <= 16
        R("PASS" if ok else "FAIL", "Listing", "logo 16:9, at least 512x288", f"{s[0]}x{s[1]}" if s else "not PNG")
    if desc is None: R("FAIL", "Listing", "description.txt", "missing"); return
    flat = re.sub(r"\s+", " ", desc)
    R("PASS" if EULA in flat else "FAIL", "Listing", "EULA statement word for word")
    email = m.get("contactEmailAddress") if m else None
    R("PASS" if re.search(r"(?im)^email", desc) and (not email or email in desc) else "FAIL", "Listing", "Email section with the contact address", email or "")
    R("PASS" if re.search(r"(?i)feedback|bugs", desc) else "FAIL", "Listing", "Feedback section")
    R("PASS" if re.search(r"(?i)collaborat|contribut|pull request", desc) else "WARN", "Listing", "stance on collaboration stated (Submission process)")
    R("PASS" if re.search(r"(?im)^permissions", desc) else "FAIL", "Listing", "Permissions section (or 'no permissions')")
    R("PASS" if re.search(r"(?i)data protection", desc) else "FAIL", "Listing", "Data Protection section")
    ab = [c for c in "<>" if c in desc]
    R("FAIL" if ab else "PASS", "Listing", "no < or > in the description", "".join(ab))
    R("PASS" if len(desc) <= 50000 else "FAIL", "Listing", "description under 50,000 characters", f"{len(desc)}")
    if m and m.get("optionalPermissions"):
        tags = (rd("tags.txt") or "").lower()
        miss = [p for p in m["optionalPermissions"] if p.lower().replace("access", "") not in tags]
        R("WARN" if miss else "PASS", "Listing", "permission tags added", ", ".join(miss))

def check_zip(z):
    with zipfile.ZipFile(z) as zf:
        names = zf.namelist()
    R("PASS" if "main.lua" in names and "plugin.json" in names else "FAIL", "Files", "main.lua and plugin.json at the zip root", z.name)

MANUAL = [
    "contact email differs from your mod.io login email",
    "all platforms ticked on upload; submitted Hidden",
    "required dependencies also set on mod.io; optional ones not",
    "no automation / sending input, hidden or future info, combat prediction, click-zone changes (Prohibited list)",
    "no info exported about other players; not a copy of another plugin",
    "documentation clear to a brand new player; code reviewed and understood (AI policy)",
    "changelog describes changes since the last approved version",
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder"); ap.add_argument("--listing"); ap.add_argument("--zip"); ap.add_argument("--desc")
    a = ap.parse_args()
    f = pathlib.Path(a.folder).resolve()
    L = pathlib.Path(a.listing) if a.listing else pathlib.Path(__file__).resolve().parent / "modio" / f.name
    m = check_manifest(f); check_files(f); check_code(f); check_listing(L, m)
    if a.desc and not a.listing:
        pass
    if a.zip: check_zip(pathlib.Path(a.zip))
    for t in MANUAL: R("MANUAL", "Manual", t)
    w = max(len(x[2]) for x in out)
    for lvl, area, rule, d in out: print(f"{lvl:6} {area:9} {rule:<{w}}  {d}")
    n = {k: sum(1 for x in out if x[0] == k) for k in ("PASS", "WARN", "FAIL", "MANUAL")}
    print(f"\n{f.name}: {n['PASS']} pass, {n['WARN']} warn, {n['FAIL']} fail, {n['MANUAL']} manual")
    return 1 if n["FAIL"] else 0
if __name__ == "__main__": sys.exit(main())
