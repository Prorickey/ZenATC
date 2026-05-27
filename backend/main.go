package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	"github.com/gin-gonic/gin"
)

// hlsDir resolves to audio/hls/ relative to this source file so the server
// works regardless of the working directory it is launched from.
var hlsDir = sourceRelative("audio/hls")

func sourceRelative(name string) string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return name
	}
	return filepath.Join(filepath.Dir(file), name)
}

// validHLSPath restricts requests to /<trackID>/index.m3u8 or /<trackID>/seg_NNN.ts,
// preventing directory traversal and unexpected file access.
var validHLSPath = regexp.MustCompile(`^/[a-zA-Z0-9_-]+/(index\.m3u8|seg_\d+\.ts)$`)

func main() {
	initChallengeKey()
	initVerification()
	initCDN()

	gin.SetMode(gin.ReleaseMode)
	router := gin.Default()

	// Trust Cloudflare's CF-Connecting-IP for accurate client IPs in logs / rate limiting.
	router.TrustedPlatform = gin.PlatformCloudflare

	// CORS — allows the iOS AVPlayer and any CDN pass-through to issue requests.
	router.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Range")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Range")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	router.GET("/attestation-challenge", attestationChallengeHandler)
	router.POST("/verify-and-stream", verifyAndStreamHandler)
	router.POST("/attest-key", attestKeyHandler)
	router.POST("/assert-and-stream", assertAndStreamHandler)

	// HLS audio — VOD segments pre-sliced at build time.
	//
	// ┌─ /hls/:id/index.m3u8 ──── requires signed token, private (not cached by CDN)
	// └─ /hls/:id/seg_NNN.ts ──── public, immutable — Cloudflare caches these at the edge
	router.GET("/hls/*filepath", hlsHandler)

	log.Printf("ZenATC backend listening on :8080")
	log.Printf("HLS audio available at /hls/<track_id>/index.m3u8?expires=…&signature=…")
	if err := router.Run(":8080"); err != nil {
		log.Fatal(err)
	}
}

// hlsHandler serves pre-sliced VOD HLS files.
//
// Signature validation is handled by the Cloudflare Worker at the edge before
// requests reach this origin. The origin trusts that any request that arrives
// here has already been validated.
//
// Playlists (.m3u8):  never cached by CDN (private, no-store).
// Segments  (.ts):    public and immutable — Cloudflare caches these at the edge.
func hlsHandler(c *gin.Context) {
	fp := c.Param("filepath") // e.g. "/lofi_late_night/index.m3u8"

	if !validHLSPath.MatchString(fp) {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}

	if strings.HasSuffix(fp, "index.m3u8") {
		// Private — each URL carries a unique signature; Cloudflare must not
		// cache the playlist or subsequent requests will share tokens.
		c.Header("Cache-Control", "private, no-store")
		c.Header("Content-Type", "application/vnd.apple.mpegurl")
	} else {
		// Segments are content-addressed and never change; cache indefinitely.
		c.Header("Cache-Control", "public, max-age=31536000, immutable")
		c.Header("CDN-Cache-Control", "max-age=31536000")
		c.Header("Content-Type", "video/mp2t")
	}

	fullPath := filepath.Join(hlsDir, filepath.FromSlash(strings.TrimPrefix(fp, "/")))
	if _, err := os.Stat(fullPath); err != nil {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	c.File(fullPath)
}
