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
variants("skid", 2, lambda i: [L(WIND, "bandpass=f=2600:w=2200,volume=4,afade=t=in:d=0.04,afade=t=out:st=0.2:d=0.18", ss=3 + 2 * i, dur=0.4)])
S("brake_air", [L(WH, "asetrate=50000,aresample=44100,afade=t=in:d=0.05,afade=t=out:st=0.2:d=0.2", dur=0.45)])
variants("bonk", 3, lambda i: [L(IMP("impactPunch_heavy", i), "lowpass=f=2500"), L(IMP("impactPlate_heavy", i), "", -4)])
variants("pad_launch", 2, lambda i: [L(CC("spring_0%d" % (2 + i))), L(SW(7), "", -6, dur=0.35)])
# ---- movement (loops)
S("slide_loop", [L(WIND, "highpass=f=700,lowpass=f=5200,volume=3", ss=2.0, dur=6.0)], "loop", loop=(0.0, 3.0, 0.5))
S("wall_slide_loop", [L(WIND, "highpass=f=300,lowpass=f=1800,volume=2", ss=8.0, dur=6.0)], "loop", loop=(0.0, 3.0, 0.5))
S("wind_speed", [L(WIND, "highpass=f=250,lowpass=f=9000", ss=12.0, dur=14.0)], "loop", loop=(0.0, 10.0, 1.5))
# ---- fire
variants("ignite", 3, lambda i: [L(oga("flame_0.ogg"), "", 0), L(kn("scifi", "explosionCrunch_%03d" % i), "lowpass=f=2400", -5, dur=0.6),
                                  L(kn("scifi", "thrusterFire_%03d" % (i + 2)), "afade=t=out:st=0.3:d=0.2", -9, dur=0.5)])
S("torch_loop", [L(FIRE, "lowpass=f=7000", ss=4.0, dur=12.0)], "loop", loop=(0.0, 8.0, 1.0))
S("smolder_loop", [L(FIRE, "highpass=f=2200,lowpass=f=9000", ss=15.0, dur=8.0)], "loop", loop=(0.0, 5.0, 0.8))
variants("extinguish", 2, lambda i: [L(WAT("splash_0%d" % (3 + i)), "lowpass=f=4200"),
                                      L(WIND, "highpass=f=4500,volume=5,afade=t=in:d=0.05,afade=t=out:st=0.6:d=0.6", -6, ss=20 + 3 * i, dur=1.2)])
S("smoke_warn", [L(RUMBLE, "lowpass=f=600,afade=t=in:d=0.5,afade=t=out:st=1.4:d=0.6", ss=2.0, dur=2.0),
                 L(kn("scifi", "lowFrequency_explosion_001"), "lowpass=f=250", -3, 0.0, dur=1.2)])
variants("shove", 3, lambda i: [L(IMP("impactPunch_medium", i)), L(SW(2 + i), "", -4, 0.0, dur=0.3)])
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
S("amb_outdoor", [L(oga("amb_outdoor1_loop.ogg"), "", ss=0.0, dur=29.5)], "amb", ch=2, loop=(0.0, 26.0, 3.0))
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
variants("ui_tick", 3, lambda i: [L(kn("ui", "click%d" % (3 + i)), "asetrate=52000,aresample=44100")])
variants("ui_turn", 3, lambda i: [L(kn("ui", "switch%d" % (10 + i)), "afade=t=out:st=0.1:d=0.08", dur=0.2)])
variants("ui_whoosh", 2, lambda i: [L(WH, "asetrate=%d,aresample=44100,lowpass=f=7000,afade=t=in:d=0.08,afade=t=out:st=0.25:d=0.25" % (44100 + 9000 * i), dur=0.6)])
variants("ui_pop", 3, lambda i: [L(oga("cc0_100", "plop_0%d.ogg" % (1 + i % 2)), "asetrate=%d,aresample=44100" % (44100 + 3500 * i)), L(kn("interface", "drop_00%d" % (1 + i)), "", -6)])
S("ui_open", [L(kn("interface", "open_001"))])
S("ui_close", [L(kn("interface", "close_001"))])


def build(name, kind, layers, opt):
    ch = opt.get("ch", 1)
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
