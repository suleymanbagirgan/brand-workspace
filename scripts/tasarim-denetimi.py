#!/usr/bin/env python3
"""Tasarım denetimi — arayüz kodunda tasarım dilinden KAÇIŞLARI sayar (bilgi + eşik aracı; özgün, dış kod yok).

Kullanım: python3 scripts/tasarim-denetimi.py [--esik N] [--ayrinti] [yol …]
  yol verilmezse Sources/MarkaApp taranır. Klasör verilirse *.swift, dosya verilirse (uzantısı ne olursa olsun) o dosya okunur.
  Çıkış kodu: toplam ihlal > eşik ise 1, değilse 0 (varsayılan eşik 0). Ayrıntı: `dosya:satır · tür · kesit`.

Altı ihlal türü (sayı tablosu `tür: sayı` satırlarıyla yazılır):
  sabit-renk     Color(red:/white:/hue:), NSColor(red:…), #colorLiteral, Color(hex…) — renk `Design`/`Palette` belirtecinden gelmeli.
  sabit-yazi     `.font(.system(size:` ve `// sabit-boyut:` gerekçe yorumu yok (satırda ya da üst satırda).
  kose           cornerRadius sayısı Design.Radius değerlerinden (7, 10, 14) biri değil.
  metin-L        `Text("…")` düz Türkçe dize, `L(` ya da `verbatim:` yok (çeviri dışı kalır).
  simge-dugme    Button etiketi yalnız Image(systemName:), Text/Label yok ve `.accessibilityLabel(` yok.
  bosluk         padding / spacing sabit sayısı 4'ün katı değil (Design.Space: 4, 8, 16, 24).
Bilinçli atlama: bulgu satırına ya da üstündeki satıra `// tasarim-denetimi: yok-say — <neden>`; sayı ayrı yazılır, gizlenmez.
`Design.swift` belirteçlerin tanımıdır: renk/yazı/köşe/boşluk taramasından hariçtir.

Sınırlar (yanlış pozitif/negatif olabilir; derleyici değil metin taraması): ifade sınırı "satır başı `.` ile başlamıyorsa yeni ifade"
kuralıyla bulunur; değişken içeren Text(değişken) metin-L'ye girmez; Text'te yalnız harf içeren sabit dize sayılır; ölçü birimi
değişkenle verilen boşluk görülmez. Temiz çıkması arayüzün tutarlı olduğunu KANITLAMAZ; gerçek pencere çizimi gerekir."""
import pathlib, re, sys
from collections import Counter

TURLER = ["sabit-renk", "sabit-yazi", "kose", "metin-L", "simge-dugme", "bosluk"]
KOSE_IZINLI = {7, 10, 14}
YOK_SAY = re.compile(r"//\s*tasarim-denetimi:\s*yok-say")
TOKEN_DOSYASI = "Design.swift"


def yorumsuz(src):
    """Yorumları boşlukla değiştirir (uzunluk/satır korunur); dizelerin içi korunur. Yorum-gerekçe aramak için ham metin ayrıca tutulur."""
    out = list(src); i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('"""', i):
            j = src.find('"""', i + 3); i = n if j < 0 else j + 3
        elif c == '"':
            i += 1
            while i < n and src[i] != '"' and src[i] != "\n":
                i += 2 if src[i] == "\\" else 1
            i += 1
        elif src.startswith("//", i):
            j = src.find("\n", i); j = n if j < 0 else j
            for k in range(i, j): out[k] = " "
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2); j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n": out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def esles(s, i, a="(", b=")"):
    """s[i] == a konumundan eşleşen b'nin sonrasını döndürür (dizeleri atlar)."""
    d, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            i += 1
            while i < n and s[i] != '"' and s[i] != "\n":
                i += 2 if s[i] == "\\" else 1
        elif c == a: d += 1
        elif c == b:
            d -= 1
            if d == 0: return i + 1
        i += 1
    return n


def ifade_sonu(s, i):
    """i'deki `Button(` çağrısının (sondaki kapanış + zincir değiştiriciler dahil) bittiği konum."""
    n = len(s)
    j = i + len("Button")
    k = j
    while k < n and s[k] in " \t": k += 1
    if k < n and s[k] == "(": j = esles(s, k)
    while True:
        k = j
        while k < n and s[k] in " \t": k += 1
        lm = re.compile(r"label\s*:\s*(?=\{)").match(s, k)
        if lm: k = lm.end()
        if k < n and s[k] == "{":
            j = esles(s, k, "{", "}"); continue
        m = re.compile(r"\s*\n\s*\.|\s*\.").match(s, j)
        if m:
            p = m.end() - 1
            q = re.compile(r"\.[A-Za-z_]\w*").match(s, p)
            if not q: return j
            j = q.end()
            if j < n and s[j] == "(": j = esles(s, j)
            continue
        return j


