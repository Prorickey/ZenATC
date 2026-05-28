// Command genkey generates an Ed25519 keypair for CDN URL signing.
//
// Run from the backend directory:
//
//	go run ./scripts/genkey
//
// Put PRIVATE_KEY in the backend's CLOUDFLARE_URL_SIGNING_PRIVATE_KEY env var
// and PUBLIC_KEY in the Worker's CLOUDFLARE_URL_SIGNING_PUBLIC_KEY var.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log"
)

func main() {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Fatalf("failed to generate key: %v", err)
	}
	enc := base64.StdEncoding
	fmt.Printf("CLOUDFLARE_URL_SIGNING_PRIVATE_KEY=%s\n", enc.EncodeToString(priv.Seed()))
	fmt.Printf("CLOUDFLARE_URL_SIGNING_PUBLIC_KEY=%s\n", enc.EncodeToString(pub))
}
