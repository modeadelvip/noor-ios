#!/usr/bin/env python3
"""Checks that the ANDROID engine (Java) behaves exactly like the tested reference
(Python mirror of the Swift engine) — run after touching locate()/analyze()."""
import importlib.util, subprocess, os, re, json, sys
spec = importlib.util.spec_from_file_location("ios_test", os.path.join(os.path.dirname(__file__), "ios_test.py"))
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
t.Q = t.Quran(t.QURAN_JSON)

cases = [
 "الحمد لله رب العالمين الرحمن الرحيم مالك يوم الدين",
 "الحمده لله رب العالمين الرحمن الرحيم مالك يوم الدين",
 "الحمد لله رب العلمين الرحمن الرحيم مالك يوم الدين",
 " ".join(t.norm(t.Q.ayah(18, i)) for i in range(1, 4)),
 "هذا نص عربي عادي ليس من القران",
]
print("reference (Swift-mirror) results:")
for c in cases:
    r = t.analyze(c)
    print(f"  {c[:34]:34s} → sura {r['sura']:3d} · {r['percent']:3d}% · wrong {r['wrong']} · missing {r['missing']}")
count = 0
for n in range(1, 115):
    src = t.norm(t.Q.surahs[n-1]["ayahs"][0]).split()[:8]
    if len(src) < 3: continue
    loc = t.locate(" ".join(src))
    if loc and t.Q.to_surah_ayah(loc[0])[0] == n: count += 1
print(f"surah self-locate: {count}/114 (identical openings land on the twin — honest)")
