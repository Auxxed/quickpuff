#!/usr/bin/env python3
"""Synthesise QuickPuff's sound cues: sounds/<name>.ogg.

Every cue is built here from oscillators, filtered noise and a small
convolution reverb, and most cues on top of public-domain (CC0) field
recordings kept in tools/sources/ (see SOURCES.md
there), so the sounds can ship under this repository's MIT license. Each cue is timed to the moment it plays
with in ReadyOverlay.qml or SessionOverlay.qml: the neon buzz follows the
sign's flicker, a smoke puff leaves with each ring, and a firework booms when
an average shell bursts.

Needs numpy, and ffmpeg for the Ogg Vorbis encode:

    python3 tools/make-sounds.py              # every cue
    python3 tools/make-sounds.py ready count  # just these
    python3 tools/make-sounds.py --wav DIR    # keep 48 kHz WAVs as well

The output is repeatable: each cue draws from its own seeded generator.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
import wave
import zlib
from pathlib import Path

import numpy as np

SR = 48_000
ROOT = Path(__file__).resolve().parent.parent
SOUNDS = ROOT / "sounds"
SOURCES = ROOT / "tools" / "sources"
FFMPEG = "/usr/bin/ffmpeg"
CEILING_DB = -1.0  # true-peak ceiling for every cue
TAU = 2 * np.pi


# ------------------------------------------------------------------ basics


def n_of(seconds: float) -> int:
    return int(round(seconds * SR))


def clock(seconds: float) -> np.ndarray:
    return np.arange(n_of(seconds)) / SR


def hz(name: str) -> float:
    """Equal-tempered frequency of a note name such as "A4" or "C#6"."""
    steps = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    semis = steps[pitch[0]] + pitch.count("#") - pitch.count("b")
    return 440.0 * 2.0 ** ((semis + 12 * (octave - 4)) / 12)


def db(value: float) -> float:
    return 10.0 ** (value / 20.0)


def smooth(x):
    """Smoothstep from 0 to 1 as x goes from 0 to 1."""
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def line(t, points):
    """Piecewise-linear envelope through (seconds, level) points."""
    xs, ys = zip(*points)
    return np.interp(t, xs, ys)


def hit(t, at, attack, tau):
    """Silent before `at`, a linear attack, then an exponential decay."""
    x = t - at
    rise = np.clip(x / attack, 0.0, 1.0)
    return np.where(x >= 0, rise * np.exp(-np.clip(x - attack, 0.0, None) / tau), 0.0)


# ------------------------------------------------------------- oscillators


def phase(freq, n):
    """Running phase in radians of a fixed or per-sample frequency."""
    return TAU * np.cumsum(np.broadcast_to(np.asarray(freq, dtype=float), (n,))) / SR


def sine(freq, n, offset=0.0):
    return np.sin(phase(freq, n) + offset)


def partials(freq, n, amps, ratios=None, offset=0.0):
    """A few sine partials at freq * ratio (harmonics unless ratios are given)."""
    ph = phase(freq, n) + offset
    top = float(np.max(freq))
    out = np.zeros(n)
    for k, amp in enumerate(amps, start=1):
        ratio = k if ratios is None else ratios[k - 1]
        if ratio * top < 20_000:
            out += amp * np.sin(ratio * ph)
    return out


def table(amps, size=4096):
    """One cycle of a waveform made of harmonics with these amplitudes."""
    k = np.arange(1, len(amps) + 1)[:, None]
    cycle = np.arange(size)[None, :] * TAU / size
    return (np.asarray(amps, dtype=float)[:, None] * np.sin(k * cycle)).sum(axis=0)


def play(tab, freq, n, offset=0.0):
    """Read a one-cycle table at a fixed or per-sample frequency."""
    cycles = np.cumsum(np.broadcast_to(np.asarray(freq, dtype=float), (n,))) / SR + offset
    pos = (cycles % 1.0) * len(tab)
    i = pos.astype(int)
    frac = pos - i
    return tab[i] * (1 - frac) + tab[(i + 1) % len(tab)] * frac


def saw(freq, n, offset=0.0, top=12_000.0):
    """Band-limited sawtooth, its harmonics stopping below `top` Hz."""
    count = max(1, min(240, int(top / float(np.max(freq)))))
    return play(table([2 / np.pi / k for k in range(1, count + 1)]), freq, n, offset)


# ------------------------------------------------------------------- noise


def noise(rng, n):
    return rng.standard_normal(n)


def tilted(rng, n, slope_db):
    """Unit-variance noise with a slope in dB per octave (pink -3, brown -6)."""
    size = 1 << int(np.ceil(np.log2(max(n, 2))))
    spec = np.fft.rfft(rng.standard_normal(size))
    f = np.fft.rfftfreq(size, 1 / SR)
    f[0] = f[1]
    spec *= (f / 1000.0) ** (slope_db / 6.0206)
    out = np.fft.irfft(spec, size)[:n]
    return out / (np.std(out) + 1e-12)


def events(rng, seconds, rate, peak):
    """Times of a Poisson process whose rate (per second) follows rate(t) <= peak."""
    times, t = [], 0.0
    while True:
        t += rng.exponential(1 / peak)
        if t >= seconds:
            return times
        if rng.uniform() * peak <= rate(t):
            times.append(t)


def grain(rng, seconds, centre, q):
    """A windowed burst of band-passed noise."""
    m = max(8, n_of(seconds))
    return filtered(rng.standard_normal(m) * np.hanning(m), bandpass(centre, q))


def recording(name):
    """A CC0 source clip from tools/sources/, decoded to 48 kHz stereo floats."""
    raw = subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-i", str(SOURCES / f"{name}.ogg"),
                          "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], stdout=subprocess.PIPE, check=True).stdout
    return np.frombuffer(raw, "<f4").reshape(-1, 2).T.astype(float)


def from_onset(clip, onset, lead=0.0):
    """The clip from `lead` seconds before `onset` on, faded in over 3 ms."""
    out = clip[:, max(0, n_of(onset - lead)):].copy()
    k = n_of(0.003)
    out[:, :k] *= np.linspace(0, 1, k)
    return out


# ----------------------------------------------------------------- filters


def lp_gain(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_gain(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-6)) ** (2 * order))


def bp_gain(f, fc, q):
    return 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / np.maximum(f, 1e-6))) ** 2)


def lowpass(fc, order=2):
    return lambda f: lp_gain(f, fc, order)


def highpass(fc, order=2):
    return lambda f: hp_gain(f, fc, order)


def bandpass(fc, q):
    return lambda f: bp_gain(f, fc, q)


def filtered(x, response):
    """Apply a zero-phase magnitude response, a function of frequency in Hz."""
    n = x.shape[-1]
    size = 1 << int(np.ceil(np.log2(n + 4096)))
    f = np.fft.rfftfreq(size, 1 / SR)
    return np.fft.irfft(np.fft.rfft(x, size) * response(f), size)[..., :n]


def swept(x, response, frame=2048, hop=256):
    """Filter with a response that changes over time. response(f, t) gets the
    frequencies in Hz as a row and the frame times in seconds as a column."""
    if x.ndim == 2:
        return np.vstack([swept(row, response, frame, hop) for row in x])
    n = len(x)
    win = np.hanning(frame + 1)[:-1]
    padded = np.concatenate([np.zeros(frame), x, np.zeros(2 * frame)])
    count = (len(padded) - frame) // hop + 1
    starts = hop * np.arange(count)
    frames = padded[starts[:, None] + np.arange(frame)[None, :]] * win
    f = np.fft.rfftfreq(frame, 1 / SR)[None, :]
    times = ((starts + frame / 2 - frame) / SR)[:, None]
    shaped = np.fft.irfft(np.fft.rfft(frames, axis=1) * response(f, times), frame, axis=1) * win
    out = np.zeros(len(padded))
    norm = np.zeros(len(padded))
    for start, chunk in zip(starts, shaped):
        out[start:start + frame] += chunk
        norm[start:start + frame] += win * win
    return (out / np.maximum(norm, 1e-9))[frame:frame + n]


# ------------------------------------------------------- stereo and space


def stereo(x):
    return np.vstack([x, x]) if x.ndim == 1 else x


def pan(x, position):
    """Equal-power pan, -1 left to 1 right, unity in the middle."""
    angle = (np.clip(position, -1, 1) + 1) * np.pi / 4
    return np.vstack([x * np.cos(angle), x * np.sin(angle)]) * np.sqrt(2)


def place(bus, sound, at):
    """Mix a mono or stereo sound into a stereo bus, starting `at` seconds in."""
    sound = stereo(sound)
    i = n_of(at)
    if i >= bus.shape[1]:
        return
    j = min(bus.shape[1], i + sound.shape[1])
    bus[:, i:j] += sound[:, :j - i]


def rms(x, start=0.0, end=None):
    seg = stereo(x)[:, n_of(start):None if end is None else n_of(end)]
    return float(np.sqrt(np.mean(seg ** 2))) + 1e-12


def scaled(x, level_db, start=0.0, end=None):
    """x with its RMS between start and end (seconds) at level_db dBFS."""
    return x * db(level_db) / rms(x, start, end)


def peaked(x, level_db):
    """x with its peak at level_db dBFS."""
    return x * db(level_db) / (float(np.max(np.abs(x))) + 1e-12)


def soft(x, ceiling_db=-3.0):
    """Round off peaks above about ceiling_db with a tanh knee."""
    c = db(ceiling_db)
    return c * np.tanh(x / c)


def convolve(a, b):
    size = 1 << int(np.ceil(np.log2(len(a) + len(b))))
    return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:len(a) + len(b) - 1]


def reverb(x, rng, seconds=1.4, wet=0.25, predelay=0.015, bright=7000.0, dark=1500.0):
    """Dry signal plus a stereo convolution reverb: decaying noise that darkens
    as it fades. `seconds` is the time to fall 60 dB."""
    dry = stereo(x)
    n = n_of(seconds * 1.1)
    t = np.arange(n) / SR
    darkening = lambda f, tt: lp_gain(f, np.maximum(dark, bright * np.exp(-tt / (seconds * 0.4))), 1)
    ir = swept(np.vstack([noise(rng, n), noise(rng, n)]) * np.exp(-6.908 * t / seconds), darkening)
    ir[:, :n_of(0.004)] *= np.linspace(0, 1, n_of(0.004))
    ir /= np.sqrt(np.mean(np.sum(ir ** 2, axis=1)))
    lag = n_of(predelay)
    out = np.zeros((2, dry.shape[1] + lag + n))
    out[:, :dry.shape[1]] += dry
    for ch in range(2):
        out[ch, lag:lag + dry.shape[1] + n - 1] += wet * convolve(dry[ch], ir[ch])
    return out


# ---------------------------------------------------------------- loudness

# ITU-R BS.1770 K-weighting at 48 kHz: a high shelf, then a high-pass.
_K_SHELF = ((1.53512485958697, -2.69169618940638, 1.19839281085285), (1.0, -1.69065929318241, 0.73248077421585))
_K_HIGHPASS = ((1.0, -2.0, 1.0), (1.0, -1.99004745483398, 0.99007225036621))


def _biquad(f, b, a):
    z = np.exp(-1j * TAU * f / SR)
    return np.abs((b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z))


def loudness(x):
    """Integrated loudness in LUFS (BS.1770: K-weighted, gated 400 ms blocks)."""
    k = filtered(stereo(x), lambda f: _biquad(f, *_K_SHELF) * _biquad(f, *_K_HIGHPASS))
    block, hop = n_of(0.4), n_of(0.1)
    if k.shape[1] < block:
        k = np.pad(k, ((0, 0), (0, block - k.shape[1])))
    power = np.array([np.sum(np.mean(k[:, s:s + block] ** 2, axis=1))
                      for s in range(0, k.shape[1] - block + 1, hop)])
    lk = -0.691 + 10 * np.log10(power + 1e-20)
    if not np.any(lk > -70):
        return -70.0
    relative = -0.691 + 10 * np.log10(power[lk > -70].mean()) - 10
    return float(-0.691 + 10 * np.log10(power[(lk > -70) & (lk > relative)].mean()))


def true_peak(x, factor=4):
    st = stereo(x)
    size = 1 << int(np.ceil(np.log2(st.shape[1])))
    return float(np.max(np.abs(np.fft.irfft(np.fft.rfft(st, size), size * factor) * factor)))


def level(x, lufs):
    """Scale to an integrated loudness, but never past the true-peak ceiling."""
    gain = db(lufs - loudness(x))
    peak = true_peak(x) * gain
    if peak > db(CEILING_DB):
        gain *= db(CEILING_DB) / peak
    return x * gain


def finish(x, seconds, fade):
    """Cut or pad to length, clear DC and rumble, and fade both ends."""
    st = filtered(stereo(x), highpass(20.0, 2))
    n = n_of(seconds)
    st = np.pad(st, ((0, 0), (0, max(0, n - st.shape[1]))))[:, :n].copy()
    st[:, :48] *= np.linspace(0, 1, 48)
    k = n_of(fade)
    st[:, -k:] *= np.linspace(1, 0, k) ** 2
    return st


# -------------------------------------------------------------------- cues

CUES = {}


def cue(seconds, lufs, fade=0.05):
    """Register a cue: its length, loudness and the fade at its end."""
    def register(fn):
        CUES[fn.__name__] = (fn, seconds, lufs, fade)
        return fn
    return register


@cue(0.6, -15.5)
def count(rng):
    """Countdown beep (3, 2, 1, a beat apart): a clean A5 with a crisp edge."""
    t = clock(0.6)
    n = len(t)
    f = hz("A5")
    body = partials(f, n, [1.0, 0.1, 0.035])
    body *= np.clip(t / 0.0015, 0, 1) * np.where(t < 0.12, 1.0, np.exp(-(t - 0.12) / 0.06))
    edge = sine(4 * f, n) * hit(t, 0, 0.0005, 0.006) * 0.12
    tick = filtered(noise(rng, n) * hit(t, 0, 0.0003, 0.0025), highpass(4000)) * 0.08
    return reverb(body + edge + tick, rng, seconds=0.45, wet=0.1, predelay=0.006)


def glass(t, at, f, amp):
    """A glassy struck note: decaying partials and an FM glint on the attack."""
    x = np.maximum(t - at, 0.0)
    body = np.zeros(len(t))
    for ratio, a, tau in ((1, 1.0, 0.42), (2, 0.32, 0.25), (3, 0.16, 0.16), (4.17, 0.1, 0.1), (5.43, 0.07, 0.06)):
        body += a * np.sin(TAU * f * ratio * x) * np.exp(-x / tau)
    glint = np.sin(TAU * f * x + 2.4 * np.exp(-x / 0.05) * np.sin(TAU * 3.5 * f * x)) * np.exp(-x / 0.12) * 0.45
    return (body + glint) * np.clip(x / 0.002, 0, 1) * (t >= at) * amp


@cue(2.0, -14.0, fade=0.3)
def ready(rng):
    """The ready chime: two glassy notes rising a fourth (E5 to A5) on a soft sub
    thump, then an airy shimmer of A, E and B. Also the trailer's sonic logo."""
    t = clock(2.0)
    n = len(t)
    bus = pan(glass(t, 0.0, hz("E5"), 0.85), -0.2) + pan(glass(t, 0.14, hz("A5"), 1.0), 0.2)
    sub = sine(line(t, [(0, 72), (0.2, 44), (3, 44)]), n) * hit(t, 0, 0.003, 0.09) * 0.35
    bus += stereo(filtered(sub, lowpass(180)))
    air = np.zeros((2, n))
    for name, amp in (("A5", 0.5), ("E6", 0.35), ("B6", 0.22)):
        for ch, cents in ((0, -7), (1, 7)):
            f = hz(name) * 2 ** (cents / 1200)
            air[ch] += amp * (np.sin(TAU * f * t + rng.uniform(0, TAU)) + 0.3 * np.sin(TAU * 2 * f * t + rng.uniform(0, TAU)))
    air *= line(t, [(0, 0), (0.14, 0), (0.4, 1), (1.5, 0), (3, 0)]) * (1 + 0.25 * np.sin(TAU * 5.5 * t)) * 0.07
    return reverb(bus + air, rng, seconds=1.5, wet=0.26, predelay=0.02)


