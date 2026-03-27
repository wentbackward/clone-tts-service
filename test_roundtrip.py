#!/usr/bin/env python3
"""
Round-trip TTS→STT test harness for Clone Voice Service.

Generates audio via TTS, transcribes it back via STT, and compares.
Includes short/long text tests and concurrent stress tests.

Usage:
    python test_roundtrip.py [HOST]       # default: http://localhost:3030
    python test_roundtrip.py --parallel   # also run concurrency tests
"""

import sys
import time
import io
import difflib
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

HOST = "http://localhost:3030"
RUN_PARALLEL = False
for arg in sys.argv[1:]:
    if arg == "--parallel":
        RUN_PARALLEL = True
    elif not arg.startswith("-"):
        HOST = arg

# ── Test cases ───────────────────────────────────────────────────────────────
# (label, input text, minimum word match ratio)
CASES = [
    # Short texts — historically truncated
    ("1-word",      "Hello",                                                    0.8),
    ("2-word",      "Thank you",                                                0.8),
    ("4-word",      "This is a test",                                           0.8),
    ("question",    "How are you doing today?",                                 0.7),
    ("greeting",    "Good morning, how are you?",                               0.7),

    # Medium texts
    ("1-sentence",  "The quick brown fox jumps over the lazy dog.",             0.7),
    ("2-sentence",  "Welcome to the voice cloning service. This is a test of medium length text generation.", 0.6),
    ("numbers",     "There are 365 days in a year and 24 hours in a day.",     0.5),
    ("punctuation", "Wait, what? No! That can't be right... can it?",          0.5),

    # Long texts — triggers multi-batch chunking
    ("paragraph",
     "Artificial intelligence has transformed the way we interact with technology. "
     "Voice synthesis, in particular, has made remarkable progress in recent years. "
     "Modern systems can clone a voice from just a few seconds of reference audio, "
     "producing speech that is nearly indistinguishable from the original speaker. "
     "This has applications in accessibility, entertainment, and communication.",
     0.5),

    ("long-mixed",
     "On March 15th, 2026, the research team published their findings. "
     "The results were surprising: a 47% improvement over the baseline. "
     "Dr. Smith noted that the approach could be applied to other domains. "
     "Quote: 'This changes everything we thought we knew about the problem.' "
     "The next steps include validation on larger datasets and peer review.",
     0.5),
]

# ── Helpers ──────────────────────────────────────────────────────────────────

def normalize(text: str) -> str:
    """Strip punctuation and normalize for comparison."""
    import re
    text = text.lower().strip()
    text = re.sub(r'[^\w\s]', '', text)       # remove punctuation
    text = re.sub(r'\s+', ' ', text).strip()   # collapse whitespace
    return text


def word_match_ratio(expected: str, actual: str) -> float:
    """Fuzzy word-level match ratio (0.0–1.0) after normalization."""
    a = normalize(expected).split()
    b = normalize(actual).split()
    if not a and not b:
        return 1.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def tts_request(text: str, voice: str = "paul", endpoint: str = "/v1/audio/speech") -> bytes:
    """Generate audio, return raw bytes."""
    r = requests.post(f"{HOST}{endpoint}", json={
        "model": "tts-1", "input": text, "voice": voice,
    }, timeout=120)
    r.raise_for_status()
    return r.content


def stt_request(audio_bytes: bytes) -> str:
    """Transcribe audio bytes, return text."""
    r = requests.post(f"{HOST}/stt",
        files={"audio": ("audio.ogg", io.BytesIO(audio_bytes), "audio/ogg")},
        data={"format": "text"},
        timeout=120,
    )
    r.raise_for_status()
    return r.text.strip()


def roundtrip(text: str) -> tuple[str, float, float]:
    """TTS→STT round trip. Returns (transcription, tts_time, stt_time)."""
    t0 = time.time()
    audio = tts_request(text)
    t1 = time.time()
    transcript = stt_request(audio)
    t2 = time.time()
    return transcript, t1 - t0, t2 - t1


# ── Sequential tests ─────────────────────────────────────────────────────────

