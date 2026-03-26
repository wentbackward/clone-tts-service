#!/bin/bash
# Start the Clone Voice Service
set -e
cd "$(dirname "$0")"

# Use BUILD=1 to force local build instead of pulling prebuilt images
BUILD_FLAG=""
if [ "${BUILD:-0}" = "1" ]; then
    BUILD_FLAG="--build"
    echo "Building locally..."
fi

# Detect GPU availability
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    echo "GPU detected — starting with CUDA support"
    docker compose up -d $BUILD_FLAG
else
    echo "No GPU detected — starting in CPU mode"
    echo "Tip: set device: \"cpu\" in config.yaml and use a smaller whisper model (tiny/base)"
    docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d $BUILD_FLAG
fi

echo ""
echo "Waiting for health check..."

for i in $(seq 1 90); do
    if curl -s http://localhost:${VOICE_PORT:-3030}/health | grep -q '"ok"' 2>/dev/null; then
        echo "Service is ready!"
        echo ""
        echo "  Health:    http://localhost:${VOICE_PORT:-3030}/health"
        echo "  Voices:    http://localhost:${VOICE_PORT:-3030}/voices"
        echo "  TTS:       POST http://localhost:${VOICE_PORT:-3030}/tts"
        echo "  STT:       POST http://localhost:${VOICE_PORT:-3030}/stt"
        echo ""
        echo "First TTS/STT request will be slow (~30s) as models load."
        echo "Subsequent requests are sub-second."
        exit 0
    fi
    sleep 2
done

echo "Service did not start in time. Check logs:"
echo "  docker compose logs -f"
exit 1