@cue(1.9, -17.9, fade=0.3)
def complete(rng):
    """Session over: a soft mallet falling E5, C5, A4 over an open fifth."""
    t = clock(1.9)
    n = len(t)
    bus = np.zeros((2, n))
    for at, name, amp, side in ((0.0, "E5", 0.8, 0.2), (0.15, "C5", 0.85, -0.05), (0.30, "A4", 1.0, -0.2)):
        f, x = hz(name), np.maximum(t - at, 0.0)
        tone = (np.sin(TAU * f * x) * np.exp(-x / 0.55)
                + 0.22 * np.sin(TAU * 2 * f * x) * np.exp(-x / 0.22)
                + 0.06 * np.sin(TAU * 7.1 * f * x) * np.exp(-x / 0.02))
        bus += pan(tone * np.clip(x / 0.004, 0, 1) * (t >= at) * amp, side)
    pad = sum(a * (sine(hz(name), n) + 0.15 * sine(2 * hz(name), n)) for name, a in (("A3", 0.6), ("E4", 0.45)))
    bus += stereo(pad * line(t, [(0, 0), (0.3, 0), (0.7, 1), (1.9, 0)]) * 0.18)
    return reverb(filtered(bus, lowpass(7000, 1)), rng, seconds=1.4, wet=0.3, predelay=0.018)