def run_sequential():
    print(f"\n{'='*70}")
    print(f" ROUND-TRIP TESTS (TTS → STT)  —  {HOST}")
    print(f"{'='*70}\n")

    # Warm up
    print("Warming up models...", end=" ", flush=True)
    t0 = time.time()
    tts_request("warm up")
    stt_request(tts_request("warm up"))
    print(f"done ({time.time()-t0:.1f}s)\n")

    passed = 0
    failed = 0
    results = []

    for label, text, min_ratio in CASES:
        print(f"  [{label:12s}] ", end="", flush=True)
        try:
            transcript, tts_t, stt_t = roundtrip(text)
            ratio = word_match_ratio(text, transcript)
            ok = ratio >= min_ratio
            status = "PASS" if ok else "FAIL"
            symbol = " OK " if ok else "FAIL"

            print(f"[{symbol}] match={ratio:.0%}  tts={tts_t:.2f}s  stt={stt_t:.2f}s")
            if not ok or ratio < 0.9:
                print(f"{'':16s}  sent: {text[:70]}")
                print(f"{'':16s}  got:  {transcript[:70]}")

            results.append((label, text, transcript, ratio, tts_t, stt_t, ok))
            if ok:
                passed += 1
            else:
                failed += 1

        except Exception as e:
            print(f"[ERR ] {type(e).__name__}: {e}")
            results.append((label, text, "", 0, 0, 0, False))
            failed += 1

    # Summary table
    print(f"\n{'─'*70}")
    print(f"{'Test':<14s} {'Match':>6s}  {'TTS':>6s}  {'STT':>6s}  {'Status'}")
    print(f"{'─'*70}")
    for label, text, transcript, ratio, tts_t, stt_t, ok in results:
        print(f"{label:<14s} {ratio:>5.0%}  {tts_t:>5.2f}s  {stt_t:>5.2f}s  {'PASS' if ok else 'FAIL'}")
    print(f"{'─'*70}")
    print(f"Results: {passed} passed, {failed} failed")
    return failed


# ── Parallel / concurrency tests ─────────────────────────────────────────────

def run_parallel():
    print(f"\n{'='*70}")
    print(f" CONCURRENCY TESTS  —  {HOST}")
    print(f"{'='*70}\n")

    batch_texts = [
        "First concurrent request checking queue behavior.",
        "Second request with different length text.",
        "This is the third request in the batch.",
        "Fourth request is a bit longer to mix up the batch sizes and test stability.",
        "Fifth request to round things out nicely.",
        "Sixth request pushing the concurrency even further with more words in the sentence.",
        "Here comes the seventh request now.",
        "Eighth and final request, testing the queuing under load.",
    ]

    for batch_size in [2, 4, 8]:
        texts = batch_texts[:batch_size]
        print(f"  Batch of {batch_size} concurrent requests...", end=" ", flush=True)

        t0 = time.time()
        results = {}
        errors = []

        with ThreadPoolExecutor(max_workers=batch_size) as pool:
            futures = {pool.submit(roundtrip, t): i for i, t in enumerate(texts)}
            for future in as_completed(futures):
                idx = futures[future]
                try:
                    transcript, tts_t, stt_t = future.result()
                    ratio = word_match_ratio(texts[idx], transcript)
                    results[idx] = (transcript, ratio, tts_t, stt_t)
                except Exception as e:
                    errors.append((idx, e))

        elapsed = time.time() - t0
        all_ok = len(errors) == 0 and all(r[1] >= 0.5 for r in results.values())
        ratios = [r[1] for r in results.values()]
        avg_ratio = sum(ratios) / len(ratios) if ratios else 0

        status = " OK " if all_ok else "FAIL"
        print(f"[{status}] {elapsed:.1f}s total, avg match={avg_ratio:.0%}, {len(errors)} errors")

        if errors:
            for idx, e in errors:
                print(f"    req {idx}: {type(e).__name__}: {e}")

        if not all_ok:
            for idx in sorted(results):
                transcript, ratio, tts_t, stt_t = results[idx]
                if ratio < 0.5:
                    print(f"    req {idx}: match={ratio:.0%}")
                    print(f"      sent: {texts[idx][:60]}")
                    print(f"      got:  {transcript[:60]}")

    print()


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    failures = run_sequential()

    if RUN_PARALLEL:
        run_parallel()

    if failures:
        sys.exit(1)
