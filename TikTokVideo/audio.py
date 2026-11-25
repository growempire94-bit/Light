"""Synthesize the music bed and sound effects, then mix them with the voiceover.

Everything is generated with numpy/scipy, so the soundtrack has no third-party copyright.
Outputs:
  audio/mix_voice.wav    – voice + music + sfx (main version)
  audio/mix_novoice.wav  – music + sfx only (to record your own voice over it)
"""
import json, pathlib
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
root = pathlib.Path(__file__).parent
T = json.loads((root / "timeline.json").read_text(encoding="utf-8"))
DUR = T["duration"]
N = int(DUR * SR) + SR // 2
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def lp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "low", fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def place(buf, x, at, gain=1.0):
    i = int(round(at * SR))
    if i >= len(buf):
        return
    if i < 0:
        x = x[-i:]; i = 0
    n = min(len(x), len(buf) - i)
    buf[i:i + n] += gain * x[:n]


def adsr(n, a=0.005, d=0.1, s=0.6, r=0.1, hold=None):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    hold_n = n - a_n - d_n - r_n if hold is None else int(hold * SR)
    hold_n = max(hold_n, 0)
    env = np.concatenate([np.linspace(0, 1, a_n, endpoint=False), np.linspace(1, s, d_n, endpoint=False),
                          np.full(hold_n, s), np.linspace(s, 0, r_n)])
    return np.pad(env, (0, max(0, n - len(env))))[:n]


def saw(freq, tt, detune_cents=0.0, phase=0.0):
    f = freq * 2 ** (detune_cents / 1200)
    return signal.sawtooth(2 * np.pi * f * tt + phase)


# ---------------------------------------------------------------- instruments
def kick(gain=1.0):
    tt = t_axis(0.45)
    f = 45 + 110 * np.exp(-tt / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-tt / 0.16)
    click = hp(rng.standard_normal(len(tt)), 2500) * np.exp(-tt / 0.004) * 0.3
    return gain * (body + click)


def clap(gain=1.0):
    tt = t_axis(0.3)
    n = bp(rng.standard_normal(len(tt)), 900, 5000)
    env = np.zeros_like(tt)
    for off in (0.0, 0.011, 0.022):
        env += np.where(tt >= off, np.exp(-(tt - off) / 0.008), 0) * 0.6
    env += np.where(tt >= 0.03, np.exp(-(tt - 0.03) / 0.09), 0)
    return gain * 0.5 * n * env


def hat(open_=False, gain=1.0):
    tt = t_axis(0.25 if open_ else 0.06)
    n = hp(rng.standard_normal(len(tt)), 7000, 4)
    return gain * 0.35 * n * np.exp(-tt / (0.07 if open_ else 0.015))


def bass_note(m, length, gain=1.0):
    tt = t_axis(length)
    f = midi(m)
    x = 0.6 * saw(f, tt) + 0.5 * np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(np.pi * f * tt)
    x = lp(x, 700, 2)
    return gain * x * adsr(len(tt), 0.004, 0.08, 0.7, 0.04)


def pad_chord(notes, length, gain=1.0, cutoff=2400):
    tt = t_axis(length)
    L = np.zeros_like(tt); R = np.zeros_like(tt)
    for m in notes:
        f = midi(m)
        L += saw(f, tt, -9) + 0.7 * saw(f, tt, 6, 1.0)
        R += saw(f, tt, 9, 0.5) + 0.7 * saw(f, tt, -5, 2.0)
    env = adsr(len(tt), 0.03, 0.3, 0.75, 0.15)
    L = lp(L, cutoff, 2) * env; R = lp(R, cutoff, 2) * env
    return gain * 0.09 * np.stack([L, R], 1)


def pluck(m, gain=1.0, length=0.22, bright=5000):
    tt = t_axis(length)
    f = midi(m)
    x = signal.square(2 * np.pi * f * tt, 0.3) * 0.5 + saw(f, tt, 7) * 0.5
    x = lp(x, bright, 2) * np.exp(-tt / 0.07)
    return gain * 0.18 * x


def bell(freq, length=0.9, gain=1.0):
    tt = t_axis(length)
    x = (np.sin(2 * np.pi * freq * tt) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * tt) * np.exp(-tt / 0.1)
         + 0.2 * np.sin(2 * np.pi * freq * 5.4 * tt) * np.exp(-tt / 0.05))
    return gain * 0.35 * x * np.exp(-tt / (length / 3.5)) * np.minimum(1, tt / 0.002)