@cue(2.5, -21.9, fade=0.25)
def ignite(rng):
    """Heat-up starts: a relay clicking in (CC0 recording), then a space heater's
    hum (CC0) swelling and brightening as the element comes up, over a quiet
    synthesised tone easing up an octave (A1 to A2)."""
    t = clock(2.5)
    n = len(t)
    click = np.zeros((2, n))
    place(click, from_onset(recording("relay-click"), 0.051, 0.002), 0)
    hum = np.zeros((2, n))
    place(hum, recording("heater-hum"), 0)
    hum = swept(hum, lambda f, tt: lp_gain(f, 250 + 5000 * smooth((tt - 0.05) / 1.9), 2))
    hum *= line(t, [(0, 0), (0.04, 0), (0.25, 0.4), (1.5, 1.0), (2.05, 1.0), (2.5, 0)])
    rise = smooth((t - 0.08) / 1.9)
    tone = play(table([1 / k ** 1.15 for k in range(1, 25)]), hz("A1") * 2 ** rise, n, rng.uniform())
    tone = filtered(tone, lowpass(900, 2)) * line(t, [(0, 0), (0.1, 0), (1.5, 1.0), (2.05, 1.0), (2.5, 0)])
    mix = peaked(click, -4) + scaled(hum, -20, 1.0, 2.0) + stereo(scaled(tone, -30, 1.0, 2.0))
    return reverb(mix, rng, seconds=0.7, wet=0.12)


