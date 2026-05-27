#!/bin/bash
set -e

docker build -t zenatc-backend .
docker run --rm -p 8080:8080 zenatc-backend