def tara(yol, ham):
    src = yorumsuz(ham)
    satirlar = ham.split("\n")
    bulgu = []
    tokenlik = yol.name == TOKEN_DOSYASI

    def satir_no(pos): return src.count("\n", 0, pos) + 1
    def ekle(tur, pos):
        ln = satir_no(pos)
        onceki = satirlar[ln - 2] if ln >= 2 else ""
        atla = bool(YOK_SAY.search(satirlar[ln - 1]) or YOK_SAY.search(onceki))
        bulgu.append((tur, ln, atla, satirlar[ln - 1].strip()[:90]))

    if not tokenlik:
        for m in re.finditer(r"\b(?:NS|UI)?Color\(\s*(?:\.\w+\s*,\s*)?(?:red|white|hue|hex)\s*:|#colorLiteral|Color\(hex", src):
            ekle("sabit-renk", m.start())
        for m in re.finditer(r"\.font\(\s*\.system\(\s*size\s*:", src):
            ln = satir_no(m.start())
            gerekce = "sabit-boyut:" in satirlar[ln - 1] or (ln >= 2 and "sabit-boyut:" in satirlar[ln - 2])
            if not gerekce: ekle("sabit-yazi", m.start())
        for m in re.finditer(r"cornerRadius\s*(?::|\()\s*(\d+(?:\.\d+)?)\b(?!\s*[\w.])|cornerRadius\s*(?::|\()\s*(\d+(?:\.\d+)?)\s*[,)]", src):
            v = float(m.group(1) or m.group(2))
            if v not in KOSE_IZINLI: ekle("kose", m.start())
        for m in re.finditer(r"\.padding\(([^()]*)\)|\bspacing\s*:\s*([0-9.]+)", src):
            if m.group(1) is not None:
                sayi = re.findall(r"(?:^|,)\s*(?:\.\w+\s*,\s*)?(-?\d+(?:\.\d+)?)\s*$", m.group(1))
                vals = sayi[-1:] if sayi else []
            else:
                vals = [m.group(2)]
            for v in vals:
                if float(v) % 4 != 0: ekle("bosluk", m.start())
    for m in re.finditer(r'\bText\(\s*"((?:[^"\\]|\\.)*)"', src):
        govde = re.sub(r"\\\([^)]*\)", "", m.group(1))
        if re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]{2}", govde): ekle("metin-L", m.start())
    for m in re.finditer(r"\bButton\b\s*(?=\()|\bButton\s*\{", src):
        son = ifade_sonu(src, m.start())
        parca = src[m.start():son]
        if "Image(systemName" in parca and not re.search(r"\bText\(|\bLabel\(|accessibilityLabel", parca):
            ekle("simge-dugme", m.start())
    return bulgu


def dosyalar(yollar):
    for y in yollar:
        p = pathlib.Path(y)
        if p.is_dir(): yield from sorted(p.rglob("*.swift"))
        elif p.is_file(): yield p
        else: print(f"yol yok: {y}", file=sys.stderr); sys.exit(2)


def main(argv):
    esik, ayrinti, yollar = 0, False, []
    it = iter(argv)
    for a in it:
        if a == "--esik": esik = int(next(it))
        elif a == "--ayrinti": ayrinti = True
        else: yollar.append(a)
    if not yollar:
        yollar = [str(pathlib.Path(__file__).resolve().parent.parent / "Sources" / "MarkaApp")]
    sayi, atlanan, dosya_say = Counter(), Counter(), 0
    for p in dosyalar(yollar):
        dosya_say += 1
        for tur, ln, atla, kesit in tara(p, p.read_text(encoding="utf-8")):
            (atlanan if atla else sayi)[tur] += 1
            if ayrinti and not atla: print(f"{p}:{ln} · {tur} · {kesit}")
    print(f"taranan dosya: {dosya_say}")
    for t in TURLER: print(f"{t}: {sayi[t]}")
    toplam = sum(sayi.values())
    print(f"toplam: {toplam}")
    if atlanan: print("atlanan (yok-say): " + ", ".join(f"{t} {atlanan[t]}" for t in TURLER if atlanan[t]))
    print(f"eşik: {esik} → {'KALDI' if toplam > esik else 'GEÇTİ'}")
    return 1 if toplam > esik else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
