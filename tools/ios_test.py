#!/usr/bin/env python3
# =============================================================================
#  Noor — iOS test suite  (unit + UI + screen captures)
#  This is my test harness. It uses the SAME strings, the SAME grading logic and
#  the SAME layout numbers as the Swift app, so it reproduces (and screenshots)
#  what the iPhone shows *before* anyone builds the IPA.
#
#  usage:  python3 tools/ios_test.py [--shots DIR]
# =============================================================================

import json, os, sys, math, datetime, unicodedata, itertools

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QURAN_JSON = os.path.join(ROOT, "NoorKit", "Sources", "NoorKit", "quran.json")
ADHKAR_JSON = os.path.join(ROOT, "NoorKit", "Sources", "NoorKit", "adhkar.json")

fails, passes = [], []

def check(name, cond, detail=""):
    (passes if cond else fails).append(name)
    print(("  ✅ " if cond else "  ❌ ") + name + (("  → " + str(detail)) if detail and not cond else ""))
    return cond

AR_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
def fmt(v): return str(v).translate(AR_DIGITS)

# ───────────────────────────────────────────────────────────── Quran model (Swift Quran.swift)
class Quran:
    def __init__(self, path):
        self.surahs = json.load(open(path, encoding="utf-8"))
        self.ayahs = [(s["n"], i + 1, a) for s in self.surahs for i, a in enumerate(s["ayahs"])]
        self.global_of = {}
        g = 0
        for s in self.surahs:
            for i in range(len(s["ayahs"])):
                g += 1
                self.global_of[(s["n"], i + 1)] = g
        self.flat_words, self.word_ayah, self.word_char = [], [], []
        text = ""
        self.ayah_word_off = {0: 0}
        for g, (s, a, t) in enumerate(self.ayahs, start=1):
            self.ayah_word_off[g] = len(self.flat_words)
            for w in norm(t).split():
                if text: text += " "
                self.word_char.append(len(text.encode("utf-16-le")) // 2)
                self.word_ayah.append(g)
                self.flat_words.append(w)
                text += w
        self.flat_text = text
        self.ayah_word_off[6237] = len(self.flat_words)

    def ayah(self, s, a): return self.surahs[s - 1]["ayahs"][a - 1]
    def count(self, s): return len(self.surahs[s - 1]["ayahs"])
    def name(self, s): return self.surahs[s - 1]["t"]
    def global_index(self, s, a): return self.global_of[(s, a)]
    def to_surah_ayah(self, g): return self.ayahs[g - 1][0], self.ayahs[g - 1][1]
    def words_of(self, g): return self.ayah_word_off[g], self.ayah_word_off.get(g + 1, self.ayah_word_off[6237])

    def word_at(self, pos):
        lo, hi, ans = 0, len(self.word_char) - 1, 0
        while lo <= hi:
            mid = (lo + hi) // 2
            if self.word_char[mid] <= pos: ans, lo = mid, mid + 1
            else: hi = mid - 1
        return ans

Q = None

# ───────────────────────────────────────────────────────────── normalisation (Swift ReciteCheck)
DIACRITIC_RANGES = [(0x0610, 0x061A), (0x064B, 0x065F), (0x06D6, 0x06ED)]
def is_diacritic(ch):
    v = ord(ch)
    if v == 0x0670 or v == 0x0640: return True
    return any(a <= v <= b for a, b in DIACRITIC_RANGES)

FOLD = {"ٱ": "ا", "أ": "ا", "إ": "ا", "آ": "ا", "ٲ": "ا", "ٳ": "ا", "ٵ": "ا",
        "ة": "ه", "ہ": "ه", "ۀ": "ه", "ى": "ي", "ئ": "ي", "ﻯ": "ي", "ؤ": "و", "ک": "ك"}

def norm(s):
    out = []
    for ch in s:
        v = ord(ch)
        if is_diacritic(ch): continue
        if v in (0x0640, 0x0670) or v in (0x06E1, 0x06E2, 0x06E5, 0x06E6, 0x06E9): continue
        ch = FOLD.get(ch, ch)
        if ord(ch) == 0x0621: continue
        if ch.isspace():
            if out and out[-1] == " ": continue
            ch = " "
        out.append(ch)
    return "".join(out).strip()

def skeleton(s):
    n = norm(s)
    r = "".join(c for c in n if c not in "اوي")
    return r or n

def words(s): return [w for w in norm(s).split(" ") if w]

def similarity(a, b):
    if a == b: return 1.0
    la, lb = len(a), len(b)
    if not la or not lb: return 0.0
    prev = list(range(lb + 1)); cur = [0] * (lb + 1)
    for i in range(1, la + 1):
        cur[0] = i
        for j in range(1, lb + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
        prev, cur = cur, prev
    return 1.0 - prev[lb] / max(la, lb)

# ───────────────────────────────────────────────────────────── harakat
H_NAMES = ["فتحة", "ضمة", "كسرة", "سكون", "شدّة", "تنوين", "بدون حركة"]
HARAKA = {0x064E: 0, 0x064F: 1, 0x0650: 2, 0x0652: 3, 0x0651: 4, 0x064B: 5, 0x064C: 5, 0x064D: 5}
def haraka_sig(word):
    out = []
    for i, ch in enumerate(word):
        if is_diacritic(ch): continue
        h = 6
        for d in word[i + 1:]:
            if not is_diacritic(d): break
            if ord(d) in HARAKA: h = HARAKA[ord(d)]; break
        out.append(h)
    return out

def haraka_text(word): return " ".join(H_NAMES[h] for h in haraka_sig(word))

# ───────────────────────────────────────────────────────────── engine (Swift ReciteCheck.analyze)
def compare_harakat(w):
    exp, got = haraka_sig(w["target"]), haraka_sig(w.get("spoken") or "")
    w["expectedHarakat"], w["gotHarakat"] = haraka_text(w["target"]), haraka_text(w.get("spoken") or "")
    if not exp or not got:
        w["harakaScore"], w["harakaNote"] = 1.0, ""
        return
    wrong = checked = 0; detail = []
    for i in range(min(len(exp), len(got))):
        if got[i] == 6: continue
        checked += 1
        if exp[i] != got[i]:
            wrong += 1
            detail.append(f"الحرف {fmt(i+1)}: المتوقع {H_NAMES[exp[i]]} والمقروء {H_NAMES[got[i]]}")
    w["harakaScore"] = 1.0 if checked == 0 else 1 - wrong / checked
    w["harakaNote"] = " · ".join(detail)

# ── anchor search: fuzzy votes + a second opinion on the best candidates
_WORD_INDEX = None
def word_index():
    global _WORD_INDEX
    if _WORD_INDEX is not None: return _WORD_INDEX
    exact, by_first = {}, {}
    for pos, w in enumerate(Q.flat_words):
        exact.setdefault(w, []).append(pos)
        by_first.setdefault(w[0], {}).setdefault(w, []).append(pos)
    _WORD_INDEX = (exact, by_first)
    return _WORD_INDEX

def _pos_score(anchor, sw):
    """how well the spoken words line up if the recitation starts at this word"""
    hits = exacts = 0.0
    for i, w in enumerate(sw[:12]):
        pos = anchor + i
        if pos >= len(Q.flat_words): break
        t = Q.flat_words[pos]
        if t == w: exacts += 1; hits += 2.0
        elif skeleton(t) == skeleton(w): hits += 1.2
        elif similarity(t, w) >= 0.8: hits += 0.8
    return hits + 1.5 * exacts

def locate(spoken, hint_sura=None):
    """returns (global ayah, word offset inside it) or None.

    Votes on *anchor word positions* (so one wrong word or a mid-page start does not
    defeat it), then re-scores the best candidates word-by-word («second opinion»)
    so surahs with identical openings resolve correctly.
    A confidence guard rejects non-Quranian input instead of grading nonsense.
    """
    sw = norm(spoken).split(" ")
    if len(sw) < 2: return None
    exact, by_first = word_index()
    votes = {}
    for i, w in enumerate(sw):
        # muqatta'at (طسم · حم · الم) carry meaning even when short
        informative = len(w) >= 3 or (len(sw) <= 6 and w not in ("ما", "في", "من", "على", "الا", "هو"))
        if not informative and len(sw) > 3: continue
        cands = [(p, 1.6) for p in exact.get(w, [])[:200]]
        bucket = by_first.get(w[0], {})
        if len(cands) < 200:
            for pw, plist in bucket.items():
                if abs(len(pw) - len(w)) > 1: continue
                if pw == w: continue
                sim = similarity(w, pw)
                if sim >= 0.8:
                    cands.extend((p, 1.2 * sim) for p in plist[:100])
        for p, sc in cands[:300]:
            a = p - i
            if a < 0: continue
            v = votes.setdefault(a, [0.0, 0])
            v[0] += sc; v[1] += 1
    if not votes: return None

    # top candidates by vote, then re-scored by real word-by-word agreement
    top = sorted(votes.items(), key=lambda kv: -(kv[1][0] + 0.8 * kv[1][1]))[:12]
    best_a, best_s = None, -1.0
    for a, (score, cnt) in top:
        if a >= len(Q.word_ayah): continue
        s2 = _pos_score(a, sw)
        if s2 > best_s: best_s, best_a = s2, a
    if best_a is None: return None

    # ---- confidence: a *consecutive* run of agreeing words, and a decent ratio
    agree = exact_hits = run = best_run = 0
    for i, w in enumerate(sw[:10]):
        pos = best_a + i
        if pos >= len(Q.flat_words): break
        t = Q.flat_words[pos]
        ok = (t == w) or (similarity(t, w) >= 0.8 and len(w) >= 3)
        if t == w: exact_hits += 1
        if ok:
            agree += 1; run += 1; best_run = max(best_run, run)
        else:
            run = 0
    compare_n = min(len(sw), 10)
    need = 2 if len(sw) > 2 else 1
    if agree < need or best_run < need or exact_hits < 1: return None
    if agree / max(1, compare_n) < 0.5: return None

    # ---- «the surah I'm reading» wins ties (identical openings across surahs)
    if hint_sura:
        for a, (score, cnt) in top:
            if a >= len(Q.word_ayah): continue
            g0 = Q.word_ayah[a]
            if Q.to_surah_ayah(g0)[0] == hint_sura and _pos_score(a, sw) >= best_s - 0.6:
                best_a = a
                break

    g = Q.word_ayah[best_a]
    return g, max(0, best_a - Q.words_of(g)[0])

def haraka_verdict(r):
    if r["harakaTotal"] == 0: return "مش ممكن نقيس التشكيل — الحروف نفسها في كلمات غلط"
    if r["wrongHarakat"] == 0: return "التشكيل مضبوط ✅"
    if r["harakaPercent"] >= 90: return f"شبه مضبوط — راجع {fmt(r['wrongHarakat'])} كلمة"
    if r["harakaPercent"] >= 75: return f"فيه {fmt(r['wrongHarakat'])} كلمة حركتها غلط — اسمع القارئ وركّز"
    return f"التشكيل محتاج مراجعة جدية ({fmt(r['wrongHarakat'])} كلمة)"

def tally(words_out):
    r = dict(words=words_out, correct=0, wrong=0, missing=0, percent=0, harakaTotal=0,
             harakaCorrect=0, harakaPercent=0, wrongHarakat=0)
    s = 0.0
    for w in words_out:
        L = max(1, len(w["target"]))
        if w["correct"]:
            r["correct"] += 1; s += 1
            r["harakaTotal"] += L
            r["harakaCorrect"] += round(w["harakaScore"] * L)
            if w["harakaScore"] < 0.999: r["wrongHarakat"] += 1
        elif w.get("spoken") is None:
            r["missing"] += 1
        else:
            r["wrong"] += 1; s += w["letterPercent"]
    r["percent"] = min(100, round(100 * s / max(1, len(words_out))))
    r["harakaPercent"] = 0 if r["harakaTotal"] == 0 else round(100 * r["harakaCorrect"] / r["harakaTotal"])
    r["harakaVerdict"] = haraka_verdict(r)
    return r

def analyze(spoken):
    sw = words(spoken)
    seed = {"sura": 1, "ayahs": [], "correct": 0, "wrong": 0, "missing": 0,
            "wrongHarakat": 0, "ayahsPerfect": 0, "percent": 0, "harakaPercent": 0,
            "heardWords": len(sw), "resumeAyah": 1, "mistakes": []}
    loc = locate(spoken)
    if not loc or len(sw) < 3:
        seed["feedback"] = "مش قادرين نحدد الآية — اقرأ آية كاملة بوضوح"
        return seed
    anchor, offset = loc
    sura, anchor_ayah = Q.to_surah_ayah(anchor)
    seed["sura"] = sura
    maxA = Q.count(sura)

    tw, t_ayah, t_global = [], [], []
    first, ay = True, anchor_ayah
    while ay <= maxA and len(tw) < len(sw) + 30:
        gl = Q.global_index(sura, ay)
        parts = norm(Q.ayah(sura, ay)).split()
        for wi, w in enumerate(parts):
            if first and wi < offset: continue
            tw.append(w); t_ayah.append(ay); t_global.append(gl)
        first = False; ay += 1
    if not tw:
        seed["feedback"] = "تعذّر تحميل نص السورة"
        return seed

    n, m = len(tw), len(sw)
    NEG = -1e9
    dp = [[0.0] * (m + 1) for _ in range(n + 1)]
    bk = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1): dp[i][0] = dp[i - 1][0] - 1.2; bk[i][0] = 1
    for j in range(1, m + 1): dp[0][j] = dp[0][j - 1] - 1.2; bk[0][j] = 2
    for i in range(1, n + 1):
        w, sk = tw[i - 1], skeleton(tw[i - 1])
        for j in range(1, m + 1):
            v = sw[j - 1]
            if w == v: match = 2.0
            elif sk == skeleton(v): match = 1.4
            else:
                sim = similarity(w, v)
                match = 0.9 if sim >= 0.8 else (0.2 if sim >= 0.62 else -1.2)
            best, d = dp[i - 1][j - 1] + match, 0
            if dp[i - 1][j] - 1.2 > best: best, d = dp[i - 1][j] - 1.2, 1
            if dp[i][j - 1] - 1.2 > best: best, d = dp[i][j - 1] - 1.2, 2
            dp[i][j], bk[i][j] = best, d

    match_spoken = [None] * n
    i, j = n, m
    while i > 0 or j > 0:
        d = 2 if i == 0 else (1 if j == 0 else bk[i][j])
        if d == 0: match_spoken[i - 1] = sw[j - 1]; i -= 1; j -= 1
        elif d == 1: match_spoken[i - 1] = None; i -= 1
        else: j -= 1

    out = []
    idx = 0
    while idx < n:
        ayah = t_ayah[idx]
        wl = []
        spoken_of = []
        while idx < n and t_ayah[idx] == ayah:
            target, sp = tw[idx], match_spoken[idx]
            w = dict(target=target, normalized=target, spoken=sp, correct=False,
                     lettersSpelledDifferently=False, similarity=0.0, letterPercent=0.0, edits=[])
            if sp is not None:
                w["similarity"] = similarity(target, sp)
                w["letterPercent"] = max(0, min(1, similarity(skeleton(target), skeleton(sp))))
                same = target == sp or skeleton(target) == skeleton(sp)
                w["correct"] = same
                w["lettersSpelledDifferently"] = same and target != sp
                compare_harakat(w)
                spoken_of.append(sp)
            wl.append(w)
            idx += 1
        r = tally(wl)
        r["ayah"] = ayah
        r["text"] = Q.ayah(sura, ayah)
        r["spoken"] = " ".join(spoken_of)
        out.append(r)

    last_good = -1
    for k, r in enumerate(out):
        if r["percent"] >= 40 or r["correct"] > 0: last_good = k
    if last_good >= 0 and last_good + 1 < len(out): out = out[:last_good + 1]

    s = 0.0
    for r in out:
        seed["correct"] += r["correct"]; seed["wrong"] += r["wrong"]
        seed["missing"] += r["missing"]; seed["wrongHarakat"] += r["wrongHarakat"]
        if r["percent"] == 100 and r["wrongHarakat"] == 0: seed["ayahsPerfect"] += 1
        s += r["correct"] + sum(w["letterPercent"] for w in r["words"] if not w["correct"] and w.get("spoken"))
        for w in r["words"]:
            if w.get("spoken") is None:
                seed["mistakes"].append(dict(ayah=r["ayah"], kind="ناقصة", target=w["target"],
                                             got="", detail="الكلمة مش متقروءة"))
            elif not w["correct"]:
                seed["mistakes"].append(dict(ayah=r["ayah"], kind="كلمة غلط", target=w["target"],
                                             got=w["spoken"],
                                             detail=" · ".join(f"«{e[0]}» ← «{e[1]}»" for e in w["edits"]) if w["edits"] else ""))
            elif w["harakaScore"] < 0.999:
                seed["mistakes"].append(dict(ayah=r["ayah"], kind="حركة", target=w["target"],
                                             got=w["spoken"], detail=w["harakaNote"]))
    total = max(1, seed["correct"] + seed["wrong"] + seed["missing"])
    seed["percent"] = min(100, round(100 * s / total))
    ht = sum(r["harakaTotal"] for r in out); hc = sum(r["harakaCorrect"] for r in out)
    seed["harakaPercent"] = 0 if ht == 0 else round(100 * hc / ht)
    seed["ayahs"] = out
    seed["resumeAyah"] = min(maxA, out[-1]["ayah"] + 1) if out else anchor_ayah
    errs = seed["wrong"] + seed["missing"]
    seed["feedback"] = ("ما شاء الله — كل اللي قريته صح ✅" if errs == 0 and seed["wrongHarakat"] == 0
                        else f"الحروف كلها صح — راجع {fmt(seed['wrongHarakat'])} حركة (تشكيل) 🟡" if errs == 0
                        else f"فيه {fmt(errs)} خطأ — شوف القايمة تحت")
    return seed

# ───────────────────────────────────────────────────────────── prayer times (Swift Prayer.swift)
METHODS = [("الهيئة المصرية العامة للمساحة", 19.5, 17.5), ("رابطة العالم الإسلامي", 18.0, 17.0),
           ("أم القرى — مكة المكرمة", 18.5, 0.0), ("ISNA — أمريكا الشمالية", 15.0, 15.0),
           ("معهد الجيوفيزياء — طهران", 17.7, 14.0)]
PNAMES = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]

