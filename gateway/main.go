package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type config struct {
	ListenAddr      string
	UpstreamBaseURL *url.URL // Optional: for LLM API proxy
	UpstreamAPIKey  string   // Optional: for LLM API proxy

	AccessCodes []string

	AllowedOrigins []string

	UploadDir       string
	MaxUploadBytes  int64
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	// OpenAI-compatible endpoints (proxy) - only if upstream is configured
	if cfg.UpstreamBaseURL != nil && cfg.UpstreamAPIKey != "" {
		mux.Handle("/v1/chat/completions", proxyHandler(cfg, "/chat/completions"))
		mux.Handle("/v1/responses", proxyHandler(cfg, "/responses"))
		mux.Handle("/v1/models", proxyHandler(cfg, "/models"))
		log.Printf("LLM proxy enabled: upstream=%s", cfg.UpstreamBaseURL.String())
	} else {
		log.Printf("LLM proxy disabled (UPSTREAM_BASE_URL or UPSTREAM_API_KEY not set)")
	}

	// Upload & serve files for the web frontend (always enabled)
	mux.Handle("/webapi/upload", uploadHandler(cfg))
	mux.Handle("/files/", filesHandler(cfg))

	// WebDAV proxy for web frontend (bypasses CORS restrictions)
	// Use a custom handler that accepts all methods
	mux.HandleFunc("/webapi/webdav/", func(w http.ResponseWriter, r *http.Request) {
		webdavProxyHandler(cfg).ServeHTTP(w, r)
	})

	handler := withCORS(cfg, mux)

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("kelivo-gateway listening on %s", cfg.ListenAddr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("listen error: %v", err)
	}
}

func loadConfig() (*config, error) {
	listenAddr := strings.TrimSpace(getenv("LISTEN_ADDR", ":8080"))

	// Upstream config is now optional (for LLM proxy feature)
	var upstreamURL *url.URL
	upstreamRaw := strings.TrimSpace(os.Getenv("UPSTREAM_BASE_URL"))
	if upstreamRaw != "" {
		var err error
		upstreamURL, err = url.Parse(upstreamRaw)
		if err != nil {
			return nil, fmt.Errorf("invalid UPSTREAM_BASE_URL: %w", err)
		}
		if upstreamURL.Scheme != "http" && upstreamURL.Scheme != "https" {
			return nil, fmt.Errorf("UPSTREAM_BASE_URL must be http(s)")
		}
		if upstreamURL.Host == "" {
			return nil, fmt.Errorf("UPSTREAM_BASE_URL must include host")
		}
		upstreamURL.Path = strings.TrimRight(upstreamURL.Path, "/")
	}

	upstreamKey := strings.TrimSpace(os.Getenv("UPSTREAM_API_KEY"))

	accessCodes := splitCSV(os.Getenv("ACCESS_CODE"))
	allowedOrigins := splitCSV(os.Getenv("CORS_ALLOW_ORIGINS"))

	uploadDir := strings.TrimSpace(getenv("UPLOAD_DIR", "./uploads"))

	maxUploadMB := strings.TrimSpace(getenv("MAX_UPLOAD_MB", "25"))
	maxUpload := int64(25 << 20)
	if v, err := parseInt64(maxUploadMB); err == nil && v > 0 {
		maxUpload = v << 20
	}

	return &config{
		ListenAddr:      listenAddr,
		UpstreamBaseURL: upstreamURL,
		UpstreamAPIKey:  upstreamKey,
		AccessCodes:     accessCodes,
		AllowedOrigins:  allowedOrigins,
		UploadDir:       uploadDir,
		MaxUploadBytes:  maxUpload,
	}, nil
}

func proxyHandler(cfg *config, upstreamPath string) http.Handler {
	client := &http.Client{
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			// Streaming responses can be long-lived; do not set Client.Timeout.
			ForceAttemptHTTP2:     true,
			MaxIdleConns:          64,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost && r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		if !checkAccess(cfg, r) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		// Small host: cap request body size to avoid OOM from abuse.
		// Chat payloads are JSON and should stay small.
		r.Body = http.MaxBytesReader(w, r.Body, 10<<20) // 10 MiB

		target := *cfg.UpstreamBaseURL
		target.Path = target.Path + upstreamPath

		req, err := http.NewRequestWithContext(r.Context(), r.Method, target.String(), r.Body)
		if err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}

		// Pass-through some headers, but never let client control upstream auth.
		copyHeader(req.Header, r.Header, "Content-Type", "Accept", "User-Agent")
		// Keep streaming simple and predictable.
		req.Header.Set("Accept-Encoding", "identity")
		req.Header.Set("Authorization", "Bearer "+cfg.UpstreamAPIKey)

		// Preserve query string if any (mostly for /models).
		req.URL.RawQuery = r.URL.RawQuery

		resp, err := client.Do(req)
		if err != nil {
			http.Error(w, "upstream error", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		// Copy status and headers.
		for k, vv := range resp.Header {
			// Avoid Go's automatic compression here; we want clean streaming behavior.
			if strings.EqualFold(k, "Content-Encoding") {
				continue
			}
			for _, v := range vv {
				w.Header().Add(k, v)
			}
		}

		// Help proxies keep SSE unbuffered.
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("X-Accel-Buffering", "no")

		w.WriteHeader(resp.StatusCode)

		fl, _ := w.(http.Flusher)
		_, copyErr := io.Copy(&flushWriter{w: w, fl: fl}, resp.Body)
		if copyErr != nil && !errors.Is(copyErr, context.Canceled) && !errors.Is(copyErr, context.DeadlineExceeded) {
			// Can't reliably write an error here; connection may already be broken.
			log.Printf("stream copy error: %v", copyErr)
		}
	})
}