@cue(3.0, -15.2, fade=0.3)
def liftoff(rng):
    """Liftoff: a real rocket motor lighting on the beat (CC0 recording), with a
    sub thump under its first moment, receding as it climbs away."""
    t = clock(3.0)
    n = len(t)
    motor = np.zeros((2, n))
    place(motor, from_onset(recording("rocket-launch"), 0.337, 0.005), 0)
    motor = swept(motor, lambda f, tt: lp_gain(f, np.interp(tt, [0, 1.0, 3.0], [16000, 9000, 1800]), 1))
    motor *= line(t, [(0, 1), (1.2, 1), (3.0, 0)]) ** 1.5
    thump = sine(line(t, [(0, 80), (0.3, 36), (3, 36)]), n) * hit(t, 0, 0.004, 0.22)
    mix = peaked(motor, -2) + stereo(peaked(thump, -9))
    return reverb(soft(mix, -2), rng, seconds=1.8, wet=0.12, predelay=0.02)


@cue(2.0, -15.5, fade=0.3)
def pop(rng):
    """Confetti: a real party popper and confetti cannon (CC0 recordings), then
    paper fluttering down."""
    t = clock(2.0)
    n = len(t)
    burst = np.zeros((2, n))
    place(burst, peaked(from_onset(recording("party-popper"), 0.076, 0.002), -1), 0)
    place(burst, peaked(from_onset(recording("confetti-cannon"), 0.011, 0.002), -5), 0.004)
    flutter = np.zeros((2, n))
    falling = lambda x: 380 * np.exp(-(x - 0.12) / 0.55) if x > 0.12 else 0.0
    for when in events(rng, 1.9, falling, 380):
        g = grain(rng, rng.uniform(0.008, 0.035), rng.uniform(2500, 9000), rng.uniform(1.5, 4.0))
        place(flutter, pan(g * rng.lognormal(0, 0.5), rng.uniform(-0.85, 0.85)), when)
    mix = soft(burst, -9) + scaled(flutter, -34, 0.2, 1.2)
    return reverb(mix, rng, seconds=0.9, wet=0.14, predelay=0.01)


