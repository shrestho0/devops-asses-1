package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Config holds the application configuration
type Config struct {
	Port     string
	LogLevel string
	EnvName  string
	AppVer   string
}

// loadConfig reads configuration from environment variables with fallbacks
func loadConfig() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}

	envName := os.Getenv("ENV_NAME")
	if envName == "" {
		envName = "development"
	}

	appVer := os.Getenv("APP_VERSION")
	if appVer == "" {
		appVer = "1.0.0"
	}

	return Config{
		Port:     port,
		LogLevel: logLevel,
		EnvName:  envName,
		AppVer:   appVer,
	}
}

// setupLogger configures standard structured JSON logging to stdout
func setupLogger(levelStr string) {
	var level slog.Level
	switch strings.ToLower(levelStr) {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: level,
	}))
	slog.SetDefault(logger)
}

// Prometheus metrics definitions
var (
	requestCount = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests processed",
		},
		[]string{"path", "method"},
	)

	errorCount = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_errors_total",
			Help: "Total number of HTTP requests resulting in an error (>=400)",
		},
		[]string{"path", "method", "status"},
	)

	requestLatency = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Histogram of request latencies in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"path", "method"},
	)
)

// responseWriter wraps http.ResponseWriter to capture the status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// metricsMiddleware intercepts requests to record metrics and optionally log them
func metricsMiddleware(path string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{w, http.StatusOK}

		next.ServeHTTP(rw, r)

		duration := time.Since(start)
		requestCount.WithLabelValues(path, r.Method).Inc()
		requestLatency.WithLabelValues(path, r.Method).Observe(duration.Seconds())

		if rw.statusCode >= 400 {
			errorCount.WithLabelValues(path, r.Method, strconv.Itoa(rw.statusCode)).Inc()
		}

		// Log individual requests at the debug level
		slog.Debug("HTTP Request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rw.statusCode),
			slog.Duration("duration", duration),
		)
	}
}

// rootHandler returns the main JSON response
func rootHandler(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		if err:=json.NewEncoder(w).Encode(map[string]string{
			"message":     "Hello from DevOps Task!",
			"status":      "running",
			"version":     cfg.AppVer,
			"environment": cfg.EnvName,
		}); err!= nil {
			slog.Error("Failed to write response", slog.String("error", err.Error()))
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
	}
}

// healthHandler is the liveness/readiness check
// func healthHandler(w http.ResponseWriter, r *http.Request) {
// 	w.Header().Set("Content-Type", "application/json")
// 	w.WriteHeader(http.StatusOK)
// 	if  _, err := w.Write([]byte(`{"status": "ok", "message": "Service is healthy"}`)); err!=nil {
// 		return 
// 	}
// }


// healthHandlerWillFail for generating failure
func healthHandlerWillFail(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	if  _, err := w.Write([]byte(`{"status": "error", "message": "Service is failing, by choice"}`)); err!=nil {
		return 
	}
}

func main() {
	// 1. Initialize configuration and structured logger
	cfg := loadConfig()
	setupLogger(cfg.LogLevel)

	slog.Info("Starting service",
		slog.String("port", cfg.Port),
		slog.String("env", cfg.EnvName),
		slog.String("version", cfg.AppVer),
		slog.String("log_level", cfg.LogLevel),
	)

	// 2. Setup router
	mux := http.NewServeMux()
	mux.HandleFunc("/", metricsMiddleware("/", rootHandler(cfg)))
	// mux.HandleFunc("/health", metricsMiddleware("/health", healthHandler))
	mux.HandleFunc("/health", metricsMiddleware("/health", healthHandlerWillFail))
	mux.Handle("/metrics", promhttp.Handler())

	// 3. Configure HTTP Server
	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: mux,
	}

	// 4. Start server in a background goroutine
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Server failed to start", slog.String("error", err.Error()))
			os.Exit(1)
		}
	}()

	// 5. Wait for SIGTERM or SIGINT
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Block until a signal is received
	sig := <-stop
	slog.Info("Received shutdown signal", slog.String("signal", sig.String()))

	// 6. Graceful Shutdown with a 5-second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("Server forced to shutdown", slog.String("error", err.Error()))
	} else {
		slog.Info("Server gracefully stopped")
	}
}