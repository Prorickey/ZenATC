package main

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// challengeSigningKey is loaded once at startup from the environment.
// It is the HMAC-SHA256 key used to sign and later verify challenge tokens.
var challengeSigningKey []byte

func initChallengeKey() {
	raw := os.Getenv("CHALLENGE_SIGNING_SECRET")
	if raw == "" {
		log.Fatal("CHALLENGE_SIGNING_SECRET env var is not set — refusing to start")
	}
	key, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		log.Fatalf("CHALLENGE_SIGNING_SECRET is not valid base64: %v", err)
	}
	if len(key) < 32 {
		log.Fatal("CHALLENGE_SIGNING_SECRET must decode to at least 32 bytes")
	}
	challengeSigningKey = key
}

type challengeClaims struct {
	Challenge string `json:"challenge"`
	jwt.RegisteredClaims
}

// attestationChallengeHandler issues a short-lived, self-validating challenge
// token. The token is a signed JWT containing a random 32-byte challenge and
// a 5-minute expiry. No server-side state is stored.
//
// GET /attestation-challenge
// Response 200: { "token": "<jwt>" }
func attestationChallengeHandler(c *gin.Context) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate challenge"})
		return
	}
	challenge := base64.URLEncoding.EncodeToString(raw)

	now := time.Now()
	claims := challengeClaims{
		Challenge: challenge,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(5 * time.Minute)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(challengeSigningKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("failed to sign token: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": signed})
}
