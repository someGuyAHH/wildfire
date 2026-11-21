#!/usr/bin/env python3
"""
Builds assets/sfx/ from the raw CC0 packs in tools/audio/sources/ (git-ignored; where each came from
is in assets/CREDITS.md). Needs ffmpeg and numpy.

    python3 tools/audio/build_sfx.py            # rebuild every sound
    python3 tools/audio/build_sfx.py step_ jump # only the ones whose name starts with these

Each sound is a recipe: one or more source layers (with an ffmpeg filter chain, gain and offset), mixed,
silence trimmed, normalised to a loudness target for its kind (so the bank's volume_db is only about
balance), and written as a mono 44.1 kHz WAV (one-shots) or a stereo OGG (loops and ambience).
Loops are cut from a section of the source and crossfaded tail into head, so the file loops with no seam
(AudioStreamOggVorbis.loop in the bank).
"""
import os, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "sources")
OUT = os.path.join(HERE, "..", "..", "assets", "sfx")
SR = 44100

KIND_DIRS = {"shot": "one_shots", "loop": "loops", "amb": "ambience"}
# target RMS (dBFS) of the sound's active part, and the peak ceiling
TARGET = {"shot": (-17.0, -1.0), "loop": (-22.0, -1.5), "amb": (-26.0, -1.5)}


def kn(pack, name): return os.path.join(SRC, "kenney_" + pack, name + ".ogg")
def oga(*p): return os.path.join(SRC, "oga", *p)


