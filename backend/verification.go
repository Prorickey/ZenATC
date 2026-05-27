package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"time"

	"github.com/fxamacker/cbor/v2"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

//go:embed apple_app_attest_root_ca.pem
var appleRootCAPEM []byte

var (
	appleRootCAPool *x509.CertPool
	appleAppID      string
)

// Production AAGUID: ASCII "appattest" + 7 null bytes
var aaguidProduction = [16]byte{
	0x61, 0x70, 0x70, 0x61, 0x74, 0x74, 0x65, 0x73,
	0x74, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
}

// Development AAGUID: ASCII "appattestdevelop"
var aaguidDevelopment = [16]byte{
	0x61, 0x70, 0x70, 0x61, 0x74, 0x74, 0x65, 0x73,
	0x74, 0x64, 0x65, 0x76, 0x65, 0x6c, 0x6f, 0x70,
}

// OID for the Apple App Attest nonce extension in the credential certificate.
var oidAppleAttestation = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}

func initVerification() {
	pool := x509.NewCertPool()
	log.Printf("[attest] embedded Apple Root CA size: %d bytes", len(appleRootCAPEM))
	if !pool.AppendCertsFromPEM(appleRootCAPEM) {
		log.Fatal("[attest] failed to parse Apple App Attestation Root CA certificate")
	}
	appleRootCAPool = pool

	// Allow override for multi-tenant or staging builds; default to this app.
	appID := os.Getenv("APPLE_APP_ID")
	if appID == "" {
		appID = "PS96HNX5KD.tech.bedson.lofiatc"
	}
	appleAppID = appID
	log.Printf("[attest] App ID: %s", appleAppID)
}

// streamURLTTL is how long a signed CDN URL remains valid.
const streamURLTTL = 3 * time.Minute

