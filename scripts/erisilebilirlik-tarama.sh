#!/bin/zsh
# Erişilebilirlik — KOD DÜZEYİNDE tarama (bilgi aracı; çıkış kodu her zaman 0).
#
# Ne yapar: Sources/MarkaApp/*.swift içinde metin + parantez eşleştirmesiyle (derleyici değil) şu kuralları arar ve
# bulguları `dosya:satır · kural · ayrıntı` olarak listeler, sonda kural başına sayıları özetler:
#   (a) simge-düğme   Button/Menu/Toggle etiketi yalnız `Image(systemName:)` (ya da `StatusCircle`) içeriyor, metin başlığı
#                     (`Text(`/`Label(`/ilk konumsal başlık) yok ve ne etikette ne değiştirici zincirinde `.accessibilityLabel(`
#                     var. Yalnız `.help(` olanlar da bulgudur: macOS'ta `.help` ipucu/yardım verir, ETİKET değildir.
#   (b) dokunma       `.onTapGesture` ile tıklanabilir yapılmış görünüm; aynı ifadenin üst düzey zincirinde
#                     `.accessibilityAddTraits(.isButton)` ya da `.accessibilityAction` yok. `.accessibilityHidden(true)` olan
#                     ifade atlanır (VoiceOver'a görünmez; eylemi kardeş denetim taşır).
#   (c) sabit-yazı    `.font(.system(size:` sayısı — YALNIZ BİLGİ, bulgu sayılmaz. macOS'ta Dynamic Type yok; sistem
#                     "metin boyutu" ayarı SwiftUI sabit boyutunu büyütmez. Sayı ileride ölçek tokenına geçiş için tutulur.
#   (d) renk-durum    `StatusCircle(` ya da küçük renkli nokta (`Circle().fill(…)` + `frame(width: ≤10`) durum taşıyor; kendisi
#                     ya da en çok 4 üst ifadesi `.accessibilityLabel(`/`.accessibilityValue(` vermiyor (StatusCircle tanımı
#                     `accessibilityHidden(true)`: durum yalnız renk/biçimle görünür).
#   (e) alan-etiketi  `TextEditor` zincirinde `.accessibilityLabel(` yok (TextEditor başlık almaz); `TextField`/`SecureField`
#                     başlığı boş ya da yalnız örnek/yer tutucu ("Örn. …", "https://") ve `.accessibilityLabel(` yok.
#
# Bilinçli atlama: bulgu satırına ya da hemen üstündeki satıra `// a11y-tarama: yok-say — <neden>` yazılırsa bulgu
# "atlanan" sayılır ve nedeniyle ayrı listelenir (sayı gizlenmez).
#
# Sınırlar / yanlış pozitif ve negatifler (dürüst tarama):
#   - Sözdizimi ağacı yok: ifade sınırı "satır başı `.` ile başlamıyorsa yeni ifade" kuralıyla bulunur; tek satıra sıkışmış
#     birden çok ifade, `if`/`switch` dalları ve `@ViewBuilder` yardımcıları yanlış kapsanabilir.
#   - Bileşen içinden verilen etiket görülmez: etiket değiştirici zinciri bir yardımcı fonksiyonun/bileşenin İÇİNDEYSE
#     (ör. `CheckBox`, `TextMenu`) çağrı yerinde değil tanımında aranır; özel bileşenler (`TextMenu`, `CheckBox`) taranmaz,
#     tanımları zaten etiket verir.
#   - (a) değişken başlıklı `Button(title)` metinli sayılır; `Label` + `.labelStyle(.iconOnly)` metinli sayılır (doğru).
#   - (d) üst ifadedeki herhangi bir etiket yeterli sayılır; etiketin durumu gerçekten söyleyip söylemediği okunmaz.
#   - (e) `TextField(değişken, …)` başlıklı sayılır; değişkenin boş olmadığı doğrulanmaz.
#   - Kontrast, odak halkası görünürlüğü, VoiceOver okuma sırası ve gerçek davranış ÖLÇÜLMEZ. Bu betik temiz çıksa da
#     uygulama "erişilebilir" sayılmaz; gerçek VoiceOver denemesi gerekir (docs/erisilebilirlik.md).
set -e
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import pathlib, re, sys
from collections import Counter, defaultdict

SUPPRESS = re.compile(r"//\s*a11y-tarama:\s*yok-say\s*(?:—|-)?\s*(.*)")