# ------------------------------------------------------------------- music
BEAT = 0.5          # 120 BPM
BAR = 4 * BEAT
PROG = [  # (pad voicing, bass note, arp notes)
    ((57, 60, 64), 45, (69, 72, 76, 81)),   # Am
    ((57, 60, 65), 41, (65, 69, 72, 77)),   # F
    ((55, 60, 64), 48, (67, 72, 76, 79)),   # C
    ((55, 59, 62), 43, (67, 71, 74, 79)),   # G
]
S = T["scenes"]; C = T["cues"]


def groove(start, end, drums=True, full=True, lead=False):
    """Render a section of the song between start..end (seconds), bars anchored at `start`."""
    length = end - start
    out = np.zeros((int((length + 2.5) * SR), 2))
    kick_times = []
    nbars = int(np.ceil(length / BAR))
    for b in range(nbars):
        bt = b * BAR
        pad, bassm, arp = PROG[b % 4]
        place(out, pad_chord(pad, BAR + 0.1, 1.0 if full else 0.8, 2600 if full else 1800), bt)
        for s16 in range(16):
            t16 = bt + s16 * BEAT / 4
            if t16 >= length:
                break
            beat_i, sub = divmod(s16, 4)
            if drums:
                if full or beat_i in (0, 2):
                    if sub == 0:
                        k = kick(0.9 if full else 0.55)
                        place(out, np.stack([k, k], 1), t16); kick_times.append(t16)
                if sub == 0 and beat_i in (1, 3):
                    c = clap(0.9 if full else 0.5); place(out, np.stack([c, c], 1), t16)
                if sub == 2:
                    h = hat(open_=full and beat_i % 2 == 1, gain=0.9); place(out, np.stack([h * 0.8, h], 1), t16)
                elif full and sub in (1, 3):
                    h = hat(gain=0.45); place(out, np.stack([h, h * 0.8], 1), t16)
            if full and sub in (0, 2, 3) or (not full and sub == 0):
                bn = bass_note(bassm + (12 if (sub == 3 and full) else 0), BEAT / 4 * (2 if sub == 0 else 1) * 0.95, 0.55)
                place(out, np.stack([bn, bn], 1), t16)
            # arpeggio
            note = arp[[0, 1, 2, 3, 2, 1, 2, 3][s16 % 8]] + (12 if lead and s16 % 8 in (3, 7) else 0)
            g = 0.9 if lead else (0.55 if full else 0.75)
            p = pluck(note, g)
            pan = 0.35 * np.sin(s16 * 0.8)
            place(out, np.stack([p * (1 - pan), p * (1 + pan)], 1), t16)
    # sidechain pump on everything except kick (approximation: whole bus, gentle)
    pump = np.ones(len(out))
    for kt in kick_times:
        i = int(kt * SR); n = int(0.25 * SR)
        seg = 1 - 0.35 * np.exp(-np.arange(n) / SR / 0.07)
        j = min(len(pump), i + n)
        pump[i:j] = np.minimum(pump[i:j], seg[:j - i])
    out *= pump[:, None]
    return out


music = np.zeros((N, 2))
# intro: glam, light drums
intro = groove(0.0, S["scratch"], drums=True, full=False)
cut = int(S["scratch"] * SR)
intro = intro[:cut + int(0.4 * SR)]
# tape-stop on the last 0.4s
ts_n = int(0.4 * SR)
seg = intro[cut:cut + ts_n]
speed = np.linspace(1, 0, ts_n) ** 1.5
pos = np.cumsum(speed); pos = pos / pos[-1] * (ts_n * 0.45)
tape = np.stack([np.interp(pos, np.arange(ts_n), seg[:, ch]) for ch in (0, 1)], 1) * np.linspace(1, 0, ts_n)[:, None]
place(music, intro[:cut], 0.0)
place(music, tape, S["scratch"])

