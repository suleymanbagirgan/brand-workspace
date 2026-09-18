#!/usr/bin/env python3
"""Yerelleştirme anahtarlarını çıkarır ve İngilizce kapsamını denetler.
Kullanım: scripts/l10n.py extract   -> build/l10n-keys.json
          scripts/l10n.py check     -> eksik/fazla anahtarları, biçim belirteci uyumsuzluğunu ve İngilizce çoğul
                                       kapsamını raporlar (hata kodu 1)
          scripts/l10n.py plurals   -> çoğul sezgisinin yakaladığı anahtarları listeler (ölçüm için)
"""
import json, plistlib, re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
pat = re.compile(r'\bL[F]?\(\s*"((?:[^"\\]|\\.)*)"')
def keys():
    out = {}
    for f in sorted((root / "Sources").rglob("*.swift")):
        if "MarkaDogrula" in str(f): continue
        for m in pat.finditer(f.read_text()):
            k = m.group(1)
            if "\\(" in k: print(f"UYARI: interpolasyonlu anahtar {f.name}: {k}", file=sys.stderr)
            out.setdefault(bytes(k, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8"), f.name)
    return out
def parse_strings(p):
    d = {}
    if not p.exists(): return d
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', p.read_text(), re.M):
        unesc = lambda s: s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')
        d[unesc(m.group(1))] = unesc(m.group(2))
    return d
def parse_stringsdict(p):
    return plistlib.loads(p.read_bytes()) if p.exists() else {}
spec = re.compile(r'%(?:\d+\$)?[@dfsl]+|%\.\d+f|%(?:\d+\$)?\.\d+f|%lld')

# Çoğul sezgisi: İngilizce çeviride bir tam sayı belirtecinden sonra, noktalama/parantez/ayraçla kesilmeden gelen ilk
# üç kelimeden biri "-s" ile bitiyorsa (ör. "%d tasks", "+%d more sources", "%d malformed event lines") anahtar sayıyla
# isim çoğullar ve stringsdict'te kuralı olmalıdır. Türkçede sayıdan sonra isim tekil kaldığı için yalnızca İngilizce
# denetlenir. "-ss" ile ya da çoğul olmayan "-s" ile biten sözcükler (has, is, status …) sayılmaz.
int_spec = re.compile(r'%(?:\d+\$)?(?:l{0,2})d')
not_plural = {"is", "has", "was", "does", "its", "this", "us", "as", "plus", "status", "process", "always", "yes",
              "bonus", "previous", "focus", "canvas", "minus", "various", "whereas"}
def plural_after_number(text):
    for m in int_spec.finditer(text):
        tail = re.split(r'[·(),.:;!?%\n“”"]', text[m.end():], maxsplit=1)[0]
        words = re.findall(r"[A-Za-z’']+", tail)[:3]
        if any(w.lower().endswith("s") and not w.lower().endswith("ss") and w.lower() not in not_plural for w in words):
            return True
    return False

def plural_problems(keys, en, sd):
    """(kuralı eksik çoğul anahtarlar, hatalı stringsdict girdileri)"""
    missing = [x for x in keys if x in en and plural_after_number(en[x]) and x not in sd]
    invalid = []
    for key, entry in sd.items():
        if key not in keys: invalid.append((key, "koddaki bir anahtar değil")); continue
        fmt = entry.get("NSStringLocalizedFormatKey", "")
        names = re.findall(r'#@(\w+)@', fmt)
        if not names: invalid.append((key, "NSStringLocalizedFormatKey değişken içermiyor")); continue
        for n in names:
            v = entry.get(n)
            if not isinstance(v, dict) or v.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType":
                invalid.append((key, f"{n}: çoğul kuralı yok")); continue
            for form in ("one", "other"):
                if form not in v: invalid.append((key, f"{n}: {form} eksik"))
                elif not int_spec.search(v[form]): invalid.append((key, f"{n}.{form}: sayı belirteci yok"))
        # Her değişken bir argüman tüketir; kalan düz belirteçlerle birlikte anahtardakiyle aynı sayıda olmalı.
        consumed = len(names) + len(spec.findall(fmt))
        if consumed != len(spec.findall(key)): invalid.append((key, f"belirteç sayısı {consumed} != {len(spec.findall(key))}"))
    return missing, invalid

cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
k = keys()
en = parse_strings(root / "Resources/en.lproj/Localizable.strings")
sd = parse_stringsdict(root / "Resources/en.lproj/Localizable.stringsdict")
if cmd == "extract":
    (root / "build").mkdir(exist_ok=True)
    (root / "build/l10n-keys.json").write_text(json.dumps(sorted(k), ensure_ascii=False, indent=1))
    print(len(k), "anahtar")
elif cmd == "plurals":
    hits = sorted(x for x in k if x in en and plural_after_number(en[x]))
    for x in hits: print("KURALLI " if x in sd else "KURALSIZ", x, "=>", en[x])
    print(f"{len(hits)} çoğul anahtar; kurallı: {len([x for x in hits if x in sd])}; stringsdict: {len(sd)}")
else:
    missing = [x for x in k if x not in en]
    extra = [x for x in en if x not in k]
    bad = [x for x in k if x in en and sorted(spec.findall(x)) != sorted(spec.findall(en[x]))]
    no_rule, bad_rule = plural_problems(k, en, sd)
    print(f"anahtar: {len(k)}  en: {len(en)}  eksik: {len(missing)}  fazla: {len(extra)}  biçim uyumsuz: {len(bad)}"
          f"  çoğul kuralı: {len(sd)}  çoğul eksik: {len(no_rule)}  çoğul hatalı: {len(bad_rule)}")
    for x in missing[:40]: print("  EKSİK:", x)
    for x in bad[:20]: print("  BİÇİM:", x, "=>", en[x])
    for x in no_rule: print("  ÇOĞUL YOK (Localizable.stringsdict'e ekle):", x, "=>", en[x])
    for x, why in bad_rule: print("  ÇOĞUL HATALI:", x, "—", why)
    sys.exit(1 if missing or bad or no_rule or bad_rule else 0)
