package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"net/http"
	"sync"

	"github.com/fxamacker/cbor/v2"
	"github.com/gin-gonic/gin"
)

var errKeyNotFound = errors.New("key not found")

// attestedKey holds the public key and current assertion counter for a registered device.
type attestedKey struct {
	publicKey *ecdsa.PublicKey
	counter   uint32
}

var (
	keyStore   = make(map[string]*attestedKey)
	keyStoreMu sync.Mutex
)

// storeKey saves a verified public key so future assertions can be verified without
// contacting Apple's servers. initialAuthData is the authenticatorData from the
// attestation CBOR; bytes 33–36 carry the initial counter (0 for a fresh key).
func storeKey(keyID string, pub *ecdsa.PublicKey, initialAuthData []byte) {
	var initialCounter uint32
	if len(initialAuthData) >= 37 {
		initialCounter = binary.BigEndian.Uint32(initialAuthData[33:37])
	}
	keyStoreMu.Lock()
	defer keyStoreMu.Unlock()
	keyStore[keyID] = &attestedKey{publicKey: pub, counter: initialCounter}
	log.Printf("[attest] registered key %q (counter=%d)", keyID, initialCounter)
}

// ── /attest-key ──────────────────────────────────────────────────────────────

type attestKeyRequest struct {
	ChallengeToken    string `json:"challenge_token"    binding:"required"`
	KeyID             string `json:"key_id"             binding:"required"`
	AttestationObject string `json:"attestation_object" binding:"required"`
}

// attestKeyHandler validates a full Apple attestation and stores the public key.
// Does not return a stream URL — use /assert-and-stream for that.
//
// POST /attest-key
// Body: { "challenge_token": "...", "key_id": "...", "attestation_object": "<base64>" }
// Response 200: {}
func attestKeyHandler(c *gin.Context) {
	var req attestKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing challenge_token, key_id, or attestation_object"})
		return
	}

	attestationBytes, err := base64.StdEncoding.DecodeString(req.AttestationObject)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "attestation_object must be standard base64"})
		return
	}

	pub, authData, err := verifyAttestation(req.ChallengeToken, attestationBytes)
	if err != nil {
		log.Printf("[attest] key registration failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "attestation verification failed"})
		return
	}

	storeKey(req.KeyID, pub, authData)
	c.JSON(http.StatusOK, gin.H{})
}

// ── /assert-and-stream ───────────────────────────────────────────────────────

type assertRequest struct {
	ChallengeToken  string `json:"challenge_token"  binding:"required"`
	KeyID           string `json:"key_id"           binding:"required"`
	AssertionObject string `json:"assertion_object" binding:"required"`
	StreamID        string `json:"stream_id"        binding:"required"`
}

type assertionCBOR struct {
	Signature         []byte `cbor:"signature"`
	AuthenticatorData []byte `cbor:"authenticatorData"`
}

// assertAndStreamHandler verifies an App Attest assertion and returns a short-lived
// signed CDN URL. No Apple server contact is needed — verification uses the stored key.
//
// POST /assert-and-stream
// Body: { "challenge_token": "...", "key_id": "...", "assertion_object": "<base64>", "stream_id": "..." }
// Response 200: { "stream_url": "..." }
// Response 404: { "error": "key_not_found" }  — call /attest-key first, then retry
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

	assertionBytes, err := base64.StdEncoding.DecodeString(req.AssertionObject)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "assertion_object must be standard base64"})
		return
	}

	if err := verifyAssertion(req.ChallengeToken, req.KeyID, assertionBytes); err != nil {
		if errors.Is(err, errKeyNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "key_not_found"})
			return
		}
		log.Printf("[assert] verification failed for key %q: %v", req.KeyID, err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "assertion verification failed"})
		return
	}

	streamURL, err := signedStreamURL(req.StreamID, streamURLTTL)
	if err != nil {
		log.Printf("[cdn] failed to sign URL for %q: %v", req.StreamID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate stream URL"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"stream_url": streamURL})
}

// verifyAssertion validates an App Attest assertion object against the stored public key.
//
// The iOS client calls generateAssertion(keyID, clientDataHash: SHA256(challenge))
// where challenge is the raw string extracted from the JWT. The backend reconstructs
// clientDataHash the same way, so the iOS never needs to send the raw challenge.
func verifyAssertion(challengeToken, keyID string, assertionBytes []byte) error {
	challenge, err := verifyAndExtractChallenge(challengeToken)
	if err != nil {
		return fmt.Errorf("challenge token invalid: %w", err)
	}

	keyStoreMu.Lock()
	defer keyStoreMu.Unlock()

	stored := keyStore[keyID]
	if stored == nil {
		return errKeyNotFound
	}

	var assertion assertionCBOR
	if err := cbor.Unmarshal(assertionBytes, &assertion); err != nil {
		return fmt.Errorf("CBOR decode failed: %w", err)
	}

	if len(assertion.AuthenticatorData) < 37 {
		return errors.New("authenticatorData too short")
	}

	// Verify rpIdHash (bytes 0–31).
	expectedRPIDHash := sha256.Sum256([]byte(appleAppID))
	if !bytes.Equal(assertion.AuthenticatorData[:32], expectedRPIDHash[:]) {
		return errors.New("rpIdHash mismatch")
	}

	// Verify counter is strictly increasing (bytes 33–36, big-endian).
	// Prevents replay attacks: an intercepted assertion cannot be reused.
	counter := binary.BigEndian.Uint32(assertion.AuthenticatorData[33:37])
	if counter <= stored.counter {
		return errors.New("counter not incremented — possible replay attack")
	}

	// Verify ECDSA signature.
	// nonce = SHA256(authenticatorData || SHA256(challenge))
	clientDataHash := sha256.Sum256([]byte(challenge))
	composite := make([]byte, 0, len(assertion.AuthenticatorData)+sha256.Size)
	composite = append(composite, assertion.AuthenticatorData...)
	composite = append(composite, clientDataHash[:]...)
	nonce := sha256.Sum256(composite)

	if !ecdsa.VerifyASN1(stored.publicKey, nonce[:], assertion.Signature) {
		return errors.New("assertion signature invalid")
	}

	// Update stored counter only after all checks pass.
	stored.counter = counter
	return nil
}
