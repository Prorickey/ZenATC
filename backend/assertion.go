package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"

	"github.com/fxamacker/cbor/v2"
	"github.com/gin-gonic/gin"
)

var errKeyNotFound = errors.New("key not found")

// storeKey extracts the COSE public key from the attestation authData and stores it.
// The COSE key (not the credential certificate's key) is what Apple uses for assertion signing.
func storeKey(keyID string, certPub *ecdsa.PublicKey, initialAuthData []byte) error {
	var initialCounter uint32
	if len(initialAuthData) >= 37 {
		initialCounter = binary.BigEndian.Uint32(initialAuthData[33:37])
	}

	// Extract the COSE public key from authData.
	// Layout: rpIdHash(32) | flags(1) | counter(4) | AAGUID(16) | credIdLen(2) | credId(N) | COSEKey(...)
	pub := certPub
	if len(initialAuthData) >= 55 {
		credIDLen := int(initialAuthData[53])<<8 | int(initialAuthData[54])
		coseOffset := 55 + credIDLen
		if coseOffset < len(initialAuthData) {
			if cosePub, err := parseCOSEKey(initialAuthData[coseOffset:]); err == nil {
				pub = cosePub
				log.Printf("[attest] using COSE public key from authData")
			} else {
				log.Printf("[attest] COSE key parse failed, using cert key: %v", err)
			}
		}
	}

	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return fmt.Errorf("failed to marshal public key for %q: %w", keyID, err)
	}

	// Upsert: a fresh attestation for an existing key replaces the stored key
	// and resets the counter to the attestation's initial value.
	if _, err := db.Exec(`
		INSERT INTO attested_keys (key_id, public_key, counter)
		VALUES (?, ?, ?)
		ON CONFLICT(key_id) DO UPDATE SET
			public_key = excluded.public_key,
			counter    = excluded.counter`,
		keyID, pubDER, int64(initialCounter)); err != nil {
		return fmt.Errorf("failed to store key %q: %w", keyID, err)
	}

	log.Printf("[attest] registered key %q (counter=%d)", keyID, initialCounter)
	return nil
}

func parseCOSEKey(data []byte) (*ecdsa.PublicKey, error) {
	var rawMap map[int]interface{}
	if err := cbor.Unmarshal(data, &rawMap); err != nil {
		return nil, fmt.Errorf("CBOR unmarshal: %w", err)
	}

	xRaw, ok := rawMap[-2]
	if !ok {
		return nil, fmt.Errorf("COSE key missing x (-2)")
	}
	yRaw, ok := rawMap[-3]
	if !ok {
		return nil, fmt.Errorf("COSE key missing y (-3)")
	}

	xBytes, ok := xRaw.([]byte)
	if !ok {
		return nil, fmt.Errorf("COSE key x is not []byte: %T", xRaw)
	}
	yBytes, ok := yRaw.([]byte)
	if !ok {
		return nil, fmt.Errorf("COSE key y is not []byte: %T", yRaw)
	}

	x := new(big.Int).SetBytes(xBytes)
	y := new(big.Int).SetBytes(yBytes)
	return &ecdsa.PublicKey{
		Curve: elliptic.P256(),
		X:     x,
		Y:     y,
	}, nil
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

	if err := storeKey(req.KeyID, pub, authData); err != nil {
		log.Printf("[attest] failed to persist key %q: %v", req.KeyID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register key"})
		return
	}
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

	// Run the read-check-write inside a transaction so two concurrent requests
	// cannot both pass the strictly-increasing counter check and replay an assertion.
	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // rollback after Commit is a no-op

	var pubDER []byte
	var storedCounter int64
	switch err := tx.QueryRow(
		`SELECT public_key, counter FROM attested_keys WHERE key_id = ?`,
		keyID,
	).Scan(&pubDER, &storedCounter); err {
	case nil:
		// found
	case sql.ErrNoRows:
		return errKeyNotFound
	default:
		return fmt.Errorf("failed to load key %q: %w", keyID, err)
	}

	parsedPub, err := x509.ParsePKIXPublicKey(pubDER)
	if err != nil {
		return fmt.Errorf("failed to parse stored public key for %q: %w", keyID, err)
	}
	publicKey, ok := parsedPub.(*ecdsa.PublicKey)
	if !ok {
		return fmt.Errorf("stored key %q is not an EC public key", keyID)
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
	if int64(counter) <= storedCounter {
		return errors.New("counter not incremented — possible replay attack")
	}

	// Verify ECDSA signature.
	// Apple uses double SHA256: nonce = SHA256(SHA256(authenticatorData || clientDataHash))
	clientDataHash := sha256.Sum256([]byte(challenge))
	composite := make([]byte, 0, len(assertion.AuthenticatorData)+sha256.Size)
	composite = append(composite, assertion.AuthenticatorData...)
	composite = append(composite, clientDataHash[:]...)
	inner := sha256.Sum256(composite)
	nonce := sha256.Sum256(inner[:])

	if !ecdsa.VerifyASN1(publicKey, nonce[:], assertion.Signature) {
		return errors.New("assertion signature invalid")
	}

	// Persist the new counter only after all checks pass. The WHERE clause guards
	// against a concurrent update slipping in between the SELECT and UPDATE.
	res, err := tx.Exec(
		`UPDATE attested_keys SET counter = ? WHERE key_id = ? AND counter = ?`,
		int64(counter), keyID, storedCounter,
	)
	if err != nil {
		return fmt.Errorf("failed to update counter for %q: %w", keyID, err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to read update result for %q: %w", keyID, err)
	}
	if affected == 0 {
		return errors.New("counter update raced — possible replay attack")
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit counter update for %q: %w", keyID, err)
	}
	return nil
}