@cue(5.6, -19.4, fade=1.2)
def bubbles(rng):
    """Lava lamp: thick liquid gurgling over hot bubbling mud (CC0 recordings),
    warm and soft, for the length of the show."""
    t = clock(5.6)
    n = len(t)
    goo, mud = np.zeros((2, n)), np.zeros((2, n))
    place(goo, recording("viscous-bubbling"), 0)
    place(mud, recording("hot-mud"), 0)
    bus = filtered(scaled(goo, -20) + scaled(mud, -29), lowpass(4500, 1))
    bus *= line(t, [(0, 0), (0.15, 1), (4.3, 1), (5.6, 0)])
    return reverb(bus, rng, seconds=0.8, wet=0.15, predelay=0.012)


@cue(6.5, -19.0, fade=0.4)
def shimmer(rng):
    """Aurora: a pad that swells and fades with the lights (in for 18 % of the
    6.5 s show, out over the last 30 %), sparkling with high chimes."""
    t = clock(6.5)
    n = len(t)
    lights = smooth(np.minimum(1, np.minimum(t / 1.17, (6.5 - t) / 1.95)))
    pad = np.zeros((2, n))
    for name in ("A3", "E4", "G4", "B4", "E5"):
        for ch in range(2):
            for cents in (-11, -4, 3, 10):
                f = hz(name) * 2 ** ((cents + rng.uniform(-2, 2)) / 1200)
                pad[ch] += saw(f, n, rng.uniform(), top=5000)
    pad = swept(pad / 20, lambda f, tt: lp_gain(f, 700 + 2300 * np.sin(np.pi * np.clip(tt / 6.5, 0, 1)), 2))
    pad *= lights * 0.5
    chimes = np.zeros((2, n))
    scale = [hz(name) for name in ("A5", "C6", "D6", "E6", "G6", "A6", "C7")]
    m = n_of(1.6)
    x = np.arange(m) / SR
    for when in np.sort(rng.uniform(0.35, 4.6, 13)):
        f = scale[rng.integers(len(scale))]
        bell = np.sin(TAU * f * x + 1.6 * np.exp(-x / 0.12) * np.sin(TAU * 3.5 * f * x))
        bell *= np.clip(x / 0.001, 0, 1) * np.exp(-x / 0.45) * (rng.uniform(0.1, 0.2) * np.interp(when, t, lights) + 0.03)
        side = rng.uniform(-0.8, 0.8)
        for k, (gain, where) in enumerate(((1.0, side), (0.38, -side), (0.15, side))):
            place(chimes, pan(bell * gain, where), when + 0.24 * k)
    air = filtered(np.vstack([noise(rng, n), noise(rng, n)]), highpass(7000)) * 0.012 * lights
    return reverb(pad + chimes + air, rng, seconds=3.2, wet=0.42, predelay=0.03)


