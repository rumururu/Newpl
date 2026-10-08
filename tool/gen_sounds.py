"""효과음/배경음악 합성 스크립트.

외부 음원 없이 numpy로 칩튠 스타일 사운드를 만든다 (저작권 걱정 없음).
실행: python3 tool/gen_sounds.py  ->  assets/audio/*.wav
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def save(name, x, vol=0.8):
    x = np.clip(x * vol, -1, 1)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def t(sec):
    return np.linspace(0, sec, int(SR * sec), endpoint=False)


def env(n, attack=0.005, release=None):
    e = np.ones(n)
    a = max(1, int(SR * attack))
    e[:a] = np.linspace(0, 1, a)
    r = n - a if release is None else int(SR * release)
    e[-r:] *= np.linspace(1, 0, r) ** 2
    return e


def sweep(f0, f1, sec, shape="square"):
    tt = t(sec)
    f = np.linspace(f0, f1, len(tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    return np.sin(ph)


def noise(sec, seed=0):
    return np.random.default_rng(seed).uniform(-1, 1, int(SR * sec))


def lowpass(x, k=8):
    return np.convolve(x, np.ones(k) / k, mode="same")


def main():
    os.makedirs(OUT, exist_ok=True)

    s = sweep(1400, 300, 0.12) * env(int(SR * 0.12))
    save("shoot", s, 0.25)

    s = lowpass(noise(0.08, 1), 3) * env(int(SR * 0.08))
    save("hit", s, 0.35)

    n = noise(0.5, 2)
    s = lowpass(n, 12) * env(int(SR * 0.5)) + sweep(200, 40, 0.5, "sine") * env(int(SR * 0.5)) * 0.6
    save("explode", s, 0.6)

    n = noise(1.2, 3)
    s = lowpass(n, 20) * env(int(SR * 1.2)) + sweep(150, 25, 1.2, "sine") * env(int(SR * 1.2))
    save("big_explode", s, 0.8)

    s = np.concatenate([sweep(900, 900, 0.05, "square"), sweep(1350, 1350, 0.08, "square")])
    save("pickup", s * env(len(s)), 0.2)

    s = np.concatenate([sweep(1975, 1975, 0.06, "square"), sweep(2637, 2637, 0.14, "square")])
    save("coin", s * env(len(s)), 0.18)

    notes = [1047, 1319, 1568, 2093]
    s = np.concatenate([sweep(f, f, 0.07, "sine") for f in notes])
    save("gem", s * env(len(s), release=0.15), 0.5)

    notes = [523, 659, 784, 1047, 1319]
    s = np.concatenate([sweep(f, f, 0.06, "square") * 0.5 + sweep(f * 2, f * 2, 0.06, "sine") * 0.5 for f in notes])
    save("upgrade", s * env(len(s), release=0.12), 0.35)

    s = np.concatenate([sweep(880, 660, 0.25, "square"), sweep(880, 660, 0.25, "square")])
    save("alarm", s * env(len(s)), 0.22)

    tt = t(1.2)
    s = sweep(100, 1800, 1.2, "sine") * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * tt))
    s += lowpass(noise(1.2, 4), 6) * np.linspace(0, 0.5, len(tt))
    save("warp", s * env(len(s), attack=0.2, release=0.4), 0.5)

    s = sweep(300, 900, 0.35, "saw") * 0.5 + lowpass(noise(0.35, 5), 4) * 0.5
    save("missile", s * env(len(s)), 0.35)

    tt = t(0.5)
    s = sweep(400, 1200, 0.5, "sine") * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * tt))
    save("shield", s * env(len(s), release=0.2), 0.45)

    s = lowpass(noise(0.3, 6), 2) * np.linspace(1, 0, int(SR * 0.3)) + sweep(200, 600, 0.3, "sine") * 0.5
    save("boost", s * env(len(s)), 0.4)

    s = sweep(300, 120, 0.18, "square") * env(int(SR * 0.18))
    save("hurt", s, 0.3)

    save("bgm", make_bgm(), 0.5)


def note_freq(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def make_bgm():
    """신나는 우주 모험 느낌의 8마디 반복 칩튠 (BPM 120)."""
    bpm = 120
    beat = 60 / bpm
    step = beat / 2  # 8분음표
    # 코드 진행: Am - F - C - G (2마디씩)
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
    melody = [
        76, 0, 74, 72, 74, 0, 69, 0, 72, 74, 76, 0, 79, 76, 74, 0,
        72, 0, 69, 72, 74, 0, 72, 0, 69, 0, 67, 69, 72, 0, 0, 0,
        76, 0, 79, 81, 79, 0, 76, 0, 74, 76, 72, 0, 74, 72, 69, 0,
        71, 0, 74, 0, 79, 0, 78, 79, 81, 0, 79, 0, 74, 0, 0, 0,
    ]
    total_steps = len(melody)
    n_step = int(SR * step)
    out = np.zeros(total_steps * n_step)
    rng = np.random.default_rng(9)
    for i in range(total_steps):
        seg = slice(i * n_step, (i + 1) * n_step)
        tt = np.arange(n_step) / SR
        chord = chords[(i // 16) % 4]
        # 베이스 (옥타브 점프)
        bn = chord[0] - 12 + (12 if i % 2 else 0)
        bass = np.sign(np.sin(2 * np.pi * note_freq(bn) * tt)) * 0.18
        bass *= np.linspace(1, 0.3, n_step)
        # 아르페지오
        an = chord[i % 3] + 12
        arp = np.sign(np.sin(2 * np.pi * note_freq(an) * tt)) * 0.06 * np.linspace(1, 0.2, n_step)
        # 멜로디
        mel = np.zeros(n_step)
        if melody[i]:
            f = note_freq(melody[i])
            vib = 1 + 0.004 * np.sin(2 * np.pi * 6 * tt)
            mel = (0.6 * np.sign(np.sin(2 * np.pi * f * vib * tt)) + 0.4 * np.sin(2 * np.pi * f * tt)) * 0.14
            mel *= np.minimum(1, np.linspace(1.3, 0.2, n_step))
        # 드럼
        drum = np.zeros(n_step)
        if i % 4 == 0:  # 킥
            drum += np.sin(2 * np.pi * np.cumsum(np.linspace(150, 40, n_step)) / SR) * np.linspace(1, 0, n_step) ** 3 * 0.5
        if i % 4 == 2:  # 스네어
            drum += rng.uniform(-1, 1, n_step) * np.linspace(1, 0, n_step) ** 4 * 0.22
        drum += rng.uniform(-1, 1, n_step) * np.exp(-tt * 120) * 0.05  # 하이햇
        out[seg] = bass + arp + mel + drum
    # 두 바퀴 = 약 16초
    return np.concatenate([out, out])


if __name__ == "__main__":
    main()