type flushWriter struct {
	w  io.Writer
	fl http.Flusher
}

func (fw *flushWriter) Write(p []byte) (int, error) {
	n, err := fw.w.Write(p)
	if fw.fl != nil {
		fw.fl.Flush()
	}
	return n, err
}

func checkAccess(cfg *config, r *http.Request) bool {
	// If not configured, allow (dev mode).
	if len(cfg.AccessCodes) == 0 {
		return true
	}

	code := strings.TrimSpace(r.Header.Get("X-Access-Code"))
	if code == "" {
		code = bearerToken(r.Header.Get("Authorization"))
	}
	if code == "" {
		code = strings.TrimSpace(r.URL.Query().Get("access_code"))
	}
	if code == "" {
		return false
	}

	for _, allowed := range cfg.AccessCodes {
		if subtle.ConstantTimeCompare([]byte(code), []byte(allowed)) == 1 {
			return true
		}
	}
	return false
}

func withCORS(cfg *config, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && isAllowedOrigin(cfg.AllowedOrigins, origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Access-Code, X-WebDAV-URL, X-WebDAV-Username, X-WebDAV-Password, Depth, Destination, Overwrite")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PROPFIND, MKCOL, COPY, MOVE, OPTIONS")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isAllowedOrigin(allowed []string, origin string) bool {
	if len(allowed) == 0 {
		// If unset: don't do permissive CORS by default. Use same-origin behind reverse proxy.
		return false
	}
	for _, a := range allowed {
		if a == "*" || strings.EqualFold(a, origin) {
			return true
		}
	}
	return false
}

func bearerToken(authHeader string) string {
	v := strings.TrimSpace(authHeader)
	if v == "" {
		return ""
	}
	const prefix = "Bearer "
	if len(v) <= len(prefix) || !strings.EqualFold(v[:len(prefix)], prefix) {
		return ""
	}
	return strings.TrimSpace(v[len(prefix):])
}

func splitCSV(s string) []string {
	raw := strings.TrimSpace(s)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func copyHeader(dst, src http.Header, keys ...string) {
	for _, k := range keys {
		if v := src.Get(k); v != "" {
			dst.Set(k, v)
		}
	}
}

func getenv(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func parseInt64(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("empty")
	}
	var n int64
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0, fmt.Errorf("not int")
		}
		n = n*10 + int64(ch-'0')
	}
	return n, nil
}

func uploadHandler(cfg *config) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if !checkAccess(cfg, r) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		if err := os.MkdirAll(cfg.UploadDir, 0o755); err != nil {
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, cfg.MaxUploadBytes)
		mr, err := r.MultipartReader()
		if err != nil {
			http.Error(w, "invalid multipart", http.StatusBadRequest)
			return
		}

		var savedName string
		var origName string

		for {
			part, err := mr.NextPart()
			if err != nil {
				if errors.Is(err, io.EOF) {
					break
				}
				http.Error(w, "invalid multipart", http.StatusBadRequest)
				return
			}
			if part.FormName() != "file" || part.FileName() == "" {
				_ = part.Close()
				continue
			}
			origName = part.FileName()

			ext := strings.ToLower(filepath.Ext(origName))
			if len(ext) > 10 {
				ext = ""
			}
			if ext != "" {
				// Keep only simple extensions; strip weird ones.
				ext = strings.TrimLeft(ext, ".")
				if !regexpSafeExt(ext) {
					ext = ""
				}
			}

			token := make([]byte, 16)
			if _, err := rand.Read(token); err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				_ = part.Close()
				return
			}
			base := hex.EncodeToString(token)
			if ext != "" {
				savedName = base + "." + ext
			} else {
				savedName = base
			}

			dstPath := filepath.Join(cfg.UploadDir, savedName)
			f, err := os.OpenFile(dstPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
			if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				_ = part.Close()
				return
			}
			_, copyErr := io.Copy(f, part)
			_ = part.Close()
			_ = f.Close()
			if copyErr != nil {
				_ = os.Remove(dstPath)
				http.Error(w, "upload failed", http.StatusBadRequest)
				return
			}
			break
		}

		if savedName == "" {
			http.Error(w, "missing file", http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"url":      publicURL(r, "/files/"+savedName),
			"filename": origName,
			"stored":   savedName,
		})
	})
}