def decode(path, af="", ch=1):
    cmd = ["ffmpeg", "-v", "error", "-i", path]
    if af: cmd += ["-af", af]
    cmd += ["-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    a = np.frombuffer(raw, dtype=np.float32)
    return a.reshape(-1, ch) if ch > 1 else a.reshape(-1, 1)


def L(path, af="", gain=0.0, at=0.0, ss=0.0, dur=0.0):
    """A layer: a source file, ffmpeg filters, gain in dB, start offset in the mix (s), and a cut of the source."""
    return dict(path=path, af=af, gain=gain, at=at, ss=ss, dur=dur)


def render(layers, ch):
    parts = []
    for l in layers:
        af = l["af"]
        cut = ""
        if l["ss"] or l["dur"]:
            end = ":end=%.4f" % (l["ss"] + l["dur"]) if l["dur"] else ""
            cut = "atrim=start=%.4f%s,asetpts=PTS-STARTPTS" % (l["ss"], end)
        chain = ",".join(x for x in (cut, af) if x)
        a = decode(l["path"], chain, ch) * (10 ** (l["gain"] / 20))
        parts.append((int(l["at"] * SR), a))
    n = max(o + len(a) for o, a in parts)
    mix = np.zeros((n, ch), dtype=np.float32)
    for o, a in parts: mix[o:o + len(a)] += a
    return mix


def trim_silence(a, floor_db=-48.0):
    peak = np.max(np.abs(a))
    if peak <= 0: return a
    mono = np.max(np.abs(a), axis=1)
    idx = np.nonzero(mono > peak * 10 ** (floor_db / 20))[0]
    return a[idx[0]:idx[-1] + 1] if len(idx) else a


def fade(a, fin=0.002, fout=0.02):
    a = a.copy()
    ni, no = min(int(fin * SR), len(a) // 2), min(int(fout * SR), len(a) // 2)
    if ni: a[:ni] *= np.linspace(0, 1, ni)[:, None]
    if no: a[-no:] *= np.linspace(1, 0, no)[:, None]
    return a


def make_loop(a, start, length, xf):
    """Cut [start, start+length+xf), blend the extra tail over the head: loops with no seam."""
    s = int(start * SR); n = int(length * SR); x = int(xf * SR)
    seg = a[s:s + n + x]
    if len(seg) < n + x: raise SystemExit("loop source too short: need %.1f s" % (start + length + xf))
    out = seg[:n].copy()
    t = np.linspace(0, np.pi / 2, x)[:, None]
    out[:x] = seg[:x] * np.sin(t) + seg[n:n + x] * np.cos(t) # equal power
    return out


def normalise(a, kind):
    rms_t, peak_t = TARGET[kind]
    # RMS over the loud part only (a click with a long quiet tail shouldn't be boosted to fill it)
    env = np.max(np.abs(a), axis=1)
    loud = env > np.max(env) * 10 ** (-24 / 20)
    body = a[loud] if loud.sum() > 64 else a
    rms = np.sqrt(np.mean(body ** 2)) + 1e-9
    g = 10 ** (rms_t / 20) / rms
    peak = np.max(np.abs(a)) * g
    lim = 10 ** (peak_t / 20)
    if peak > lim: g *= lim / peak
    return a * g


def write(a, kind, name):
    d = os.path.join(OUT, KIND_DIRS[kind])
    os.makedirs(d, exist_ok=True)
    pcm = (np.clip(a, -1, 1) * 32767).astype("<i2").tobytes()
    ch = a.shape[1]
    base = ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", str(ch), "-i", "-"]
    if kind == "shot":
        path = os.path.join(d, name + ".wav")
        subprocess.run(base + [path], input=pcm, check=True)
    else:
        path = os.path.join(d, name + ".ogg")
        subprocess.run(base + ["-c:a", "libvorbis", "-q:a", "4", path], input=pcm, check=True)
    return path


SPECS = []  # (name, kind, layers, options)
def S(name, layers, kind="shot", **opt): SPECS.append((name, kind, layers, opt))
def variants(name, count, make, kind="shot", **opt):
    for i in range(count): S("%s_%d" % (name, i), make(i), kind, **opt)


SW = lambda n: oga("swishes", "swish-%d.wav" % n)
WIND = oga("wind.wav")
FIRE = oga("fire.wav")
RUMBLE = oga("rumble.wav")
IMP = lambda n, i: kn("impact", "%s_%03d" % (n, i))
CC = lambda n: oga("cc0_100", n + ".ogg")
BANG = lambda i: oga("cc0_bang", "bang_%02d.ogg" % i)
WAT = lambda n: oga("water", n + ".ogg")

# ---- movement (one-shots, played at the character)
variants("step_concrete", 5, lambda i: [L(IMP("footstep_concrete", i))])
variants("step_grass", 5, lambda i: [L(IMP("footstep_grass", i))])
variants("step_wood", 5, lambda i: [L(IMP("footstep_wood", i))])
variants("jump", 3, lambda i: [L(SW(3 + i), "lowpass=f=5000", dur=0.3), L(IMP("impactSoft_medium", i), "asetrate=52920,aresample=44100", -6)])
variants("land_light", 3, lambda i: [L(IMP("impactSoft_medium", i), "lowpass=f=4500")])
variants("land_heavy", 3, lambda i: [L(IMP("impactPunch_heavy", i)), L(IMP("impactSoft_heavy", i), "", -3)])
variants("dash", 3, lambda i: [L(SW(1 + 4 * i), "", 0), L(kn("scifi", "thrusterFire_%03d" % i), "highpass=f=400,afade=t=out:st=0.25:d=0.2", -8, dur=0.45)])
variants("wall_jump", 3, lambda i: [L(IMP("impactPlank_medium", i)), L(SW(6 + i), "", -4, 0.02, dur=0.3)])
WH = oga("whoosh2_0.wav")
S("slam_start", [L(WH, "asetrate=35000,aresample=44100,lowpass=f=4000,afade=t=in:d=0.08,afade=t=out:st=0.3:d=0.2", dur=0.7)])
variants("slam_land", 2, lambda i: [L(CC("slam_0%d" % (1 + i))), L(IMP("impactPunch_heavy", i), "", -2),
                                     L(kn("scifi", "lowFrequency_explosion_000"), "lowpass=f=300", 3, dur=0.9)])
variants("vault", 2, lambda i: [L(IMP("impactSoft_heavy", i), "lowpass=f=3000", -3), L(SW(10 + i), "", -3, 0.03, dur=0.3)])
S("brake_air", [L(WH, "asetrate=50000,aresample=44100,afade=t=in:d=0.05,afade=t=out:st=0.2:d=0.2", dur=0.45)])
variants("bonk", 3, lambda i: [L(IMP("impactPunch_heavy", i), "lowpass=f=2500"), L(IMP("impactPlate_heavy", i), "", -4)])
variants("pad_launch", 2, lambda i: [L(CC("spring_0%d" % (2 + i))), L(SW(7), "", -6, dur=0.35)])
# ---- movement (loops)
S("slide_loop", [L(WIND, "highpass=f=700,lowpass=f=5200,volume=3", ss=2.0, dur=6.0)], "loop", loop=(0.0, 3.0, 0.5))
S("wall_slide_loop", [L(WIND, "highpass=f=300,lowpass=f=1800,volume=2", ss=8.0, dur=6.0)], "loop", loop=(0.0, 3.0, 0.5))
S("wind_speed", [L(WIND, "highpass=f=250,lowpass=f=9000", ss=12.0, dur=14.0)], "loop", loop=(0.0, 10.0, 1.5))
# ---- the slam-jump's launch, in layers the game fades in by how high you go (see SfxDef.gate_*): a thud and a light crack
# always; rock crunch from a middling launch; scattered gravel and falling debris after; a deep boom with cracking stone on top
import random as _random
variants("slam_jump_thud", 2, lambda i: [L(IMP("impactPunch_heavy", i), "lowpass=f=1100"), L(CC("hit_0%d" % (2 + i)), "", -7),
                                          L(kn("scifi", "lowFrequency_explosion_001"), "lowpass=f=140", -6, dur=0.5)])
variants("slam_jump_crunch", 2, lambda i: [L(IMP("impactMining", i), "", 0), L(IMP("impactMining", i + 2), "", -2, 0.05),
                                            L(kn("scifi", "explosionCrunch_00%d" % (1 + i)), "lowpass=f=2200", -5, 0.0, dur=0.6),
                                            L(FIRE, "highpass=f=1600,volume=2,afade=t=out:st=0.3:d=0.3", -9, 0.02, ss=6.0 + 4 * i, dur=0.7)])
def _debris(seed):
    r = _random.Random(seed)
    layers = [L(FIRE, "highpass=f=2500,lowpass=f=9000,volume=1.5,afade=t=in:d=0.1,afade=t=out:st=1.3:d=0.9", -12, 0.1, ss=9.0 + 5 * seed, dur=2.2)]
    for k in range(34): # stones falling back: dense at first, then fewer, quieter, a little later each
        t = 0.08 + 1.9 * (r.random() ** 1.6)
        n = r.choice(["footstep_concrete", "footstep_grass", "impactMining", "impactPlate_light"])
        f = IMP(n, r.randrange(5))
        layers.append(L(f, "lowpass=f=%d,asetrate=%d,aresample=44100" % (r.choice([2500, 4000, 6000]), r.choice([40000, 44100, 50000])), -4 - 8 * (t / 2.0) - r.random() * 4, t))
    return layers
variants("slam_jump_debris", 2, lambda i: _debris(i))
S("slam_jump_boom", [L(kn("scifi", "lowFrequency_explosion_000"), "asetrate=36000,aresample=44100,lowpass=f=170", 2),
                      L(CC("explosion"), "lowpass=f=400,asetrate=36000,aresample=44100", -3), L(CC("slam_07"), "lowpass=f=800", -4, 0.02),
                      L(kn("scifi", "explosionCrunch_004"), "lowpass=f=1800", -6, 0.05, dur=0.9),
                      L(IMP("impactMining", 4), "lowpass=f=2500", -4, 0.25)])
# ---- the hard stop's ear ring (a synthesised sine pair, no source file)
S("tinnitus", [], "loop", synth=lambda: ear_ring())
# ---- fire
variants("ignite", 3, lambda i: [L(oga("flame_0.ogg"), "", 0), L(kn("scifi", "explosionCrunch_%03d" % i), "lowpass=f=2400", -5, dur=0.6),
                                  L(kn("scifi", "thrusterFire_%03d" % (i + 2)), "afade=t=out:st=0.3:d=0.2", -9, dur=0.5)])
S("torch_loop", [L(FIRE, "lowpass=f=7000", ss=4.0, dur=12.0)], "loop", loop=(0.0, 8.0, 1.0))
S("smolder_loop", [L(FIRE, "highpass=f=2200,lowpass=f=9000", ss=15.0, dur=8.0)], "loop", loop=(0.0, 5.0, 0.8))
# the fire going out: a flame sucked away (the catching-fire clip reversed) over a short, dry hiss; no water (the
# first version used splashes and sounded like a bucket of water: Bora, 2026-11-21)
variants("extinguish", 2, lambda i: [L(oga("flame_0.ogg"), "areverse,lowpass=f=3500", 0, 0.0),
                                      L(WIND, "highpass=f=3500,lowpass=f=9000,volume=6,afade=t=in:d=0.08,afade=t=out:st=0.3:d=0.35", -5, 0.12, ss=20 + 3 * i, dur=0.7)])
S("smoke_warn", [L(RUMBLE, "lowpass=f=600,afade=t=in:d=0.5,afade=t=out:st=1.4:d=0.6", ss=2.0, dur=2.0),
                 L(kn("scifi", "lowFrequency_explosion_001"), "lowpass=f=250", -3, 0.0, dur=1.2)])
# a heavy whump with a crack on top (the first, lighter shove was too weak to notice; Bora, 2026-11-21)
variants("shove", 3, lambda i: [L(IMP("impactPunch_heavy", i + 1)), L(CC("hit_0%d" % (1 + i)), "", -2),
                                 L(kn("scifi", "impactMetal_00%d" % i), "lowpass=f=3500", -6, dur=0.4),
                                 L(kn("scifi", "lowFrequency_explosion_000"), "lowpass=f=180", -4, dur=0.4)])
# ---- modes
variants("fuse_tick", 2, lambda i: [L(kn("digital", "tone1"), "asetrate=%d,aresample=44100,afade=t=out:st=0.04:d=0.04" % (36000 + 5000 * i), dur=0.09)])
S("fuse_loop", [L(oga("fuse_0.ogg"), "")], "loop", loop=(0.0, 0.42, 0.1))
variants("explosion", 2, lambda i: [L(BANG(3 + 2 * i)), L(kn("scifi", "explosionCrunch_00%d" % (3 + i)), "", -2),
                                    L(kn("scifi", "lowFrequency_explosion_00%d" % i), "lowpass=f=400", 2)])
S("storm_start", [L(RUMBLE, "lowpass=f=500,afade=t=in:d=1.0,afade=t=out:st=3.0:d=1.2", ss=5.0, dur=4.2),
                  L(kn("scifi", "lowFrequency_explosion_000"), "lowpass=f=200", 0)])
S("storm_loop", [L(RUMBLE, "lowpass=f=700", ss=0.0, dur=10.0), L(WIND, "highpass=f=500,lowpass=f=3000,volume=1.5", -8, ss=22.0, dur=10.0)],
  "loop", loop=(0.0, 7.0, 1.5))
S("countdown_beep", [L(kn("digital", "tone1"), "", dur=0.25)])
S("countdown_go", [L(kn("digital", "powerUp7"))])
S("win", [L(kn("digital", "powerUp1")), L(kn("digital", "threeTone1"), "", -4, 0.0)])
S("lose", [L(kn("digital", "lowDown")), L(kn("digital", "zapThreeToneDown"), "", -4, 0.1)])
S("lava_in", [L(WAT("splash_0%d" % 7), "lowpass=f=1800"), L(oga("flame_0.ogg"), "", -2, 0.05), L(CC("explosion"), "lowpass=f=800", -6)])
# ---- ambience (stereo loops)
S("amb_wind", [L(WIND, "lowpass=f=5000", ss=0.0, dur=24.0)], "amb", ch=2, loop=(0.0, 20.0, 3.0))
# the Overworld's plains: just a soft, low breeze (the old amb_outdoor bed was busy and noisy; the far birds that came
# next chirped high and kept going in the menu's background: Bora, 2026-11-21)
S("amb_plains", [L(WIND, "lowpass=f=700,volume=0.5", -2, ss=4.0, dur=34.0)], "amb", ch=2, loop=(0.0, 30.0, 3.0))
S("amb_jungle", [L(oga("amb_morning_0.ogg"), "", ss=2.0, dur=58.0)], "amb", ch=2, loop=(0.0, 50.0, 6.0))
S("amb_lava", [L(RUMBLE, "lowpass=f=450", ss=0.0, dur=14.0), L(FIRE, "lowpass=f=1800,volume=0.7", -6, ss=2.0, dur=14.0)],
  "amb", ch=2, loop=(0.0, 11.0, 2.5))
S("amb_hall", [L(oga("dungeon_ambient_1_0.ogg"), "lowpass=f=3500", ss=4.0, dur=88.0)], "amb", ch=2, loop=(0.0, 76.0, 8.0))
# ---- UI (played flat, no position)
S("ui_hover_1", [L(kn("ui", "rollover2"))]) # the one Bora kept of three (2026-11-21)
variants("ui_click", 3, lambda i: [L(kn("ui", "click%d" % (1 + i)))])
S("ui_back", [L(kn("interface", "back_001"))])
S("ui_confirm", [L(kn("interface", "confirmation_001"))])
variants("ui_toggle", 2, lambda i: [L(kn("interface", "toggle_00%d" % (1 + i)))])
S("ui_tick_0", [L(kn("ui", "click3"), "asetrate=52000,aresample=44100")]) # the lowest-pitched of three (Bora, 2026-11-21)
# (a third ui_turn variant was dropped: Bora, 2026-11-21)
variants("ui_turn", 2, lambda i: [L(kn("ui", "switch%d" % (10 + i)), "afade=t=out:st=0.1:d=0.08", dur=0.2)])
variants("ui_whoosh", 2, lambda i: [L(WH, "asetrate=%d,aresample=44100,lowpass=f=7000,afade=t=in:d=0.08,afade=t=out:st=0.25:d=0.25" % (44100 + 9000 * i), dur=0.6)])
variants("ui_pop", 3, lambda i: [L(oga("cc0_100", "plop_0%d.ogg" % (1 + i % 2)), "asetrate=%d,aresample=44100" % (44100 + 3500 * i)), L(kn("interface", "drop_00%d" % (1 + i)), "", -6)])
S("ui_open", [L(kn("interface", "open_001"))])
S("ui_close", [L(kn("interface", "close_001"))])


def ear_ring():
    """The ear ring after a hard stop (tinnitus): a soft sine pair about 3.2 kHz that beats gently (2.5 Hz), a slow
    wobble in level (0.25 Hz, +-12%) and a faint fifth-ish overtone at 4.1 kHz. 4 s long; every frequency is a whole
    number of cycles in it, so the loop has no seam. Nothing above 4.1 kHz at all, nothing harsh."""
    n = 4 * SR
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 3200.0 * t) + np.sin(2 * np.pi * 3202.5 * t) + 0.18 * np.sin(2 * np.pi * 4100.0 * t + 1.1)
    wobble = 1.0 + 0.12 * np.sin(2 * np.pi * 0.25 * t)
    return (tone * wobble * 0.3).astype(np.float32)[:, None]


def build(name, kind, layers, opt):
    ch = opt.get("ch", 1)
    if "synth" in opt:
        return write(normalise(opt["synth"](), kind), kind, name), 4.0
    a = render(layers, ch)
    if "loop" in opt:
        a = make_loop(a, *opt["loop"])
    else:
        a = fade(trim_silence(a))
    a = normalise(a, kind)
    path = write(a, kind, name)
    return path, len(a) / SR


if __name__ == "__main__":
    only = sys.argv[1:]
    for name, kind, layers, opt in SPECS:
        if only and not any(name.startswith(o) for o in only): continue
        path, dur = build(name, kind, layers, opt)
        print("%-22s %-5s %6.2f s  %s" % (name, kind, dur, os.path.relpath(path, os.path.join(HERE, "..", ".."))))
