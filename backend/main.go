package main

import (
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// Resolve sibling directories relative to this source file so the server
// works regardless of the working directory it is launched from.
var (
	audioDir = sourceRelative("audio")
	liveDir  = sourceRelative("live")
)

func sourceRelative(name string) string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return name
	}
	return filepath.Join(filepath.Dir(file), name)
}

// startHLSEngine spawns an ffmpeg process that reads the source MP3 on an
// infinite loop and writes a rolling 5-segment HLS playlist to live/<id>/.
// If ffmpeg exits for any reason it is automatically restarted.
func startHLSEngine(id string) {
	input := filepath.Join(audioDir, id+".mp3")
	outDir := filepath.Join(liveDir, id)

	if err := os.MkdirAll(outDir, 0o755); err != nil {
		log.Fatalf("[hls] cannot create output dir for %s: %v", id, err)
	}

	go func() {
		for {
			cmd := exec.Command("ffmpeg",
				"-re",                  // read at native playback speed
				"-stream_loop", "-1",   // loop the source infinitely
				"-i", input,
				"-c:a", "aac",
				"-b:a", "128k",
				"-f", "hls",
				"-hls_time", "4",       // 4-second segments
				"-hls_list_size", "5",  // keep only 5 segments in the playlist
				"-hls_flags", "delete_segments", // delete old segments from disk
				"-hls_segment_filename", filepath.Join(outDir, "seg_%05d.ts"),
				filepath.Join(outDir, "index.m3u8"),
			)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr

			log.Printf("[hls] starting engine for %s", id)
			if err := cmd.Run(); err != nil {
				log.Printf("[hls] ffmpeg for %s exited (%v) — restarting in 2s", id, err)
				time.Sleep(2 * time.Second)
			}
		}
	}()
}

func main() {
	// Verify ffmpeg is available before doing anything else.
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		log.Fatal("ffmpeg not found in PATH — install it with: brew install ffmpeg")
	}

	// Auto-discover every .mp3 in audio/ and start an HLS engine for each.
	entries, err := os.ReadDir(audioDir)
	if err != nil {
		log.Fatalf("cannot read audio dir %s: %v", audioDir, err)
	}
	for _, e := range entries {
		if !e.IsDir() && strings.ToLower(filepath.Ext(e.Name())) == ".mp3" {
			id := strings.TrimSuffix(e.Name(), filepath.Ext(e.Name()))
			startHLSEngine(id)
		}
	}

	gin.SetMode(gin.ReleaseMode)
	router := gin.Default()

	// CORS — required for CDN pass-through and browser HLS players.
	router.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Range")
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

	// Differentiated Cache-Control so a CDN caches chunks long-term but
	// revalidates the playlist on every request (it changes every 4 seconds).
	router.Use(func(c *gin.Context) {
		ext := filepath.Ext(c.Request.URL.Path)
		switch ext {
		case ".m3u8":
			c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
		case ".ts":
			c.Header("Cache-Control", "public, max-age=600")
		}
		c.Next()
	})

	// Serve the rolling HLS output directory.
	// Playlist URL pattern: /radio/<id>/index.m3u8
	// e.g. http://localhost:8080/radio/atc_atl/index.m3u8
	router.StaticFS("/radio", gin.Dir(liveDir, false))

	log.Printf("ZenATC backend listening on :8080")
	log.Printf("Streams available at /radio/<id>/index.m3u8 once ffmpeg warms up (~4s)")
	if err := router.Run(":8080"); err != nil {
		log.Fatal(err)
	}
}
