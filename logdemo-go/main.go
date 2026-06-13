package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"
)

var logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

func work(w http.ResponseWriter, r *http.Request) {
	time.Sleep(50 * time.Millisecond)
	// One JSON line per request: OBI enriches synchronous stdout writes on the handler thread.
	logger.Info("request complete", "route", "/work", "duration_ms", 50)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func main() {
	logger.Info("server start", "pid", os.Getpid(), "port", 8080)
	mux := http.NewServeMux()
	mux.HandleFunc("/work", work)
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	srv := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	logger.Error("server exited", "err", srv.ListenAndServe().Error())
}