func filesHandler(cfg *config) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/files/") {
			http.NotFound(w, r)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, "/files/")
		// Flat storage only.
		if name == "" || strings.Contains(name, "/") || strings.Contains(name, "\\") || strings.Contains(name, "..") {
			http.NotFound(w, r)
			return
		}
		// Optional protection: if ACCESS_CODE configured and the request includes one, it must match.
		// We intentionally allow public reads by default because browsers can't attach headers to <img>.
		if len(cfg.AccessCodes) > 0 {
			code := strings.TrimSpace(r.URL.Query().Get("access_code"))
			if code != "" && !checkAccess(cfg, r) {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}
		path := filepath.Join(cfg.UploadDir, name)
		http.ServeFile(w, r, path)
	})
}

func regexpSafeExt(ext string) bool {
	for _, ch := range ext {
		if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
			continue
		}
		return false
	}
	return true
}

func publicURL(r *http.Request, path string) string {
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	scheme := strings.TrimSpace(r.Header.Get("X-Forwarded-Proto"))
	if scheme == "" {
		if r.TLS != nil {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}
	host := strings.TrimSpace(r.Header.Get("X-Forwarded-Host"))
	if host == "" {
		host = r.Host
	}
	// X-Forwarded-Host may contain a comma-separated list
	if i := strings.Index(host, ","); i >= 0 {
		host = strings.TrimSpace(host[:i])
	}
	if host == "" {
		return path
	}
	return scheme + "://" + host + path
}

// webdavProxyHandler proxies WebDAV requests to remote servers.
// This allows the web frontend to access WebDAV servers without CORS issues.
//
// Request format:
//   - URL: /webapi/webdav/{path}
//   - Headers:
//   - X-WebDAV-URL: Target WebDAV server base URL (required)
//   - X-WebDAV-Username: Basic auth username (optional)
//   - X-WebDAV-Password: Basic auth password (optional)
//   - Method: Any HTTP method (GET, PUT, PROPFIND, DELETE, MKCOL, etc.)
func webdavProxyHandler(cfg *config) http.Handler {
	client := &http.Client{
		Transport: &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			ForceAttemptHTTP2:     true,
			MaxIdleConns:          32,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		},
		Timeout: 120 * time.Second, // WebDAV operations can be slow
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		// Check access code if configured
		if !checkAccess(cfg, r) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		// Get target WebDAV server URL from header
		targetURL := strings.TrimSpace(r.Header.Get("X-WebDAV-URL"))
		if targetURL == "" {
			http.Error(w, "missing X-WebDAV-URL header", http.StatusBadRequest)
			return
		}

		// Parse and validate target URL
		parsedURL, err := url.Parse(targetURL)
		if err != nil {
			http.Error(w, "invalid X-WebDAV-URL", http.StatusBadRequest)
			return
		}
		if parsedURL.Scheme != "http" && parsedURL.Scheme != "https" {
			http.Error(w, "X-WebDAV-URL must be http or https", http.StatusBadRequest)
			return
		}

		// Get the path after /webapi/webdav/
		path := strings.TrimPrefix(r.URL.Path, "/webapi/webdav")
		if path == "" {
			path = "/"
		}

		// Build the full target URL
		fullURL := strings.TrimRight(targetURL, "/") + path
		if r.URL.RawQuery != "" {
			fullURL += "?" + r.URL.RawQuery
		}

		// Create proxy request
		proxyReq, err := http.NewRequestWithContext(r.Context(), r.Method, fullURL, r.Body)
		if err != nil {
			http.Error(w, "failed to create request", http.StatusInternalServerError)
			return
		}

		// Copy relevant headers
		for _, h := range []string{"Content-Type", "Content-Length", "Depth", "Destination", "Overwrite"} {
			if v := r.Header.Get(h); v != "" {
				proxyReq.Header.Set(h, v)
			}
		}

		// Set Basic Auth if provided
		username := r.Header.Get("X-WebDAV-Username")
		password := r.Header.Get("X-WebDAV-Password")
		if username != "" {
			proxyReq.SetBasicAuth(username, password)
		}

		// Forward the request
		resp, err := client.Do(proxyReq)
		if err != nil {
			log.Printf("WebDAV proxy error: %v", err)
			http.Error(w, "webdav request failed: "+err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		// Copy response headers
		for k, vv := range resp.Header {
			for _, v := range vv {
				w.Header().Add(k, v)
			}
		}

		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
	})
}
