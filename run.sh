#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker stop clone-voice 2>/dev/null
docker rm clone-voice 2>/dev/null

docker run --rm -d --runtime nvidia --gpus all \
  --name clone-voice --network host \
  -v "$SCRIPT_DIR/voices:/app/voices" \
  -v "$SCRIPT_DIR/config.yaml:/app/config.yaml" \
  -v hf-cache:/root/.cache/huggingface \
  -v whisper-cache:/root/.cache/whisper \
  clone-voice:spark

echo "clone-voice started on port 3030"
