// Command visitapp is a tiny visit-log web service backed by PostgreSQL.
//
// Every request to "/" records the caller's IP address and User-Agent in the
// `visits` table and renders a page showing the caller's IP, the total number
// of visits and the most recent ones. "/healthz" pings the database so the
// deploy can verify the service end to end.
//
// Configuration is read from the environment:
//
//	DATABASE_URL  PostgreSQL connection string (required)
//	LISTEN_ADDR   address to listen on (default ":80")
package main

import (
	"context"
	"errors"
	"html/template"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const schema = `
CREATE TABLE IF NOT EXISTS visits (
    id         bigserial   PRIMARY KEY,
    ip         inet        NOT NULL,
    user_agent text,
    visited_at timestamptz NOT NULL DEFAULT now()
);`

type visit struct {
	IP        string
	UserAgent string
	VisitedAt time.Time
}

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Visit log</title></head>
<body style="font-family: sans-serif; max-width: 40rem; margin: 3rem auto;">
  <h1>Visit log</h1>
  <p>Your IP address is <strong>{{ .IP }}</strong>.</p>
  <p>This page has been visited <strong>{{ .Count }}</strong> times.</p>
  <h2>Recent visits</h2>
  <ul>
  {{- range .Recent }}
    <li>{{ .VisitedAt.Format "2006-01-02 15:04:05 MST" }} — {{ .IP }} ({{ .UserAgent }})</li>
  {{- else }}
    <li>none yet</li>
  {{- end }}
  </ul>
</body>
</html>`))

type server struct {
	db *pgxpool.Pool
}

// clientIP extracts the caller's address, honoring X-Forwarded-For so the app
// reports the real client if it ever sits behind a reverse proxy.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	ip := clientIP(r)
	ua := r.UserAgent()
	ctx := r.Context()

	if _, err := s.db.Exec(ctx,
		`INSERT INTO visits (ip, user_agent) VALUES ($1, $2)`, ip, ua); err != nil {
		log.Printf("insert visit: %v", err)
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}

	var count int64
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM visits`).Scan(&count); err != nil {
		log.Printf("count visits: %v", err)
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}

	rows, err := s.db.Query(ctx,
		`SELECT ip::text, user_agent, visited_at FROM visits ORDER BY id DESC LIMIT 10`)
	if err != nil {
		log.Printf("recent visits: %v", err)
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var recent []visit
	for rows.Next() {
		var v visit
		if err := rows.Scan(&v.IP, &v.UserAgent, &v.VisitedAt); err != nil {
			log.Printf("scan visit: %v", err)
			http.Error(w, "database error", http.StatusInternalServerError)
			return
		}
		recent = append(recent, v)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := page.Execute(w, struct {
		IP     string
		Count  int64
		Recent []visit
	}{ip, count, recent}); err != nil {
		log.Printf("render page: %v", err)
	}
}

func (s *server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Ping(ctx); err != nil {
		log.Printf("healthz ping: %v", err)
		http.Error(w, "database unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte("ok\n"))
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":80"
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer pool.Close()

	if _, err := pool.Exec(ctx, schema); err != nil {
		log.Fatalf("ensure schema: %v", err)
	}

	s := &server{db: pool}
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleIndex)
	mux.HandleFunc("/healthz", s.handleHealthz)

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("listening on %s", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server: %v", err)
		}
	}()

	<-ctx.Done()
	log.Print("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}