# main groove from S2 until the final hit
final_hit = C["enroll"]
main = groove(S["S2"], final_hit, drums=True, full=True)
main_end = int((final_hit - S["S2"]) * SR)
main = main[:main_end]
# extra lead layer for the careers + finale sections
lead = groove(S["S5"], S["S6"], drums=False, full=False, lead=True)[: int((S["S6"] - S["S5"]) * SR)]
main[int((S["S5"] - S["S2"]) * SR): int((S["S5"] - S["S2"]) * SR) + len(lead)] += 0.5 * lead
# muffled ("boring" / "scary") passages: crossfade to lowpassed copy
muff = np.stack([lp(main[:, ch], 500, 2) for ch in (0, 1)], 1) * 0.8
w = np.zeros(len(main))
for a, b in ((S["S3"], S["S3b"]), (S["S4"], S["S4b"])):
    ia, ib = int((a - S["S2"]) * SR), int((b - S["S2"]) * SR)
    fade = int(0.08 * SR)
    w[ia:ib] = 1
    w[ia:ia + fade] = np.linspace(0, 1, fade)
    w[ib - fade:ib] = np.linspace(1, 0, fade)
main = main * (1 - w[:, None]) + muff * w[:, None]
fo = int(0.03 * SR)
main[-fo:] *= np.linspace(1, 0, fo)[:, None]
place(music, main, S["S2"])

# final chord hit with a long tail (C major, wide)
tail_len = DUR - final_hit + 0.3
hit = pad_chord((48, 55, 60, 64, 67, 72), tail_len, 2.2, 3500)
hit *= np.exp(-np.arange(len(hit)) / SR / 1.3)[:, None]
for m in (72, 76, 79, 84):
    b_ = bell(midi(m), 1.8, 0.35); place(hit, np.stack([b_, b_], 1), 0.0)
k = kick(1.2); place(hit, np.stack([k, k], 1), 0.0)
place(music, hit, final_hit)

# simple stereo reverb on the music bus (exponential-noise IR)
ir_t = t_axis(1.6)
ir = rng.standard_normal((len(ir_t), 2)) * np.exp(-ir_t / 0.35)[:, None]
ir[:, 0] = lp(ir[:, 0], 6000); ir[:, 1] = lp(ir[:, 1], 6000)
ir /= np.sqrt((ir ** 2).sum(0))
wet = np.stack([signal.fftconvolve(music[:, ch], ir[:, ch])[:N] for ch in (0, 1)], 1)
music = music + 0.22 * wet


# --------------------------------------------------------------------- sfx
def sfx_pop():
    tt = t_axis(0.09)
    f = 700 + 900 * (tt / 0.09)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.025) * 0.6


def sfx_shutter():
    out = np.zeros(int(0.2 * SR))
    for at, d in ((0.0, 0.012), (0.07, 0.03)):
        tt = t_axis(d * 6)
        n = hp(rng.standard_normal(len(tt)), 2500) * np.exp(-tt / d)
        place(out, n * 0.6, at)
    return out


def sfx_scratch():
    tt = t_axis(0.5)
    f = 250 + 1100 * np.abs(np.sin(2 * np.pi * 2.2 * tt)) ** 1.5
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = signal.sawtooth(ph) * 0.4
    noise = rng.standard_normal(len(tt))
    blocks = []
    for i in range(0, len(tt), 512):
        fc = float(np.clip(f[i] * 2.2, 400, 9000))
        blocks.append(bp(noise[i:i + 512], fc * 0.6, min(fc * 1.6, 20000)))
    nz = np.concatenate(blocks)[:len(tt)]
    x = (tone + nz * 0.8) * np.minimum(1, tt / 0.01) * np.where(tt > 0.42, np.exp(-(tt - 0.42) / 0.03), 1)
    return lp(x, 6000) * 0.8


def sfx_whoosh(length=0.45):
    tt = t_axis(length)
    noise = rng.standard_normal(len(tt))
    out = np.zeros_like(noise)
    for i in range(0, len(tt), 480):
        p = i / len(tt)
        fc = 300 + 3500 * p ** 1.5
        out[i:i + 480] = bp(noise[i:i + 480], fc * 0.5, fc * 1.5)
    env = np.sin(np.pi * tt / length) ** 2
    return out * env * 0.5


def sfx_impact():
    tt = t_axis(1.0)
    f = 38 + 90 * np.exp(-tt / 0.06)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.35)
    crack = lp(rng.standard_normal(len(tt)), 3000) * np.exp(-tt / 0.03) * 0.5
    return (boom + crack) * 0.8


def sfx_blip():
    out = np.zeros(int(0.3 * SR))
    for at, fr in ((0.0, 1320), (0.09, 1760)):
        tt = t_axis(0.08)
        place(out, np.sin(2 * np.pi * fr * tt) * np.exp(-tt / 0.03) * 0.45, at)
    return out