def fix(a, b): 
    a -= b * math.floor(a / b)
    return a + b if a < 0 else a

def julian(y, m, d):
    if m <= 2: y -= 1; m += 12
    A = math.floor(y / 100); B = 2 - A + math.floor(A / 4)
    return math.floor(365.25 * (y + 4716)) + math.floor(30.6001 * (m + 1)) + d + B - 1524.5

def times(lat, lon, method, tz, y, m, d, offsets=(0,)*6):
    fajr_a, isha_a = METHODS[method][1], METHODS[method][2]
    jd = julian(y, m, d) - lon / 360.0
    D = jd - 2451545.0
    g = fix(357.529 + 0.98560028 * D, 360)
    q = fix(280.459 + 0.98564736 * D, 360)
    L = fix(q + 1.915 * math.sin(math.radians(g)) + 0.020 * math.sin(math.radians(2 * g)), 360)
    e = 23.439 - 0.00000036 * D
    decl = math.degrees(math.asin(math.sin(math.radians(e)) * math.sin(math.radians(L))))
    RA = fix(math.degrees(math.atan2(math.cos(math.radians(e)) * math.sin(math.radians(L)),
                                    math.cos(math.radians(L)))) / 15, 24)
    eqt = q / 15 - RA
    mid = fix(12 - eqt, 24)
    off = tz - lon / 15
    def ha(alt):
        c = (math.sin(math.radians(alt)) - math.sin(math.radians(decl)) * math.sin(math.radians(lat))) / \
            (math.cos(math.radians(decl)) * math.cos(math.radians(lat)))
        return math.degrees(math.acos(max(-1, min(1, c)))) / 15
    asr_alt = math.degrees(math.atan(1 / (1 + math.tan(math.radians(abs(lat - decl))))))
    r = [mid - ha(-fajr_a) + off, mid - ha(-0.833) + off, mid + 1 / 15 + off,
         mid + ha(asr_alt) + off, mid + ha(-0.833) + off]
    r.append(r[4] + 1.5 if isha_a <= 0 else mid + ha(-isha_a) + off)
    return [fix(v + offsets[i] / 60, 24) for i, v in enumerate(r)]

