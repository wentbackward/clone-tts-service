#!/bin/bash
# Test all endpoints of the Clone Voice Service
set -e

HOST="${1:-http://localhost:3030}"
PASS=0
FAIL=0

echo "Testing Clone Voice Service at $HOST"
echo "======================================"

# Health
echo -n "GET  /health ... "
HEALTH=$(curl -s -w "\n%{http_code}" "$HOST/health")
CODE=$(echo "$HEALTH" | tail -1)
BODY=$(echo "$HEALTH" | head -1)
if [ "$CODE" = "200" ]; then
    echo "OK ($BODY)"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $CODE)"
    FAIL=$((FAIL+1))
fi

# Voices
echo -n "GET  /voices ... "
VOICES=$(curl -s -w "\n%{http_code}" "$HOST/voices")
CODE=$(echo "$VOICES" | tail -1)
BODY=$(echo "$VOICES" | head -1)
if [ "$CODE" = "200" ]; then
    COUNT=$(echo "$BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    echo "OK ($COUNT voices)"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $CODE)"
    FAIL=$((FAIL+1))
fi

# TTS — ogg
echo -n "POST /tts (ogg, fast) ... "
TTS_START=$(date +%s%3N)
TTS_CODE=$(curl -s -o /tmp/test_tts.ogg -w "%{http_code}" -X POST "$HOST/tts" \
    -H 'Content-Type: application/json' \
    -d '{"text": "Hello, this is a test of the text to speech service.", "voice": "paul", "quality": "fast", "format": "ogg"}')
TTS_END=$(date +%s%3N)
TTS_MS=$((TTS_END - TTS_START))
if [ "$TTS_CODE" = "200" ]; then
    SIZE=$(wc -c < /tmp/test_tts.ogg)
    echo "OK (${SIZE} bytes, ${TTS_MS}ms)"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $TTS_CODE)"
    FAIL=$((FAIL+1))
fi

# TTS — flac
echo -n "POST /tts (flac, quality) ... "
TTS_CODE=$(curl -s -o /tmp/test_tts.flac -w "%{http_code}" -X POST "$HOST/tts" \
    -H 'Content-Type: application/json' \
    -d '{"text": "Testing flac output.", "voice": "paul", "quality": "quality", "format": "flac"}')
if [ "$TTS_CODE" = "200" ]; then
    SIZE=$(wc -c < /tmp/test_tts.flac)
    echo "OK (${SIZE} bytes)"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $TTS_CODE)"
    FAIL=$((FAIL+1))
fi

# TTS — mp3
echo -n "POST /tts (mp3) ... "
TTS_CODE=$(curl -s -o /tmp/test_tts.mp3 -w "%{http_code}" -X POST "$HOST/tts" \
    -H 'Content-Type: application/json' \
    -d '{"text": "Testing mp3 output.", "voice": "paul", "format": "mp3"}')
if [ "$TTS_CODE" = "200" ]; then
    SIZE=$(wc -c < /tmp/test_tts.mp3)
    echo "OK (${SIZE} bytes)"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $TTS_CODE)"
    FAIL=$((FAIL+1))
fi

# TTS — invalid voice
echo -n "POST /tts (bad voice) ... "
TTS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$HOST/tts" \
    -H 'Content-Type: application/json' \
    -d '{"text": "test", "voice": "nonexistent"}')
if [ "$TTS_CODE" = "404" ]; then
    echo "OK (correctly returned 404)"
    PASS=$((PASS+1))
else
    echo "FAIL (expected 404, got $TTS_CODE)"
    FAIL=$((FAIL+1))
fi

# STT — use the TTS output as input
echo -n "POST /stt (json) ... "
STT_START=$(date +%s%3N)
STT=$(curl -s -w "\n%{http_code}" -X POST "$HOST/stt" \
    -F "audio=@/tmp/test_tts.ogg" \
    -F "format=json")
STT_END=$(date +%s%3N)
STT_MS=$((STT_END - STT_START))
CODE=$(echo "$STT" | tail -1)
BODY=$(echo "$STT" | head -1)
if [ "$CODE" = "200" ]; then
    TEXT=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text','')[:60])" 2>/dev/null || echo "?")
    echo "OK (${STT_MS}ms) \"$TEXT\""
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $CODE)"
    FAIL=$((FAIL+1))
fi

# STT — text format
echo -n "POST /stt (text) ... "
STT_CODE=$(curl -s -o /tmp/test_stt.txt -w "%{http_code}" -X POST "$HOST/stt" \
    -F "audio=@/tmp/test_tts.ogg" \
    -F "format=text")
if [ "$STT_CODE" = "200" ]; then
    TEXT=$(cat /tmp/test_stt.txt | head -c 60)
    echo "OK \"$TEXT\""
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $STT_CODE)"
    FAIL=$((FAIL+1))
fi

# STT — verbose format
echo -n "POST /stt (verbose) ... "
STT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$HOST/stt" \
    -F "audio=@/tmp/test_tts.ogg" \
    -F "format=verbose")
if [ "$STT_CODE" = "200" ]; then
    echo "OK"
    PASS=$((PASS+1))
else
    echo "FAIL (HTTP $STT_CODE)"
    FAIL=$((FAIL+1))
fi

# Summary
echo ""
echo "======================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "All tests passed!" || exit 1
