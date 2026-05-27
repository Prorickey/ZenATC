FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o zenatc .

# ── Runtime image ────────────────────────────────────────────────────────────

FROM alpine:3.21

# ffmpeg: generates HLS segments on first start via docker-entrypoint.sh
# openssl: generates signing secrets on first start via docker-entrypoint.sh
RUN apk add --no-cache ffmpeg openssl

WORKDIR /app

COPY --from=builder /app/zenatc ./
COPY --from=builder /app/apple_app_attest_root_ca.pem ./
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

VOLUME ["/app/audio"]

EXPOSE 8080

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["./zenatc"]
