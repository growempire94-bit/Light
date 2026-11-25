"""Build timeline.json: when each voice line / word / scene / sound effect happens.

Word timings are estimated by matching punctuation-separated phrases to the pauses
that ffmpeg's silencedetect finds in each synthesized line, then spreading words
inside a phrase by syllable count.
"""
import json, re, subprocess, pathlib

root = pathlib.Path(__file__).parent
vo = json.loads((root / "audio" / "vo" / "durations.json").read_text(encoding="utf-8"))
VOWELS = set("аеєиіїоуюяАЕЄИІЇОУЮЯaeiouyAEIOUY")


def silences(lid):
    out = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(root / "audio" / "vo" / f"{lid}.wav"),
                          "-af", "silencedetect=noise=-38dB:d=0.07", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    st = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", out)]
    en = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", out)]
    return list(zip(st, en))


def tokens(text):
    raw = text.split()
    words = []
    for t in raw:
        if t in ("—", "-") and words:
            words[-1]["boundary"] = True
            continue
        words.append({"w": t, "boundary": bool(re.search(r"[,:.?!»]$", t)) and not t.endswith("«")})
    words[-1]["boundary"] = False
    return words


def syl(w):
    return max(1, sum(ch in VOWELS for ch in w)) + 0.35


def align(lid, start):
    d = vo[lid]["dur"]
    words = tokens(vo[lid]["text"])
    phrases, cur = [], []
    for w in words:
        cur.append(w)
        if w["boundary"]:
            phrases.append(cur); cur = []
    if cur:
        phrases.append(cur)
    sil = [s for s in silences(lid) if 0.05 < s[0] and s[1] < d - 0.05]
    nb = len(phrases) - 1
    if nb and len(sil) >= nb:
        sil = sorted(sorted(sil, key=lambda s: s[0] - s[1])[:nb])  # longest nb pauses, in time order
        segs, prev = [], 0.0
        for s0, s1 in sil:
            segs.append((prev, s0)); prev = s1
        segs.append((prev, d))
    else:  # fallback: whole line proportional
        tot = sum(sum(syl(w["w"]) for w in p) for p in phrases)
        segs, acc = [], 0.0
        for p in phrases:
            ln = d * sum(syl(w["w"]) for w in p) / tot
            segs.append((acc, acc + ln)); acc += ln
    out = []
    for p, (a, b) in zip(phrases, segs):
        tot = sum(syl(w["w"]) for w in p)
        acc = a
        for w in p:
            ln = (b - a) * syl(w["w"]) / tot
            out.append({"w": w["w"], "s": round(start + acc, 3), "e": round(start + acc + ln, 3),
                        "boundary": w["boundary"]})
            acc += ln
    return out


lines, scenes, sfx = {}, {}, []


def say(lid, at):
    lines[lid] = {"start": round(at, 3), "end": round(at + vo[lid]["dur"], 3), "text": vo[lid]["text"],
                  "words": align(lid, at)}
    return at + vo[lid]["dur"]


def word_t(lid, needle, which=0):
    hits = [w for w in lines[lid]["words"] if needle.lower() in w["w"].lower()]
    return hits[which]["s"]


# ---- schedule -------------------------------------------------------------
scenes["S1"] = 0.0
e = say("L1", 0.30)
scenes["scratch"] = round(e + 0.10, 3)
scenes["S2"] = round(e + 0.55, 3)
e = say("L2", scenes["S2"] + 0.10)
e = say("L3", e + 0.30)
scenes["S3"] = round(e + 0.40, 3)
e = say("L4", scenes["S3"] + 0.05)
scenes["S3b"] = round(e + 0.20, 3)
e = say("L5", scenes["S3b"] + 0.05)
scenes["S4"] = round(e + 0.45, 3)
e = say("L6", scenes["S4"] + 0.05)
scenes["S4b"] = round(e + 0.25, 3)
e = say("L7", scenes["S4b"] + 0.05)
scenes["S5"] = round(e + 0.70, 3)
e = say("L8", scenes["S5"] + 0.05)
for i, k in enumerate("abcde"):
    e = say(f"L9{k}", e + (0.20 if i == 0 else 0.15))
scenes["S6"] = round(e + 0.40, 3)
e = say("L10", scenes["S6"] + 0.05)
scenes["S6b"] = round(e + 0.25, 3)
e = say("L11", scenes["S6b"] + 0.05)
scenes["S7"] = round(e + 0.35, 3)
e = say("L12", scenes["S7"] + 0.10)
END = round(e + 1.9, 3)
scenes["END"] = END

