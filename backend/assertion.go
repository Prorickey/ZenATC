package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

var errKeyNotFound = errors.New("key not found")

// parseP256PublicKey reconstructs an ECDSA P-256 public key from the 64-byte
// uncompressed X||Y form produced by CryptoKit's publicKey.rawRepresentation.
func parseP256PublicKey(raw []byte) (*ecdsa.PublicKey, error) {
	if len(raw) != 64 {
		return nil, fmt.Errorf("expected 64-byte P-256 public key, got %d", len(raw))
	}
	x := new(big.Int).SetBytes(raw[:32])
	y := new(big.Int).SetBytes(raw[32:])
	if !elliptic.P256().IsOnCurve(x, y) {
		return nil, errors.New("public key point is not on the P-256 curve")
	}
	return &ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, nil
}

// storeSigningKey upserts the app-generated signing key's raw public bytes under
// the App Attest key ID. A fresh attestation for an existing ID replaces the key.
func storeSigningKey(keyID string, publicKey []byte) error {
	if _, err := db.Exec(`
		INSERT INTO attested_keys (key_id, public_key)
		VALUES (?, ?)
		ON CONFLICT(key_id) DO UPDATE SET public_key = excluded.public_key`,
		keyID, publicKey); err != nil {
		return fmt.Errorf("failed to store signing key %q: %w", keyID, err)
	}
	log.Printf("[attest] registered signing key %q", keyID)
	return nil
}

// ── /attest-key ──────────────────────────────────────────────────────────────

type attestKeyRequest struct {
	ChallengeToken    string `json:"challenge_token"    binding:"required"`
	KeyID             string `json:"key_id"             binding:"required"`
	AttestationObject string `json:"attestation_object" binding:"required"`
	PublicKey         string `json:"public_key"         binding:"required"`
}

// attestKeyHandler validates a full Apple attestation whose clientDataHash binds
// the supplied app-generated signing key, then stores that signing key. Every
// later request is authenticated with the signing key via /assert-and-stream, so
// this one-time attestation is the only flow that contacts Apple.
//
// POST /attest-key
// Body: { "challenge_token", "key_id", "attestation_object" (b64), "public_key" (b64, 64-byte P-256 X||Y) }
// Response 200: {}
func attestKeyHandler(c *gin.Context) {
	var req attestKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing challenge_token, key_id, attestation_object, or public_key"})
		return
	}

	attestationBytes, err := base64.StdEncoding.DecodeString(req.AttestationObject)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "attestation_object must be standard base64"})
		return
	}

	publicKey, err := base64.StdEncoding.DecodeString(req.PublicKey)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "public_key must be standard base64"})
		return
	}
	if _, err := parseP256PublicKey(publicKey); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "public_key is not a valid P-256 key"})
		return
	}

	if err := verifyAttestation(req.ChallengeToken, attestationBytes, publicKey); err != nil {
		log.Printf("[attest] key registration failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "attestation verification failed"})
		return
	}

	if err := storeSigningKey(req.KeyID, publicKey); err != nil {
		log.Printf("[attest] failed to persist key %q: %v", req.KeyID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register key"})
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}

// ── /assert-and-stream ───────────────────────────────────────────────────────

type assertRequest struct {
	ChallengeToken string `json:"challenge_token" binding:"required"`
	KeyID          string `json:"key_id"          binding:"required"`
	Signature      string `json:"signature"       binding:"required"`
	StreamID       string `json:"stream_id"       binding:"required"`
}

// assertAndStreamHandler verifies an ECDSA signature produced by the registered
// signing key over (stream_id || challenge), then sets a short-lived signed
// access cookie and returns the (unsigned) playlist URL. The cookie gates both
// the .m3u8 and every .ts at the edge. There is no Apple contact and no replay
// counter — replay is bounded by the short challenge token TTL, and the cookie's
// own short TTL is refreshed by the client during playback.
//
// POST /assert-and-stream
// Body: { "challenge_token", "key_id", "signature" (b64 DER), "stream_id" }
// Response 200: Set-Cookie: zenatc_hls=...; { "stream_url": "..." }
// Response 404: { "error": "key_not_found" }  — re-attest via /attest-key, then retry
func assertAndStreamHandler(c *gin.Context) {
	var req assertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing required fields"})
		return
	}

	if !validStreamID.MatchString(req.StreamID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream_id"})
		return
	}

	signature, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "signature must be standard base64"})
		return
	}

	if err := verifySignature(req.ChallengeToken, req.KeyID, req.StreamID, signature); err != nil {
		if errors.Is(err, errKeyNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "key_not_found"})
			return
		}
		log.Printf("[assert] verification failed for key %q: %v", req.KeyID, err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "assertion verification failed"})
		return
	}

	expires := time.Now().Add(cdnAccessTTL).Unix()
	cookie, err := signAccessCookie(expires)
	if err != nil {
		log.Printf("[cdn] failed to mint access cookie: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to grant stream access"})
		return
	}

	// Secure + HttpOnly: the cookie is sent by CFNetwork/AVPlayer but never
	// exposed to scripts. SameSite=None so media subrequests always carry it.
	c.SetSameSite(http.SameSiteNoneMode)
	c.SetCookie(cookieName, cookie, int(cdnAccessTTL.Seconds()), cookieScope, cdnConfig.domain, true, true)

	c.JSON(http.StatusOK, gin.H{"stream_url": playlistURL(req.StreamID)})
}

// verifySignature checks an ECDSA P-256 signature from the registered signing key
// over the message (stream_id || challenge). The challenge is extracted from the
// signed JWT, so the raw challenge never travels in the request body. CryptoKit's
// P256.Signing signs SHA256(message), so we verify against that single digest.
func verifySignature(challengeToken, keyID, streamID string, signature []byte) error {
	challenge, err := verifyAndExtractChallenge(challengeToken)
	if err != nil {
		return fmt.Errorf("challenge token invalid: %w", err)
	}

	var pubRaw []byte
	switch err := db.QueryRow(
		`SELECT public_key FROM attested_keys WHERE key_id = ?`, keyID,
	).Scan(&pubRaw); err {
	case nil:
		// found
	case sql.ErrNoRows:
		return errKeyNotFound
	default:
		return fmt.Errorf("failed to load key %q: %w", keyID, err)
	}

	publicKey, err := parseP256PublicKey(pubRaw)
	if err != nil {
		return fmt.Errorf("stored key %q invalid: %w", keyID, err)
	}

	message := make([]byte, 0, len(streamID)+len(challenge))
	message = append(message, []byte(streamID)...)
	message = append(message, []byte(challenge)...)
	digest := sha256.Sum256(message)

	if !ecdsa.VerifyASN1(publicKey, digest[:], signature) {
		return errors.New("signature invalid")
	}
	return nil
}
