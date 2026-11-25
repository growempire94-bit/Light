"""Synthesize Ukrainian voiceover lines with RHVoice (voice: Volodymyr) and trim silences."""
import json, subprocess, pathlib

RATE = "117"
root = pathlib.Path(__file__).parent
out = root / "audio" / "vo"
out.mkdir(parents=True, exist_ok=True)
durations = {}
for line in (root / "lines.tsv").read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    lid, text = line.split("\t", 1)
    raw = out / f"{lid}.raw.wav"
    subprocess.run(["RHVoice-test", "-p", "volodymyr", "-r", RATE, "-o", str(raw)],
                   input=text.encode("utf-8"), check=True, capture_output=True)
    wav = out / f"{lid}.wav"
    trim = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
            "silenceremove=start_periods=1:start_threshold=-45dB,areverse")
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(raw), "-af", trim,
                    "-ar", "48000", "-ac", "1", str(wav)], check=True)
    raw.unlink()
    d = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                       "-of", "csv=p=0", str(wav)]).decode().strip())
    durations[lid] = {"text": text, "dur": round(d, 3)}
    print(lid, round(d, 2))
(out / "durations.json").write_text(json.dumps(durations, ensure_ascii=False, indent=1), encoding="utf-8")
print("total", round(sum(v["dur"] for v in durations.values()), 2))