def mask(src):
    """Dize ve yorumları boşlukla değiştirir (uzunluk ve satır sonları korunur); kod parantezleri eşleştirilebilir kalır."""
    out = list(src); i, n = 0, len(src)
    stack = []  # dize içi interpolasyon derinlikleri
    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n": out[k] = " "
    def skip_string(i):
        triple = src.startswith('"""', i)
        q = '"""' if triple else '"'
        j = i + len(q)
        while j < n:
            if src[j] == "\\" and j + 1 < n and src[j + 1] == "(":
                blank(i, j)  # interpolasyon öncesi metin
                depth, k = 1, j + 2
                while k < n and depth:
                    if src[k] == '"':
                        k = skip_string(k); continue
                    if src[k] == "(": depth += 1
                    elif src[k] == ")": depth -= 1
                    k += 1
                i = k - 1; j = k; continue
            if src[j] == "\\": j += 2; continue
            if src.startswith(q, j):
                blank(i, j + len(q)); return j + len(q)
            if not triple and src[j] == "\n": return j
            j += 1
        return n
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i); j = n if j < 0 else j
            blank(i, j); i = j; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); j = n if j < 0 else j + 2
            blank(i, j); i = j; continue
        if c == '"':
            i = skip_string(i); continue
        i += 1
    return "".join(out)

PAIRS = {"(": ")", "{": "}", "[": "]"}
def close(m, i):
    o = m[i]; c = PAIRS[o]; d = 0
    for k in range(i, len(m)):
        if m[k] == o: d += 1
        elif m[k] == c:
            d -= 1
            if d == 0: return k
    return len(m) - 1

def skip_ws(m, i, newline=True):
    while i < len(m) and (m[i] in " \t" or (newline and m[i] == "\n")): i += 1
    return i

def chain_end(m, i):
    """`i`den sonra gelen `.değiştirici(…) { … }` zincirinin sonunu döndürür."""
    while True:
        j = skip_ws(m, i)
        if j < len(m) and m[j] in "?!": j += 1
        if j >= len(m) or m[j] != "." : return i
        k = j + 1
        mm = re.match(r"[A-Za-z_]\w*", m[k:])
        if not mm: return i
        k += mm.end()
        while True:
            t = skip_ws(m, k, newline=False)
            if t < len(m) and m[t] == "(":
                k = close(m, t) + 1; continue
            if t < len(m) and m[t] == "{":
                k = close(m, t) + 1; continue
            break
        i = k

def enclosing_open(m, pos):
    """`pos`u içeren en içteki `{` ya da `(` konumu (yoksa -1)."""
    d = {"}": 0, ")": 0}
    for k in range(pos - 1, -1, -1):
        ch = m[k]
        if ch in "})": d[ch] += 1
        elif ch == "{":
            if d["}"] == 0: return k
            d["}"] -= 1
        elif ch == "(":
            if d[")"] == 0: return k
            d[")"] -= 1
    return -1

def statement(m, pos):
    """`pos`u içeren ifadenin (başlangıç, zincir sonu) aralığı: en içteki blokta, satır başı `.` ile başlamayan satırdan."""
    o = enclosing_open(m, pos)
    lo = o + 1
    # bloğun başından pos'a kadar üst düzey ifade başlangıcını ara
    start, k, depth = lo, lo, 0
    while k < pos:
        ch = m[k]
        if ch in "({[":
            k = close(m, k) + 1; continue
        if ch == "\n":
            t = skip_ws(m, k + 1, newline=False)
            if t < len(m) and m[t] not in ".\n}" and t <= pos:
                start = t
        if ch == ";": start = k + 1
        k += 1
    # ifadenin kendi gövdesi + zinciri
    k = start
    while k < len(m):
        ch = m[k]
        if ch in "({[":
            k = close(m, k) + 1
            continue
        if ch == "\n" or ch == "}" or ch == ";" or ch == ")": break
        k += 1
    return start, max(chain_end(m, k), pos), o

def top_level(m, a, b):
    """[a,b) aralığında iç içe `{…}` gövdelerini boşaltır (yalnız üst düzey zincir kalsın)."""
    s, out, k = m[a:b], [], 0
    while k < len(s):
        if s[k] == "{":
            e = close(s, k); out.append("{}"); k = e + 1; continue
        out.append(s[k]); k += 1
    return "".join(out)

def line_of(src, pos): return src.count("\n", 0, pos) + 1

