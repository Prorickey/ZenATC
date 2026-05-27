package main

import (
	"crypto/hmac"
	"crypto/sha256"
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
	domain        string
	signingSecret []byte
}

func initCDN() {
	cdnConfig.domain = os.Getenv("CLOUDFLARE_DOMAIN")
	if cdnConfig.domain == "" {
		cdnConfig.domain = "PLACEHOLDER.example.com"
		log.Println("[cdn] WARNING: CLOUDFLARE_DOMAIN not set — URLs will not resolve")
	}

	secretB64 := os.Getenv("CLOUDFLARE_URL_SIGNING_SECRET")
	if secretB64 == "" {
		log.Println("[cdn] WARNING: CLOUDFLARE_URL_SIGNING_SECRET not set — URL signing will fail at runtime")
		return
	}

	secret, err := base64.StdEncoding.DecodeString(secretB64)
	if err != nil {
		log.Fatalf("[cdn] CLOUDFLARE_URL_SIGNING_SECRET is not valid base64: %v", err)
	}
	if len(secret) < 32 {
		log.Fatal("[cdn] CLOUDFLARE_URL_SIGNING_SECRET must decode to at least 32 bytes")
	}
	cdnConfig.signingSecret = secret
	log.Printf("[cdn] URL signing configured, domain: %s", cdnConfig.domain)
}

// signedStreamURL returns a short-lived Cloudflare-compatible signed URL for
// the HLS playlist of the given stream ID.
//
// Signature format: hex( HMAC-SHA256(secret, "<path>:<expires>") )
// The Cloudflare Worker validates this same signature at the edge and strips
// the query params before forwarding to cache, so all users share one cached
// copy of each .ts segment despite having different signed playlist URLs.
func signedStreamURL(streamID string, ttl time.Duration) (string, error) {
	if cdnConfig.signingSecret == nil {
		return "", errors.New("CDN signing secret not configured")
	}
	path := fmt.Sprintf("/hls/%s/index.m3u8", streamID)
	expires := time.Now().Add(ttl).Unix()

	u := &url.URL{
		Scheme:   "https",
		Host:     cdnConfig.domain,
		Path:     path,
		RawQuery: fmt.Sprintf("expires=%d&signature=%s", expires, computeHMACToken(path, expires)),
	}
	return u.String(), nil
}

func computeHMACToken(path string, expires int64) string {
	mac := hmac.New(sha256.New, cdnConfig.signingSecret)
	mac.Write([]byte(fmt.Sprintf("%s:%d", path, expires)))
	return hex.EncodeToString(mac.Sum(nil))
}