@cue(3.0, -17.2, fade=0.4)
def firework(rng):
    """One shell (CC0 recordings): its whistle as it climbs and the burst 0.92 s
    after launch, when an average shell bursts on screen, with a second shell's
    burst layered in for the crackling tail."""
    t = clock(3.0)
    n = len(t)
    burst = 0.92
    shell = np.zeros((2, n))
    place(shell, from_onset(recording("firework-whistle-burst"), 1.163, burst), 0)
    tail = np.zeros((2, n))
    place(tail, from_onset(recording("firework-burst-crackle"), 1.533, 0.004), burst - 0.004)
    mix = peaked(shell, -1) + peaked(tail, -6)
    return reverb(soft(mix, -2), rng, seconds=2.2, wet=0.16, predelay=0.03)


@cue(4.0, -19.8, fade=0.4)
def smoke(rng):
    """Smoke rings: a soft puff of breath (CC0 recordings of real puffs) as each
    of the seven rings leaves, 0.48 s apart (one every 7.5 % of the 6.4 s show)."""
    t = clock(4.0)
    bus = np.zeros((2, len(t)))
    clip = recording("breath-puffs")
    puffs = [0.45, 2.30, 4.48, 5.44, 7.57, 8.41, 10.73]
    for i, onset in enumerate(puffs):
        puff = from_onset(clip, onset, 0.02)[:, :n_of(0.6)].copy()
        puff[:, -n_of(0.15):] *= np.linspace(1, 0, n_of(0.15))
        puff = filtered(puff, lowpass(5000, 1))
        place(bus, peaked(puff, -6 - 2 * rng.uniform()) * np.array([[1.0 - 0.3 * (i % 2)], [0.7 + 0.3 * (i % 2)]]), i * 0.48)
    return reverb(bus, rng, seconds=1.2, wet=0.22, predelay=0.012)