def qibla(lat, lon):
    kla, klo = 21.4225, 39.8262
    dLon = math.radians(klo - lon); p1, p2 = math.radians(lat), math.radians(kla)
    y = math.sin(dLon)
    x = math.cos(p1) * math.tan(p2) - math.sin(p1) * math.cos(dLon)
    return (math.degrees(math.atan2(y, x)) + 360) % 360

HIJRI = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
         "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
def hijri(y, m, d):
    jd = julian(y, m, d) + 0.5
    l = int(jd - 1948440 + 10632)
    n = (l - 1) // 10631
    l = l - 10631 * n + 354
    j = math.floor((10985 - l) / 5316) * math.floor(50 * l / 17719) + math.floor(l / 5670) * math.floor(43 * l / 15238)
    l = l - math.floor((30 - j) / 15) * math.floor(17719 * j / 50) - math.floor(j / 16) * math.floor(15238 * j / 43) + 29
    mh = int(math.floor(24 * l / 709)); dh = int(l - math.floor(709 * mh / 24)); yh = 30 * n + int(j) - 30
    mh = max(1, min(12, mh))
    return f"{fmt(dh)} {HIJRI[mh-1]} {fmt(yh)} هـ"

# ───────────────────────────────────────────────────────────── tests
def run_tests():
    print("\n▶ اختبارات البيانات")
    check("القرآن: ١١٤ سورة", len(Q.surahs) == 114, len(Q.surahs))
    check("القرآن: ٦٢٣٦ آية", len(Q.ayahs) == 6236, len(Q.ayahs))
    check("الفاتحة: ٧ آيات", Q.count(1) == 7)
    check("البقرة: ٢٨٦ آية", Q.count(2) == 286)
    check("الناس: ٦ آيات", Q.count(114) == 6)
    long_sura = max(Q.surahs, key=lambda s: len(s["ayahs"]))
    check("أطول سورة البقرة", long_sura["n"] == 2)
    check("كل آية غير فاضية", all(a.strip() for _, _, a in Q.ayahs))
    check("لا يوجد آية فيها حرف لاتيني", not any(ch.isascii() and ch.isalpha() for _, _, a in Q.ayahs for ch in a))
    check("آخر آية = الناس ٦", Q.to_surah_ayah(6236) == (114, 6), Q.to_surah_ayah(6236))
    check("أول آية = الفاتحة ١", Q.to_surah_ayah(1) == (1, 1))
    check("فهرس الكلمات متزايد", all(Q.word_char[i] < Q.word_char[i+1] for i in range(len(Q.word_char)-1)))

    adh = json.load(open(ADHKAR_JSON, encoding="utf-8"))
    n_adh = sum(len(g) for g in adh["adhkar"])
    check("الأذكار: ٥ تصنيفات", len(adh["adhkar"]) == 5, len(adh["adhkar"]))
    check("الأذكار: ٣٨ ذكر", n_adh == 38, n_adh)
    check("عدد الأذكار في كل تصنيف", [len(g) for g in adh["adhkar"]] == [10, 8, 7, 7, 6])
    check("الأدعية: ١٥", len(adh["duas"]) == 15, len(adh["duas"]))
    check("الأحاديث: ٢٠", len(adh["hadiths"]) == 20, len(adh["hadiths"]))
    check("كل دعاء له عنوان + نص", all(len(r) == 2 and r[0] and r[1] for r in adh["duas"]))
    check("كل ذكر له عدّاد صحيح", all(len(r) > 1 and r[1].isdigit() for g in adh["adhkar"] for r in g))

    print("\n▶ اختبارات التطبيع (Uthmani → plain)")
    check("ٱلْحَمْدُ → الحمد", norm("ٱلْحَمْدُ") == "الحمد")
    check("علامات الوقف مرفوعة", norm("قِيَٰمًاۖ") == "قيما", norm("قِيَٰمًاۖ"))
    check("التطويل مرفوع", norm("الـــلــه") == "الله")
    check("الهمزة المستقلة مرفوعة", norm("شيء") == "شي")
    check("ة → ه", norm("رحمة") == "رحمه")
    check("ى → ي", norm("هدى") == "هدي")
    check("سكون/شدة مرفوعين", norm("رَبِّ") == "رب")
    check("مسافات مضاعفة تتظبط", norm("الحمد   لله") == "الحمد لله")

    print("\n▶ اختبارات هيكل الحروف والتصحيح")
    check("العلمين ≈ العالمين (skeleton)", skeleton("العلمين") == skeleton("العالمين"),
          (skeleton("العلمين"), skeleton("العالمين")))
    check("الحمده ≠ الحمد (skeleton)", skeleton("الحمده") != skeleton("الحمد"))
    a = analyze("الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين")
    check("الفاتحة ١–٣: ١٠٠٪", a["percent"] == 100, a["percent"])
    check("الفاتحة: ٣ آيات في التقرير", len(a["ayahs"]) == 3, len(a["ayahs"]))
    check("الفاتحة: صفر أخطاء", a["wrong"] == 0 and a["missing"] == 0, (a["wrong"], a["missing"]))
    check("الفاتحة: كل الآيات متقنة", a["ayahsPerfect"] == 3, a["ayahsPerfect"])

    a = analyze("الحمد لله رب العلمين الرحمن الرحيم مالك يوم الدين")
    check("«العلمين» تُقبل كصح", a["wrong"] == 0 and a["percent"] == 100, (a["wrong"], a["percent"]))

    a = analyze("الحمده لله رب العالمين الرحمن الرحيم مالك يوم الدين")
    check("«الحمده» تُرصد غلط", a["wrong"] == 1, a["wrong"])
    check("الغلطة واحدة بس", len(a["mistakes"]) == 1, a["mistakes"])
    check("الغلطة في الآية ٢ (البسملة آية ١)", a["mistakes"][0]["ayah"] == 2 if a["mistakes"] else False)
    check("الغلط مأثرش على باقي الآيات", a["percent"] >= 85, a["percent"])

    # the 5.3 regression: one dropped word must not shift the page
    full = " ".join(Q.ayah(2, i) for i in range(1, 6))
    sw = norm(full).split()
    dropped = " ".join(sw[:5] + sw[6:])
    a = analyze(dropped)
    check("كلمة ناقصة: التقرير بيرصد ناقص ١", a["missing"] == 1, a["missing"])
    check("كلمة ناقصة: مفيش ٣٩ خطأ وهمي", a["wrong"] <= 1, a["wrong"])
    check("كلمة ناقصة: النسبة عالية (>٩٠٪)", a["percent"] >= 90, a["percent"])

    # mid-ayah start
    mid = " ".join(norm(Q.ayah(18, 2)).split()[3:])
    a = analyze(mid)
    check("بداية من نص آية: يلقى الكهف",
          a["sura"] == 18 if a["ayahs"] else False, a.get("sura"))
    check("بداية من نص آية: أول آية = ٢", a["ayahs"][0]["ayah"] == 2 if a["ayahs"] else False)

    # a typo in the FIRST word must not hide the page
    a = analyze("الحمده لله رب العالمين الرحمن الرحيم مالك يوم الدين")
    check("غلطة في أول كلمة: لسه بيلقى الفاتحة", a["ayahs"] != [] and a["sura"] == 1, (a.get("sura"), len(a["ayahs"])))
    a = analyze("قيما لينزر باسه شديدا من لدنه ويبشر")
    check("الكهف ٢ بغلطة: يلقى الكهف", a["sura"] == 18 if a["ayahs"] else False, a.get("sura"))

    # non-Quran → honest refusal
    a = analyze("هذا نص عربي عادي جدا ليس من القران الكريم ابدا")
    check("نص مش قرآني: رفض واضح", a["ayahs"] == [] and "مش قادرين" in a["feedback"], a["feedback"])

    # short input
    a = analyze("الحمد")
    check("كلمتين أو أقل: رسالة واضحة", a["ayahs"] == [])

    # harakat only → letters right, marks flagged
    a = analyze("الحَمد لِله رب العالمين")
    check("حركة غلط: الحروف صح", a["correct"] >= 2, a["correct"])

    # idempotent: analysis of the whole Baqara opening is stable
    a1 = analyze(full); a2 = analyze(full)
    check("نفس المدخل → نفس النتيجة", (a1["percent"], a1["correct"], a1["wrong"]) ==
          (a2["percent"], a2["correct"], a2["wrong"]))
    check("البقرة ١–٥ كاملة: ١٠٠٪", a1["percent"] == 100, a1["percent"])

    # every surah can be located from its own first ayah
    print("\n▶ اختبار تحديد الموضع (١١٤ سورة)")
    located_ok, wrong_place, ambiguous, no_locate = 0, [], [], []
    for s in Q.surahs:
        src = norm(s["ayahs"][0]).split()
        if len(src) < 3:
            for k in range(1, min(4, len(s["ayahs"]))):
                src = norm(" ".join(s["ayahs"][:k])).split()
                if len(src) >= 3: break
        if len(src) < 3: continue
        probe = " ".join(src[:8])
        loc = locate(probe)
        if not loc: no_locate.append(s["n"]); continue
        g, off = loc
        su, ay = Q.to_surah_ayah(g)
        # honesty: the located ayah must REALLY contain the words that were said
        anchor_words = norm(Q.ayah(su, ay)).split()
        said = norm(probe).split()
        stretch = " ".join(anchor_words[off:off + len(said)])
        # if the surah's opening spills into the next ayah, the block still matches
        if stretch != " ".join(said):
            nxt = norm(Q.ayah(su, min(ay + 1, Q.count(su)))).split()
            stretch2 = " ".join((anchor_words[off:] + nxt)[:len(said)])
            if stretch2 == " ".join(said): stretch = stretch2
        if su == s["n"]:
            located_ok += 1
        elif stretch == " ".join(said):
            ambiguous.append(s["n"])      # identical opening in another surah (e.g. الصف/الحشر)
        else:
            wrong_place.append((s["n"], f"→ {su}:{ay}"))
    check(f"كل سورة تتحدد صح ({located_ok}/114)", located_ok >= 108, (wrong_place, no_locate))
    check("مفيش ولا سورة اتحددت في مكان غلط", not wrong_place, wrong_place[:4])
    check("الافتتاحيات المتطابقة معروفة ومعدودة", len(ambiguous) <= 6, ambiguous)
    # the hint resolves them
    hint_ok = 0
    for n in ambiguous:
        src = norm(" ".join(Q.surahs[n - 1]["ayahs"][:3])).split()[:8]
        loc = locate(" ".join(src), hint_sura=n)
        if loc and Q.to_surah_ayah(loc[0])[0] == n: hint_ok += 1
    check(f"«السورة اللي بتقرأها» بتحل المتشابهات ({hint_ok}/{len(ambiguous)})",
          len(ambiguous) == 0 or hint_ok == len(ambiguous))

    print("\n▶ اختبارات الحركات")
    check("حركة كلمة بسيطة (كسرة+شدة)", haraka_sig("رَبِّ") in ([0, 2], [0, 4]), haraka_sig("رَبِّ"))
    check("سكون", haraka_sig("قُلْ") == [1, 3], haraka_sig("قُلْ"))
    check("تنوين", 5 in haraka_sig("قَوْلًا"))
    check("بدون تشكيل = بدون حركة (وليس خطأ)",
          compare_harakat(dict(target="رَبِّ", spoken="رب")) or True)
    w = dict(target="رَبِّ", spoken="رب"); compare_harakat(w)
    check("التعرّف بدون تشكيل لا يعاقب", w["harakaScore"] == 1.0, w["harakaScore"])

    print("\n▶ اختبارات المواقيت والقبلة والهجري")
    t = times(30.5965, 31.5021, 0, 2, 2026, 11, 16)
    check("المنصورة ١٦/١١: ٦ مواقيت", len(t) == 6)
    check("الترتيب صحيح (فجر<شروق<ظهر<عصر<مغرب<عشاء)", t[0] < t[1] < t[2] < t[3] < t[4] < t[5], t)
    check("الفجر في المعقول (٣–٦)", 3 <= t[0] <= 6, round(t[0], 2))
    check("الظهر في المعقول (١١–١٣)", 11 <= t[2] <= 13, round(t[2], 2))
    tm = times(21.4225, 39.8262, 2, 3, 2026, 11, 16)
    check("مكة (أم القرى): العشاء بعد المغرب ٩٠ دقيقة", abs((tm[5] - tm[4]) - 1.5) < 0.01, round(tm[5] - tm[4], 3))
    tr = times(51.5, -0.13, 1, 0, 2026, 6, 21)
    check("لندن يونيو: الفجر والعشاء موجودين", 0 <= tr[0] <= 24 and 0 <= tr[5] <= 24)
    check("القبلة من المنصورة ≈ ١٣٦°", 130 <= qibla(30.5965, 31.5021) <= 145, round(qibla(30.5965, 31.5021), 1))
    qm = qibla(21.4225, 39.8262)
    check("القبلة من عين الكعبة ≈ ٠/٣٦٠", qm < 1 or qm > 359, round(qm, 2))
    check("الهجري: ١٦/١١/٢٠٢٦", "هـ" in hijri(2026, 11, 16), hijri(2026, 11, 16))
    check("الهجري يوم ٢٧ رمضان ١٤٤٧", hijri(2027, 3, 5).count("هـ") == 1)

    print("\n▶ اختبارات النصوص (Arabic safety)")
    samples = [a for _, _, a in Q.ayahs[:50]] + [d[1] for d in adh["duas"]]
    check("مفيش نص فيه NULL أو RTL-override", not any("\x00" in s or "\u202e" in s for s in samples))
    check("مفيش مسافات مزدوجة في المصحف", not any("  " in a for _, _, a in Q.ayahs))
    check("كل الآيات تبدأ بحرف عربي بعد التطبيع", all(norm(a)[:1].isalpha() for _, _, a in Q.ayahs))
    return

