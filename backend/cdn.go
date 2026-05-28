package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"time"
)

var cdnConfig struct {
	domain     string
	privateKey ed25519.PrivateKey
}

func initCDN() {
	cdnConfig.domain = os.Getenv("CLOUDFLARE_DOMAIN")
	if cdnConfig.domain == "" {
		cdnConfig.domain = "PLACEHOLDER.example.com"
		log.Println("[cdn] WARNING: CLOUDFLARE_DOMAIN not set — URLs will not resolve")
	}

	seedB64 := os.Getenv("CLOUDFLARE_URL_SIGNING_PRIVATE_KEY")
	if seedB64 == "" {
		log.Println("[cdn] WARNING: CLOUDFLARE_URL_SIGNING_PRIVATE_KEY not set — URL signing will fail at runtime")
		return
	}

	seed, err := base64.StdEncoding.DecodeString(seedB64)
	if err != nil {
		log.Fatalf("[cdn] CLOUDFLARE_URL_SIGNING_PRIVATE_KEY is not valid base64: %v", err)
	}
	if len(seed) != ed25519.SeedSize {
		log.Fatalf("[cdn] CLOUDFLARE_URL_SIGNING_PRIVATE_KEY must decode to %d bytes (an Ed25519 seed), got %d", ed25519.SeedSize, len(seed))
	}
	cdnConfig.privateKey = ed25519.NewKeyFromSeed(seed)

	pub := cdnConfig.privateKey.Public().(ed25519.PublicKey)
	log.Printf("[cdn] URL signing configured (Ed25519), domain: %s", cdnConfig.domain)
	log.Printf("[cdn] public key (give this to the Worker): %s", base64.StdEncoding.EncodeToString(pub))
}

// CDN access is granted by a short-lived signed cookie rather than per-URL query
// signatures, so both the .m3u8 playlist and every .ts segment are protected.
const (
	cdnAccessTTL = 5 * time.Minute
	// cookieName is the access cookie the Worker checks on every /hls/* request.
	cookieName = "zenatc_hls"
	// cookieScope is both the cookie Path and the signed message prefix. One
	// cookie authorizes all streams, so switching tracks reuses it.
	cookieScope = "/hls/"
)

// playlistURL returns the (unsigned) HLS playlist URL for a stream. Access is
// gated by the cookie, not the URL, so it carries no query string.
func playlistURL(streamID string) string {
	u := &url.URL{
		Scheme: "https",
		Host:   cdnConfig.domain,
		Path:   fmt.Sprintf("/hls/%s/index.m3u8", streamID),
	}
	return u.String()
}

// signAccessCookie mints the value for the access cookie: "<expires>.<hexsig>"
// where the signature covers "<cookieScope>:<expires>". The Cloudflare Worker
// verifies it at the edge with the matching public key (it cannot mint cookies),
// then fetches the clean URL with the cookie stripped, so all users still share
// one cached copy of each .ts segment.
func signAccessCookie(expires int64) (string, error) {
	if cdnConfig.privateKey == nil {
		return "", errors.New("CDN signing key not configured")
	}
	message := fmt.Sprintf("%s:%d", cookieScope, expires)
	sig := ed25519.Sign(cdnConfig.privateKey, []byte(message))
	return fmt.Sprintf("%d.%s", expires, hex.EncodeToString(sig)), nil
}