def neon_power(t):
    """The sign's brightness over time, as NeonSign.power in ReadyOverlay.qml."""
    ms = t * 1000
    steady = 0.92 + 0.08 * np.sin(t * 20)
    fading = np.clip((5.0 - t) / 0.9, 0, 1)
    return np.select([ms < 90, ms < 180, ms < 270, ms < 405, ms < 450, t > 4.1],
                     [0.0, 1.0, 0.15, 1.0, 0.4, fading], default=steady)


@cue(5.0, -18.5, fade=0.1)
def neon(rng):
    """Neon sign: a relay click, then a real neon lamp striking and humming (CC0
    recording), gated by the sign's own flicker and fading out with it."""
    t = clock(5.0)
    n = len(t)
    lamp = np.zeros((2, n))
    place(lamp, from_onset(recording("neon-lamp"), 0.325, 0.09), 0)
    power = filtered(neon_power(t), lowpass(250, 2))
    gate = np.where(t < 0.45, 0.3 + 0.7 * power, power)
    click = np.zeros((2, n))
    place(click, from_onset(recording("relay-click"), 0.051, 0.002), 0)
    settle = smooth((t - 0.5) / 0.4)
    strike, hum = lamp * (1 - settle), lamp * settle
    mix = (soft(peaked(strike, -8), -11) + scaled(hum, -21, 1.0, 4.0)) * gate + peaked(click, -14)
    return reverb(soft(mix, -10), rng, seconds=0.9, wet=0.1, predelay=0.01)


# -------------------------------------------------------------------- output


def render(name):
    fn, seconds, lufs, fade = CUES[name]
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    return level(finish(fn(rng), seconds, fade), lufs)


def write_wav(path, x):
    """24-bit stereo PCM."""
    pcm = np.round(np.clip(stereo(x), -1.0, 1.0).T * 8_388_607).astype("<i4")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(3)
        out.setframerate(SR)
        out.writeframes(pcm.reshape(-1, 1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes())


def encode(wav, dest):
    """Ogg Vorbis at about 160 kb/s, published with an atomic rename."""
    fd, tmp = tempfile.mkstemp(prefix=f".{dest.stem}.", suffix=".ogg", dir=dest.parent)
    os.close(fd)
    try:
        subprocess.run([FFMPEG, "-nostdin", "-v", "error", "-y", "-i", str(wav), "-map_metadata", "-1",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "5",
                        "-f", "ogg", tmp], check=True)
        os.chmod(tmp, 0o644)
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Synthesise QuickPuff's sound cues into sounds/.")
    parser.add_argument("names", nargs="*", metavar="cue", help=f"cues to make (default: all of {', '.join(sorted(CUES))})")
    parser.add_argument("--out", type=Path, default=SOUNDS, help="directory for the .ogg files (default: sounds/)")
    parser.add_argument("--wav", type=Path, help="also write each cue as a 48 kHz WAV into this directory")
    args = parser.parse_args(argv)
    unknown = sorted(set(args.names) - set(CUES))
    if unknown:
        parser.error("unknown cue: " + ", ".join(unknown))
    with tempfile.TemporaryDirectory() as scratch:
        for name in args.names or sorted(CUES):
            x = render(name)
            wav = Path(scratch) / f"{name}.wav"
            write_wav(wav, x)
            if args.wav:
                args.wav.mkdir(parents=True, exist_ok=True)
                write_wav(args.wav / f"{name}.wav", x)
            encode(wav, args.out / f"{name}.ogg")
            print(f"{name:9} {x.shape[1] / SR:4.2f} s  {loudness(x):6.1f} LUFS  {20 * np.log10(true_peak(x)):5.1f} dBTP")


if __name__ == "__main__":
    main()
