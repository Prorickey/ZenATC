package main

import (
	"database/sql"
	"log"
	"os"

	_ "modernc.org/sqlite"
)

// db is the process-wide handle to the SQLite store holding registered device keys.
var db *sql.DB

// initDB opens (and creates if needed) the SQLite database and ensures the
// attested_keys table exists. The file path is read from ZENATC_DB_PATH,
// defaulting to zenatc.db next to the source so it survives restarts/redeploys.
func initDB() {
	path := os.Getenv("ZENATC_DB_PATH")
	if path == "" {
		path = sourceRelative("zenatc.db")
	}

	conn, err := sql.Open("sqlite", path)
	if err != nil {
		log.Fatalf("[db] failed to open SQLite database at %q: %v", path, err)
	}

	// SQLite is single-writer; a single connection avoids "database is locked"
	// errors and keeps the read-check-write counter update serialized.
	conn.SetMaxOpenConns(1)

	if _, err := conn.Exec(`
		CREATE TABLE IF NOT EXISTS attested_keys (
			key_id     TEXT PRIMARY KEY,
			public_key BLOB NOT NULL,
			counter    INTEGER NOT NULL
		)`); err != nil {
		log.Fatalf("[db] failed to create attested_keys table: %v", err)
	}

	db = conn
	log.Printf("[db] SQLite key store ready at %s", path)
}