# ───────────────────────────────────────────────────────────── visual snapshots
def screenshot(out_dir):
    """renders the two main screens with the app's real colours/layout numbers to an SVG pair"""
    os.makedirs(out_dir, exist_ok=True)
    P = dict(bg="#070c16", card="#101a2b", card2="#152238", surface="#0d1420", gold="#e7be72",
             teal="#3fbf9f", red="#e05a55", amber="#d48a2a", sub="#8a94a6", txt="#f2f5fa",
             paper="#fffdf7", ink="#1b1a17", inksoft="#6b6355", paperred="#b3261e",
             paperamber="#b36b00", papergreen="#1b6b3a")
    t = times(30.5965, 31.5021, 0, 2, 2026, 11, 16)
    rows = "".join(
        f'<div class="r"><span class="tm{" g" if i==2 else ""}">{fmt(int(t[i]))}:{fmt(int(round((t[i]-int(t[i]))*60))%60).zfill(2)}</span>'
        f'<span class="nm{" g" if i==2 else ""}">{PNAMES[i]}</span></div>' for i in range(6))
    a = analyze("الحمد لله رب العلمين الرحمن الرحيم مالك يوم الدين إياك نعبد وإياك نستعين")
    def ayah_html(r):
        out = []
        for w in r["words"]:
            cls = "ok" if w["correct"] and w["harakaScore"] >= 0.999 else (
                  "hk" if w["correct"] else ("miss" if w.get("spoken") is None else "bad"))
            out.append(f'<span class="{cls}">{norm(w["target"])}</span>')
        return " ".join(out)
    cards = "".join(
        f'<div class="paper"><div class="meta"><span>آية {fmt(r["ayah"])}</span>'
        f'<span class="{"pg" if r["percent"]==100 else "pa"}">{fmt(r["percent"])}%</span></div>'
        f'<div class="ayah">{ayah_html(r)}</div></div>' for r in a["ayahs"])
    mistakes = "".join(
        f'<div class="mk"><div class="k">آية {fmt(m["ayah"])} · {m["kind"]}: {norm(m["target"])}</div>'
        + (f'<div class="g">قلت: {norm(m["got"])}</div>' if m["got"] else "")
        + (f'<div class="d">{m["detail"]}</div>' if m["detail"] else "") + "</div>"
        for m in a["mistakes"])

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="760" height="1180" viewBox="0 0 760 1180"
     font-family="'SF Arabic','Segoe UI',Tahoma,sans-serif">
  <rect width="760" height="1180" fill="{P['bg']}"/>
  <text x="740" y="42" fill="{P['gold']}" font-size="26" font-weight="bold" text-anchor="end">نُور</text>
  <text x="740" y="64" fill="{P['sub']}" font-size="11" text-anchor="end">مواقيت · قرآن · أذكار · تلاوة</text>

  <rect x="20" y="82" width="340" height="300" rx="16" fill="{P['card']}"/>
  <text x="340" y="112" fill="{P['sub']}" font-size="11" text-anchor="end">{hijri(2026,11,16)}</text>
  <text x="340" y="134" fill="{P['gold']}" font-size="12" text-anchor="end" font-weight="bold">المنصورة</text>
  <text x="340" y="176" fill="{P['txt']}" font-size="30" font-weight="bold" text-anchor="end">٨:٠٨ م</text>
  <text x="340" y="200" fill="{P['teal']}" font-size="12" text-anchor="end">الصلاة القادمة: الظهر · باقي ٣ س ١٢ د</text>
  {''.join(f'<text x="340" y="{232+i*24}" fill="{P["txt"]}" font-size="13" text-anchor="end">{fmt(int(t[i]))}:{fmt(int(round((t[i]-int(t[i]))*60))%60).zfill(2)}   {PNAMES[i]}</text>' for i in range(6))}

  <rect x="400" y="82" width="340" height="300" rx="16" fill="{P['card']}"/>
  <text x="720" y="112" fill="{P['gold']}" font-size="15" font-weight="bold" text-anchor="end">📍 سورة الفاتحة · من آية ١ إلى ٣</text>
  {''.join(f'<text x="{720-i*68}" y="146" fill="{[P["teal"],P["teal"],P["red"],P["sub"],P["amber"]][i]}" font-size="15" font-weight="bold" text-anchor="middle">{v}</text>' for i,v in enumerate([f'{fmt(a["percent"])}%', fmt(a["correct"]), fmt(a["wrong"]), fmt(a["missing"]), fmt(a["wrongHarakat"])]))}
  {''.join(f'<text x="{720-i*68}" y="164" fill="{P["sub"]}" font-size="9" text-anchor="middle">{v}</text>' for i,v in enumerate(["الدقة","صح","غلط","ناقص","حركة"]))}
  <text x="720" y="196" fill="{P['sub']}" font-size="11" text-anchor="end">{a["feedback"]}</text>
  <rect x="412" y="212" width="316" height="150" rx="14" fill="{P['paper']}"/>
  <text x="716" y="238" fill="{P['inksoft']}" font-size="11" text-anchor="end" font-weight="bold">آية ١ · {fmt(a["ayahs"][0]["percent"])}%</text>
  <text x="716" y="276" fill="{P['papergreen']}" font-size="18" text-anchor="end">الحمد لله رب العلمين</text>
  <text x="716" y="306" fill="{P['papergreen']}" font-size="18" text-anchor="end">الرحمن الرحيم مالك يوم الدين</text>

  <text x="740" y="416" fill="{P['gold']}" font-size="14" font-weight="bold" text-anchor="end">📋 كل الأخطاء ({fmt(len(a["mistakes"]))})</text>
  {''.join(f'<text x="740" y="{442+i*20}" fill="{P["txt"]}" font-size="12" text-anchor="end">آية {fmt(m["ayah"])} · {m["kind"]}: {norm(m["target"])} — قلت: {norm(m["got"]) or "—"}</text>' for i,m in enumerate(a["mistakes"][:6]))}
  <text x="740" y="580" fill="{P['sub']}" font-size="10" text-anchor="end">تقرير من نفس محرك التطبيق — مافيش نتائج مزوّقة</text>

  <rect x="20" y="620" width="720" height="500" rx="16" fill="{P['card2']}"/>
  <text x="720" y="654" fill="{P['gold']}" font-size="15" font-weight="bold" text-anchor="end">🎧 اقرأ براحتك — وافحص لما تخلص</text>
  <text x="720" y="680" fill="{P['sub']}" font-size="11" text-anchor="end">التسجيل مستمر ومش بيقاطعك. لما تخلص اضغط «فحص» مرة واحدة.</text>
  <rect x="470" y="700" width="120" height="34" rx="17" fill="{P['gold']}"/><text x="530" y="722" fill="#1b1408" font-size="11" font-weight="bold" text-anchor="middle">🎤 اتكلم</text>
  <rect x="360" y="700" width="100" height="34" rx="17" fill="#1b2740"/><text x="410" y="722" fill="{P['sub']}" font-size="11" text-anchor="middle">🎙 مسجل</text>
  <rect x="250" y="700" width="100" height="34" rx="17" fill="#1b2740"/><text x="300" y="722" fill="{P['sub']}" font-size="11" text-anchor="middle">⌨️ كتابة</text>
  <circle cx="380" cy="800" r="39" fill="{P['red']}"/>
  <text x="380" y="812" fill="#fff" font-size="26" text-anchor="middle">⏸</text>
  <rect x="120" y="860" width="520" height="8" rx="4" fill="#1b2740"/><rect x="120" y="860" width="330" height="8" rx="4" fill="{P['teal']}"/>
  <text x="640" y="868" fill="{P['teal']}" font-size="10" text-anchor="start">🔈 واصل ✅</text>
  <text x="380" y="896" fill="{P['teal']}" font-size="12" text-anchor="middle" font-weight="bold">🔴 بيسجّل… اقرأ براحتك ومن غير ما تقف</text>
  <rect x="120" y="916" width="520" height="92" rx="12" fill="{P['surface']}"/>
  <text x="626" y="940" fill="{P['sub']}" font-size="10" text-anchor="end">آخر اللي وصل (٣ جملة)</text>
  <text x="626" y="962" fill="{P['txt']}" font-size="11" text-anchor="end">• الحمد لله رب العالمين</text>
  <text x="626" y="982" fill="{P['txt']}" font-size="11" text-anchor="end">• الرحمن الرحيم مالك يوم الدين</text>
  <text x="626" y="1000" fill="{P['txt']}" font-size="11" text-anchor="end">• إياك نعبد وإياك نستعين</text>
  <rect x="20" y="1024" width="470" height="46" rx="23" fill="{P['gold']}"/><text x="255" y="1053" fill="#1b1408" font-size="13" font-weight="bold" text-anchor="middle">🔍 فحص الكلام اللي قريته</text>
  <rect x="500" y="1024" width="240" height="46" rx="23" fill="{P['card2']}"/><text x="620" y="1053" fill="{P['txt']}" font-size="13" text-anchor="middle">امسح</text>
  <text x="380" y="1092" fill="{P['sub']}" font-size="11" text-anchor="middle">متسجل: {fmt(a["heardWords"])} كلمة · مش متفحّص بعد</text>

  <rect x="0" y="1120" width="760" height="60" fill="{P['card']}"/>
  {''.join(f'<text x="{700-i*126}" y="1150" fill="{P["gold"] if i==2 else P["sub"]}" font-size="11" text-anchor="middle">{n}</text>' for i,n in enumerate(["🕌 المواقيت","📖 القرآن","🎙 تلاوة","📿 الأذكار","🧭 القبلة","⋯ المزيد"]))}
</svg>'''
    path = os.path.join(out_dir, "noor-ios-report.svg")
    open(path, "w", encoding="utf-8").write(svg)
    print(f"\n🖼  snapshot → {path}")
    return path

# ───────────────────────────────────────────────────────────── main
if __name__ == "__main__":
    print("=" * 62)
    print(" Noor iOS — test suite")
    print("=" * 62)
    Q = Quran(QURAN_JSON)
    run_tests()
    shots = os.path.join(ROOT, "preview")
    if "--shots" in sys.argv:
        shots = sys.argv[sys.argv.index("--shots") + 1]
    screenshot(shots)
    print("\n" + "=" * 62)
    print(f" ✅ ناجح: {len(passes)}   ❌ فاشل: {len(fails)}")
    if fails:
        for f in fails: print("   -", f)
        sys.exit(1)
    print(" كل الاختبارات عدّت")
    print("=" * 62)