// validStreamID rejects path traversal and enforces a known-safe character set.
var validStreamID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`)

// MARK: - Request / Response

type verifyRequest struct {
	ChallengeToken    string `json:"challenge_token"    binding:"required"`
	AttestationObject string `json:"attestation_object" binding:"required"` // base64-encoded CBOR
	StreamID          string `json:"stream_id"          binding:"required"` // e.g. "lofi_late_night"
}

// MARK: - Handler

// verifyAndStreamHandler is the combined Phase 3 + 4 entry point.
// It validates the stateless challenge token and the Apple attestation object,
// then returns a short-lived signed CDN URL for the requested stream.
//
// POST /verify-and-stream
// Body: { "challenge_token": "...", "attestation_object": "<base64>", "stream_id": "lofi_late_night" }
// Response 200: { "stream_url": "https://….cloudfront.net/…?Expires=…&Signature=…&Key-Pair-Id=…" }
func verifyAndStreamHandler(c *gin.Context) {
	var req verifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing challenge_token, attestation_object, or stream_id"})
		return
	}

	if !validStreamID.MatchString(req.StreamID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream_id"})
		return
	}

	attestationBytes, err := base64.StdEncoding.DecodeString(req.AttestationObject)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "attestation_object must be standard base64"})
		return
	}

	if _, _, err := verifyAttestation(req.ChallengeToken, attestationBytes); err != nil {
		log.Printf("[attest] verification failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "attestation verification failed"})
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

// MARK: - Orchestration

// verifyAttestation runs all Phase 3 checks and returns the EC public key from
// the credential certificate and the raw authenticatorData.
// Both values are needed by attestKeyHandler to register the key for future assertions.
func verifyAttestation(challengeToken string, attestationBytes []byte) (*ecdsa.PublicKey, []byte, error) {
	// ── Step 1: Verify the stateless challenge token ──────────────────────────
	challenge, err := verifyAndExtractChallenge(challengeToken)
	if err != nil {
		return nil, nil, fmt.Errorf("challenge token invalid: %w", err)
	}

	// ── Step 2: CBOR-decode the Apple attestation object ─────────────────────
	var attest attestationObject
	if err := cbor.Unmarshal(attestationBytes, &attest); err != nil {
		return nil, nil, fmt.Errorf("CBOR decode failed: %w", err)
	}
	if attest.Format != "apple-appattest" {
		return nil, nil, fmt.Errorf("unexpected attestation format %q", attest.Format)
	}
	if len(attest.AttStmt.X5C) < 2 {
		return nil, nil, errors.New("x5c must contain at least 2 certificates")
	}

	// ── Step 3: Parse the certificate chain ──────────────────────────────────
	credCert, err := x509.ParseCertificate(attest.AttStmt.X5C[0])
	if err != nil {
		return nil, nil, fmt.Errorf("failed to parse credential certificate: %w", err)
	}
	intermediateCert, err := x509.ParseCertificate(attest.AttStmt.X5C[1])
	if err != nil {
		return nil, nil, fmt.Errorf("failed to parse intermediate certificate: %w", err)
	}

	// ── Step 4: Verify the chain against Apple's root CA ─────────────────────
	if err := verifyCertChain(credCert, intermediateCert); err != nil {
		return nil, nil, fmt.Errorf("certificate chain invalid: %w", err)
	}

	// ── Step 5: Verify the nonce embedded in the credential certificate ───────
	// nonce = SHA256(authData || SHA256(challenge))
	clientDataHash := sha256.Sum256([]byte(challenge))
	composite := make([]byte, 0, len(attest.AuthData)+sha256.Size)
	composite = append(composite, attest.AuthData...)
	composite = append(composite, clientDataHash[:]...)
	expectedNonce := sha256.Sum256(composite)
	if err := verifyCertNonce(credCert, expectedNonce[:]); err != nil {
		return nil, nil, fmt.Errorf("challenge integrity check failed: %w", err)
	}

	// ── Step 6: Verify the RP ID matches our App ID ───────────────────────────
	if err := verifyRPIDHash(attest.AuthData); err != nil {
		return nil, nil, fmt.Errorf("app identity check failed: %w", err)
	}

	// ── Step 7: Verify the AAGUID identifies a genuine App Attest device ──────
	if err := verifyAAGUID(attest.AuthData); err != nil {
		return nil, nil, fmt.Errorf("device identity check failed: %w", err)
	}

	// ── Step 8: Verify credential ID equals the public key hash ───────────────
	if err := verifyCredentialID(credCert, attest.AuthData); err != nil {
		return nil, nil, fmt.Errorf("credential ID mismatch: %w", err)
	}

	ecPub, ok := credCert.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, nil, errors.New("credential certificate does not use an EC public key")
	}
	return ecPub, attest.AuthData, nil
}

// MARK: - CBOR structures

type attestationObject struct {
	Format   string               `cbor:"fmt"`
	AttStmt  attestationStatement `cbor:"attStmt"`
	AuthData []byte               `cbor:"authData"`
}

type attestationStatement struct {
	X5C     [][]byte `cbor:"x5c"`
	Receipt []byte   `cbor:"receipt"`
}

// MARK: - Step 1: JWT challenge verification

func verifyAndExtractChallenge(tokenString string) (string, error) {
	token, err := jwt.ParseWithClaims(
		tokenString,
		&challengeClaims{},
		func(t *jwt.Token) (any, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return challengeSigningKey, nil
		},
	)
	if err != nil {
		return "", err
	}
	claims, ok := token.Claims.(*challengeClaims)
	if !ok || !token.Valid {
		return "", errors.New("invalid token claims")
	}
	if claims.Challenge == "" {
		return "", errors.New("token missing challenge claim")
	}
	return claims.Challenge, nil
}

// MARK: - Step 4: Certificate chain

func verifyCertChain(credCert, intermediateCert *x509.Certificate) error {
	intermediates := x509.NewCertPool()
	intermediates.AddCert(intermediateCert)

	_, err := credCert.Verify(x509.VerifyOptions{
		Roots:         appleRootCAPool,
		Intermediates: intermediates,
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	})
	return err
}

// MARK: - Step 5: Nonce / challenge integrity

// The credential certificate carries the expected nonce in a proprietary Apple
// extension (OID 1.2.840.113635.100.8.2). The DER structure is:
//
//	SEQUENCE {
//	  [1] EXPLICIT {
//	    OCTET STRING <32-byte SHA-256 nonce>
//	  }
//	}
func verifyCertNonce(cert *x509.Certificate, expectedNonce []byte) error {
	for _, ext := range cert.Extensions {
		if !ext.Id.Equal(oidAppleAttestation) {
			continue
		}
		// Outer SEQUENCE containing one context-specific tagged element.
		var outer []asn1.RawValue
		if _, err := asn1.Unmarshal(ext.Value, &outer); err != nil {
			return fmt.Errorf("failed to parse nonce extension outer sequence: %w", err)
		}
		if len(outer) == 0 {
			return errors.New("nonce extension sequence is empty")
		}
		// The first (and only) element is [1] EXPLICIT wrapping an OCTET STRING.
		var octetString asn1.RawValue
		if _, err := asn1.Unmarshal(outer[0].FullBytes, &octetString); err != nil {
			return fmt.Errorf("failed to parse nonce extension tagged element: %w", err)
		}
		// Extract the inner OCTET STRING from the context-specific wrapper.
		var nonce []byte
		if _, err := asn1.Unmarshal(octetString.Bytes, &nonce); err != nil {
			return fmt.Errorf("failed to parse nonce octet string: %w", err)
		}
		if !bytes.Equal(nonce, expectedNonce) {
			return errors.New("certificate nonce does not match computed value")
		}
		return nil
	}
	return errors.New("credential certificate is missing the App Attest nonce extension")
}

// MARK: - Step 6: RP ID (App ID)

// authData[0:32] is the SHA-256 of the App ID string "<TeamID>.<BundleID>".
func verifyRPIDHash(authData []byte) error {
	if len(authData) < 32 {
		return errors.New("authData too short")
	}
	expected := sha256.Sum256([]byte(appleAppID))
	if !bytes.Equal(authData[:32], expected[:]) {
		log.Printf("[attest] rpIdHash mismatch: expected SHA256(%q) = %x, got %x", appleAppID, expected[:], authData[:32])
		return errors.New("rpIdHash does not match App ID")
	}
	return nil
}

// MARK: - Step 7: AAGUID

// authData[37:53] is a 16-byte AAGUID identifying the authenticator type.
func verifyAAGUID(authData []byte) error {
	if len(authData) < 53 {
		return errors.New("authData too short to contain AAGUID")
	}
	var aaguid [16]byte
	copy(aaguid[:], authData[37:53])
	if aaguid != aaguidProduction && aaguid != aaguidDevelopment {
		return errors.New("AAGUID does not identify an Apple App Attest device")
	}
	return nil
}

// MARK: - Step 8: Credential ID

// authData[53:55] is the credential ID length (big-endian uint16).
// authData[55:55+len] is the credential ID, which Apple defines as the
// SHA-256 hash of the public key in the credential certificate.
func verifyCredentialID(credCert *x509.Certificate, authData []byte) error {
	if len(authData) < 55 {
		return errors.New("authData too short to read credential ID length")
	}
	credIDLen := int(authData[53])<<8 | int(authData[54])
	if len(authData) < 55+credIDLen {
		return fmt.Errorf("authData too short for credential ID of length %d", credIDLen)
	}
	credID := authData[55 : 55+credIDLen]

	ecPub, ok := credCert.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return errors.New("credential certificate does not contain an EC public key")
	}
	rawKey := elliptic.Marshal(ecPub.Curve, ecPub.X, ecPub.Y)
	pubKeyHash := sha256.Sum256(rawKey)
	if !bytes.Equal(credID, pubKeyHash[:]) {
		return errors.New("credential ID does not match public key hash")
	}
	return nil
}
