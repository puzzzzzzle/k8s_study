package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	pingTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "pingpong_ping_total",
		Help: "Total number of /ping requests received",
	})
	pingDuration = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "pingpong_ping_duration_seconds",
		Help:    "Duration of /ping requests",
		Buckets: prometheus.DefBuckets,
	})
)

type PingResponse struct {
	Message string `json:"message"`
	Time    string `json:"time"`
}

func pingHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	defer func() {
		pingDuration.Observe(time.Since(start).Seconds())
	}()

	pingTotal.Inc()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(PingResponse{
		Message: "pong",
		Time:    time.Now().UTC().Format(time.RFC3339),
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func main() {
	http.HandleFunc("/ping", pingHandler)
	http.HandleFunc("/healthz", healthHandler)
	http.Handle("/metrics", promhttp.Handler())

	log.Println("go-pingpong listening on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
