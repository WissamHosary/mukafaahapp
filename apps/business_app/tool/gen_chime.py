"""Synthesises the Business app alert chime: a soft two-tone bell (~0.6 s).

Run: python3 tool/gen_chime.py  ->  assets/sounds/alert.wav (mono, 22.05 kHz, 16-bit).
"""
import math
import os
import struct
import wave

RATE = 22050
LENGTH = 0.62  # seconds
# (start seconds, fundamental Hz, gain): G5 then C6, a rising "ding-dong".
NOTES = [(0.0, 783.99, 0.85), (0.14, 1046.50, 1.0)]
# Bell-like partials (ratio, relative gain, decay multiplier).
PARTIALS = [(1.0, 1.0, 1.0), (2.0, 0.32, 1.6), (2.76, 0.18, 2.2), (5.40, 0.06, 3.5)]


def sample(t: float) -> float:
    v = 0.0
    for start, f0, gain in NOTES:
        dt = t - start
        if dt < 0:
            continue
        attack = min(1.0, dt / 0.004)  # 4 ms attack, no click
        for ratio, g, decay_mul in PARTIALS:
            env = math.exp(-dt * 7.5 * decay_mul)
            v += gain * g * attack * env * math.sin(2 * math.pi * f0 * ratio * dt)
    return v


def main() -> None:
    n = int(RATE * LENGTH)
    raw = [sample(i / RATE) for i in range(n)]
    # Fade the tail to silence over the last 60 ms.
    fade = int(RATE * 0.06)
    for i in range(fade):
        raw[n - fade + i] *= 1 - i / fade
    peak = max(abs(x) for x in raw) or 1.0
    scale = 0.7 * 32767 / peak
    out = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds', 'alert.wav')
    with wave.open(out, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(x * scale)) for x in raw))
    print(f'wrote {os.path.normpath(out)} ({os.path.getsize(out)} bytes)')


if __name__ == '__main__':
    main()
