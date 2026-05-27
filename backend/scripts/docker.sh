#!/bin/bash
set -e

cd "$(dirname "$0")/.."

IMAGE="docker.bedson.tech/tbedson/zenatc-backend"

case "${1:-}" in
    run)
        docker build -t zenatc-backend .
        mkdir -p ./audio
        docker run --rm -p 3303:8080 -v "$(pwd)/audio:/app/audio" --env-file .env zenatc-backend
        ;;
    deploy)
        docker build -t "$IMAGE" .
        docker push "$IMAGE"
        echo "Pushed $IMAGE"
        ;;
    *)
        echo "Usage: $0 {run|deploy}"
        exit 1
        ;;
esac