# ---- key visual cues (absolute seconds) -----------------------------------
cues = {
    "biz": word_t("L1", "бізнес"),
    "selfie": word_t("L1", "селфі"),
    "dubai": word_t("L1", "Дубаї"),
    "warsaw": word_t("L2", "Варшаву"),
    "nine": word_t("L2", "дев"),
    "twelve": word_t("L2", "дванадцятій"),
    "shanghai": word_t("L2", "Шанхай"),
    "six": word_t("L2", "шостій"),
    "toronto": word_t("L2", "Торонто"),
    "deal_skill": word_t("L3", "домовитись"),
    "quest": word_t("L5", "квест"),
    "cargo": word_t("L5", "вантаж"),
    "logistics": word_t("L5", "логістика"),
    "duty": word_t("L5", "мито"),
    "fx": word_t("L5", "курс"),
    "deal": word_t("L5", "угода"),
    "translate": word_t("L7", "перекладає"),
    "calc": word_t("L7", "рахує"),
    "people": word_t("L7", "людьми"),
    "me": word_t("L7", "я."),
    "program": word_t("L10", "«Менеджмент"),
    "poly": word_t("L10", "Одеській"),
    "odesa": word_t("L11", "Одеса"),
    "gates": word_t("L11", "твої"),
    "reality": word_t("L12", "Реальність"),
    "better": word_t("L12", "цікавіша"),
    "enroll": word_t("L12", "Вступай"),
}
for k in "abcde":
    cues[f"job_{k}"] = lines[f"L9{k}"]["start"]

# ---- captions: chunks of <=3 words / ~20 chars, split at phrase boundaries --
NO_CAPTION = {"L8", "L9a", "L9b", "L9c", "L9d", "L9e"}
captions = []
for lid, ln in lines.items():
    if lid in NO_CAPTION:
        continue
    chunk = []
    chunks = []
    for w in ln["words"]:
        chunk.append(w)
        n_chars = sum(len(x["w"]) for x in chunk)
        if w["boundary"] or len(chunk) >= 3 or n_chars >= 18:
            chunks.append(chunk); chunk = []
    if chunk:
        chunks.append(chunk)
    for i, c in enumerate(chunks):
        s = c[0]["s"] - 0.04
        e2 = chunks[i + 1][0]["s"] - 0.04 if i + 1 < len(chunks) else ln["end"] + 0.25
        captions.append({"s": round(s, 3), "e": round(e2, 3),
                         "words": [{"w": w["w"], "s": w["s"], "e": w["e"]} for w in c]})

# ---- sound effects ---------------------------------------------------------
def fx(t, kind, gain=1.0):
    sfx.append({"t": round(t, 3), "kind": kind, "gain": gain})


fx(0.02, "shimmer", 0.8)
fx(0.32, "pop", 0.9)
fx(cues["biz"], "pop", 0.6)
fx(cues["selfie"], "shutter", 1.0)
fx(scenes["scratch"], "scratch", 1.0)
for k in ("S2", "S3", "S3b", "S4", "S4b", "S5", "S6", "S6b", "S7"):
    fx(scenes[k] - 0.18, "whoosh", 0.7)
fx(scenes["S2"] + 0.02, "impact", 0.9)
fx(scenes["S3b"] + 0.02, "impact", 0.6)
fx(scenes["S4b"] + 0.02, "impact", 0.6)
for k in ("warsaw", "shanghai", "toronto"):
    fx(cues[k], "blip", 0.8)
fx(cues["deal_skill"], "achievement", 0.9)
fx(scenes["S3"] + 0.05, "pop", 0.5)
for k in ("cargo", "logistics", "duty", "fx"):
    fx(cues[k], "tick", 0.8)
fx(cues["deal"], "stamp", 1.0)
fx(cues["deal"] + 0.55, "achievement", 0.8)
fx(scenes["S4"] + 0.03, "alarm", 0.55)
fx(cues["translate"], "tick", 0.7)
fx(cues["calc"], "tick", 0.7)
fx(cues["me"] - 0.05, "achievement", 0.9)
fx(scenes["S5"] + 0.05, "pop", 0.7)
for k in "abcde":
    fx(cues[f"job_{k}"], "pop", 0.9)
fx(cues["program"], "ding", 0.7)
fx(cues["poly"], "ding", 0.7)
fx(cues["gates"], "stamp", 0.8)
fx(scenes["S7"], "riser", 0.6)
fx(cues["enroll"], "impact", 1.0)

timeline = {"fps": 30, "width": 1080, "height": 1920, "duration": END, "scenes": scenes,
            "cues": {k: round(v, 3) for k, v in cues.items()}, "lines": lines, "captions": captions,
            "sfx": sorted(sfx, key=lambda x: x["t"])}
(root / "timeline.json").write_text(json.dumps(timeline, ensure_ascii=False, indent=1), encoding="utf-8")
print("duration", END)
for k, v in scenes.items():
    print(f"  {k:8s} {v:6.2f}")