def sfx_achievement():
    out = np.zeros(int(1.2 * SR))
    for i, m in enumerate((84, 88, 91, 96)):
        place(out, bell(midi(m), 0.9, 0.7), i * 0.06)
    return out


def sfx_tick():
    tt = t_axis(0.08)
    return (np.sin(2 * np.pi * 2200 * tt) * np.exp(-tt / 0.015) * 0.4
            + hp(rng.standard_normal(len(tt)), 4000) * np.exp(-tt / 0.003) * 0.3)


def sfx_stamp():
    tt = t_axis(0.5)
    f = 60 + 120 * np.exp(-tt / 0.02)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.09)
    slap = bp(rng.standard_normal(len(tt)), 300, 3000) * np.exp(-tt / 0.02) * 0.7
    return (thud + slap) * 0.9


def sfx_alarm():
    tt = t_axis(1.6)
    f = np.where((tt * 2.5).astype(int) % 2 == 0, 660, 880)
    x = signal.square(2 * np.pi * np.cumsum(f) / SR) * 0.25
    return lp(x, 2500) * np.minimum(1, tt / 0.02) * np.where(tt > 1.4, np.exp(-(tt - 1.4) / 0.05), 1)


def sfx_ding():
    out = bell(1568, 1.0, 0.8)
    out[:int(0.8 * SR)] += bell(2093, 0.8, 0.3)
    return out


def sfx_shimmer():
    out = np.zeros(int(1.2 * SR))
    for i in range(14):
        place(out, bell(rng.uniform(2200, 6000), 0.5, 0.25), i * 0.05 + rng.uniform(0, 0.02))
    return out


def sfx_riser():
    tt = t_axis(1.2)
    noise = hp(rng.standard_normal(len(tt)), 1500)
    f = 200 + 1000 * (tt / 1.2) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3
    return (noise * 0.25 + tone) * (tt / 1.2) ** 2


SFX = {"pop": sfx_pop, "shutter": sfx_shutter, "scratch": sfx_scratch, "whoosh": sfx_whoosh,
       "impact": sfx_impact, "blip": sfx_blip, "achievement": sfx_achievement, "tick": sfx_tick,
       "stamp": sfx_stamp, "alarm": sfx_alarm, "ding": sfx_ding, "shimmer": sfx_shimmer, "riser": sfx_riser}
fxbus = np.zeros(N)
for ev in T["sfx"]:
    start = ev["t"] - (1.2 if ev["kind"] == "riser" else 0.0)
    place(fxbus, SFX[ev["kind"]](), start, ev["gain"])

# ------------------------------------------------------------------ voice
vo = np.zeros(N)
for lid, ln in T["lines"].items():
    sr, x = wavfile.read(root / "audio" / "vo" / f"{lid}.wav")
    assert sr == SR
    x = x.astype(np.float64) / 32768.0
    place(vo, x, ln["start"])
# light voice processing: high-pass, presence lift, normalize
vo = hp(vo, 90)
vo = vo + 0.25 * bp(vo, 2500, 6000)
vo /= np.max(np.abs(vo)) + 1e-9
vo *= 0.85

# ducking envelope from voice activity
act = np.zeros(N)
for ln in T["lines"].values():
    a, b = int((ln["start"] - 0.08) * SR), int((ln["end"] + 0.15) * SR)
    act[max(a, 0):b] = 1
act = signal.lfilter([1 - np.exp(-1 / (0.06 * SR))], [1, -np.exp(-1 / (0.06 * SR))], act)


def norm(x, peak=0.9):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


music = norm(music, 1.0)
fxs = norm(fxbus, 1.0)

duck = 1 - 0.5 * act
mix_voice = (music * (0.40 * duck)[:, None] + (fxs * 0.38)[:, None] + vo[:, None])
mix_novoice = music * 0.55 + (fxs * 0.45)[:, None]

end = int(DUR * SR)
fade = int(0.6 * SR)
for name, m in (("mix_voice", mix_voice), ("mix_novoice", mix_novoice)):
    m = m[:end].copy()
    m[-fade:] *= np.linspace(1, 0, fade)[:, None]
    m = norm(m, 0.95)
    wavfile.write(root / "audio" / f"{name}.wav", SR, (m * 32767).astype(np.int16))
    print("wrote", name, round(len(m) / SR, 2), "s")
