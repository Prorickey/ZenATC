package main

import (
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"

	"github.com/gin-gonic/gin"
)

// audioDir resolves to the audio/ folder next to this source file,
// so the server works regardless of what directory it is launched from.
var audioDir = func() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return "audio"
	}
	return filepath.Join(filepath.Dir(file), "audio")
}()

func main() {
	router := gin.Default()

	// CORS — fine for local development
	router.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// GET /stream/:id — e.g. /stream/atc_atl or /stream/lofi_late_night
	//
	// Each connection gets its own goroutine reading the file on loop.
	// TCP backpressure naturally rate-limits delivery to playback speed —
	// no artificial sleep or shared broadcaster needed.
	router.GET("/stream/:id", func(c *gin.Context) {
		id := c.Param("id")
		path := filepath.Join(audioDir, id+".mp3")

		if _, err := os.Stat(path); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "stream not found: " + id})
			return
		}

		f, err := os.Open(path)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open stream"})
			return
		}
		defer f.Close()

		c.Header("Content-Type", "audio/mpeg")
		c.Header("Cache-Control", "no-cache, no-store")
		c.Header("Connection", "keep-alive")

		log.Printf("[stream] %s connected", id)
		defer log.Printf("[stream] %s disconnected", id)

		ctx := c.Request.Context()
		buf := make([]byte, 32*1024) // 32 KB per write

		c.Stream(func(w io.Writer) bool {
			select {
			case <-ctx.Done():
				return false
			default:
			}

			n, err := f.Read(buf)
			if n > 0 {
				if _, werr := w.Write(buf[:n]); werr != nil {
					return false
				}
			}
			if err == io.EOF {
				// Loop: seek back to the start and keep streaming
				_, serr := f.Seek(0, io.SeekStart)
				return serr == nil
			}
			return err == nil
		})
	})

	log.Println("ZenATC backend listening on :8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatal(err)
	}
}
