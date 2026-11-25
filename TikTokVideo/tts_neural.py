"""Neural Ukrainian voiceover with robinhad/ukrainian-tts v6 (ESPnet VITS, offline).

Usage (inside a Python 3.10 env with torch==1.13.1, espnet==202301, kaldiio, soundfile):
    python tts_neural.py <model_dir> [voice] [speed]
model_dir holds model.pth, config.yaml, spk_xvector.ark, feats_stats.npz from
https://github.com/robinhad/ukrainian-tts/releases/tag/v6.0.0
voice: mykyta | tetiana | lada | dmytro | oleksa.  tempo > 1.0 speaks faster
(the model is Tacotron2 + vocoder, so speed is changed afterwards with rubberband).

Stress is taken from lines_stressed.tsv ('+' before the stressed vowel), so no
stress-dictionary models are needed. Captions use the plain text from lines.tsv.
"""
import json, os, pathlib, subprocess, sys, tempfile
import soundfile as sf
import torch
from espnet2.bin.tts_inference import Text2Speech
from kaldiio import load_ark

root = pathlib.Path(__file__).resolve().parent
model_dir = pathlib.Path(sys.argv[1]).resolve()
os.chdir(model_dir)  # config.yaml refers to feats_stats.npz by relative path
voice = sys.argv[2] if len(sys.argv) > 2 else "mykyta"
tempo = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
VOWELS = "аеєиіїоуюя"
ALPHA = VOWELS + "бвгґджзйклмнпрстфхцчшщь" + "'-" + "+"
SYMBOLS = {"«": '"', "»": '"', "—": "-", "–": "-", "’": "'", "ʼ": "'"}


def prepare(text):
    text = text.lower()
    for a, b in SYMBOLS.items():
        text = text.replace(a, b)
    # split into words / separators the same way ukrainian-tts does
    parts, prev = [], 0
    for i, ch in enumerate(text):
        if ch not in ALPHA:
            if prev != i:
                parts.append(text[prev:i])
            parts.append(ch)
            prev = i + 1
    if prev < len(text):
        parts.append(text[prev:])
    out = []
    for p in parts:
        nv = sum(c in VOWELS for c in p)
        if "+" in p:
            first = p.find("+")  # model was trained with one stress per token
            p = p[:first + 1] + p[first + 1:].replace("+", "")
        elif nv == 1:
            i = next(i for i, c in enumerate(p) if c in VOWELS)
            p = p[:i] + "+" + p[i:]
        elif nv > 1:
            print("  warning: no stress mark in", p)
        out.append(p)
    return "".join(out)


plain = dict(l.split("\t", 1) for l in (root / "lines.tsv").read_text(encoding="utf-8").splitlines() if l.strip())
stressed = dict(l.split("\t", 1) for l in (root / "lines_stressed.tsv").read_text(encoding="utf-8").splitlines() if l.strip())

tts = Text2Speech(train_config=str(model_dir / "config.yaml"), model_file=str(model_dir / "model.pth"),
                  device="cpu")
xv = {k: v for k, v in load_ark(str(model_dir / "spk_xvector.ark"))}
out = root / "audio" / "vo"
out.mkdir(parents=True, exist_ok=True)
durations = {}
torch.manual_seed(1)
for lid, text in stressed.items():
    prepared = prepare(text)
    with torch.no_grad():
        wav = tts(prepared, spembs=xv[voice][0])["wav"].view(-1).cpu().numpy()
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        sf.write(tmp.name, wav, tts.fs, "PCM_16")
    dst = out / f"{lid}.wav"
    trim = (f"rubberband=tempo={tempo},silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
            "silenceremove=start_periods=1:start_threshold=-45dB,areverse")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", tmp.name, "-af", trim,
                    "-ar", "48000", "-ac", "1", str(dst)], check=True)
    os.unlink(tmp.name)
    d = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                       "-of", "csv=p=0", str(dst)]).decode())
    durations[lid] = {"text": plain[lid], "dur": round(d, 3)}
    print(lid, round(d, 2), prepared)
(out / "durations.json").write_text(json.dumps(durations, ensure_ascii=False, indent=1), encoding="utf-8")
print("voice", voice, "tempo", tempo, "total", round(sum(v["dur"] for v in durations.values()), 2))