findings, skipped = [], []
fonts = Counter()
root = pathlib.Path("Sources/MarkaApp")
files = sorted(root.rglob("*.swift"))
for f in files:
    src = f.read_text(); m = mask(src); lines = src.splitlines()
    def add(pos, rule, detail):
        ln = line_of(src, pos)
        for cand in (ln, ln - 1):
            if 1 <= cand <= len(lines):
                s = SUPPRESS.search(lines[cand - 1])
                if s: skipped.append((f"{f}:{ln}", rule, s.group(1).strip() or "neden yazılmamış")); return
        findings.append((f"{f}:{ln}", rule, detail))

    # (c)
    fonts[f.name] += len(re.findall(r"\.font\(\.system\(size:", m))

    # (a)
    for mt in re.finditer(r"(?<![\w.])(Button|Menu|Toggle)\s*(?=[({])", m):
        kind, p = mt.group(1), mt.end()
        args = ""
        if m[p] == "(":
            e = close(m, p); args = src[p + 1:e]; p = e + 1
        first = re.split(r",(?![^(]*\))", args.strip(), maxsplit=1)[0].strip() if args.strip() else ""
        if first and not re.match(r"^[A-Za-z_]\w*\s*:", first):
            continue  # konumsal başlık (metin) var
        closures, q = [], p
        while True:
            t = skip_ws(m, q, newline=False)
            lab = re.match(r"(\w+)\s*:\s*\{", m[t:]) if closures else None
            if t < len(m) and m[t] == "{":
                e = close(m, t); closures.append((None, t, e)); q = e + 1; continue
            if lab:
                b = t + lab.end() - 1; e = close(m, b); closures.append((lab.group(1), b, e)); q = e + 1; continue
            break
        if not closures: continue
        label = next((c for c in closures if c[0] == "label"), None)
        if label is None:
            if kind == "Menu": continue
            if kind == "Button" and "action:" not in args: continue
            label = closures[0]
        body = src[label[1]:label[2] + 1]
        if re.search(r"\b(Text|Label)\s*\(|\bL\(", body): continue
        icon = re.search(r"Image\(systemName|StatusCircle\(", body)
        if not icon: continue
        ce = chain_end(m, q)
        chain = m[q:ce]
        if ".accessibilityLabel(" in chain or ".accessibilityLabel(" in body: continue
        rule = "d renk-durum" if "StatusCircle(" in body and "Image(" not in body else "a simge-düğme"
        add(mt.start(), rule, f"{kind} etiketi yalnız simge" + (" (yalnız .help: ipucu, etiket değil)" if ".help(" in chain else ""))

    # (b)
    for mt in re.finditer(r"\.onTapGesture\b", m):
        a, b, _ = statement(m, mt.start())
        tl = top_level(m, a, b)
        if ".accessibilityHidden(true)" in tl: continue
        if ".isButton" in tl or ".accessibilityAction" in tl: continue
        add(mt.start(), "b dokunma", "onTapGesture; .isButton/accessibilityAction yok")

    # (d)
    for mt in re.finditer(r"(?<![\w.])StatusCircle\((?=state)|Circle\(\)\.fill\([^\n]*?\.frame\(width:\s*(\d+)", m):
        if mt.group(1) and int(mt.group(1)) > 10: continue
        pos, ok = mt.start(), False
        # Button etiketi içindeyse (a) zaten bakar
        for _ in range(5):
            a, b, o = statement(m, pos)
            tl = top_level(m, a, b)
            if ".accessibilityLabel(" in tl or ".accessibilityValue(" in tl: ok = True; break
            if re.search(r"(?<![\w.])Button\s*[({]", tl): ok = True; break  # düğme etiketi (a) kapsamında
            if o < 0: break
            pos = o
        if not ok: add(mt.start(), "d renk-durum", "durum yalnız renk/biçimle; metinsel etiket yok")

    # (e)
    for mt in re.finditer(r"(?<![\w.])TextEditor\s*\(", m):
        e = close(m, mt.end() - 1)
        ce = chain_end(m, e + 1)
        if ".accessibilityLabel(" not in top_level(m, e + 1, ce): add(mt.start(), "e alan-etiketi", "TextEditor etiketsiz")
    for mt in re.finditer(r"(?<![\w.])(TextField|SecureField)\s*\(", m):
        e = close(m, mt.end() - 1); args = src[mt.end():e].strip()
        lit = re.match(r'^(?:L\()?\s*"((?:[^"\\]|\\.)*)"', args)
        if not lit: continue
        t = lit.group(1).strip()
        if t and not re.match(r"^(Örn\.|https?://)", t): continue
        ce = chain_end(m, e + 1)
        if ".accessibilityLabel(" not in top_level(m, e + 1, ce):
            add(mt.start(), "e alan-etiketi", f"{mt.group(1)} başlığı boş/yer tutucu: \"{t}\"")

findings.sort(); skipped.sort()
print("== Erişilebilirlik kod taraması (Sources/MarkaApp) — kod düzeyinde; VoiceOver denemesi DEĞİLDİR ==")
for loc, rule, d in findings: print(f"{loc} · {rule} · {d}")
if skipped:
    print("\n-- Bilinçli atlanan (yok-say) --")
    for loc, rule, d in skipped: print(f"{loc} · {rule} · {d}")
cnt = Counter(r.split()[0] for _, r, _ in findings)
print("\n== Özet ==")
for k, name in [("a", "simge-düğme"), ("b", "dokunma"), ("d", "renk-durum"), ("e", "alan-etiketi")]:
    print(f"({k}) {name:<14} {cnt.get(k, 0)}")
print(f"BULGU TOPLAMI       {len(findings)}")
print(f"bilinçli atlanan    {len(skipped)}")
print(f"(c) sabit-yazı (bilgi) {sum(fonts.values())} · " + ", ".join(f"{k} {v}" for k, v in fonts.most_common(5)))
PY
exit 0
