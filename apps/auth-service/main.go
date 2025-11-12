package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"golang.org/x/crypto/bcrypt"
)

var db *sql.DB
var jwtSecret = []byte(getEnv("JWT_SECRET", ""))

// Prometheus metrics
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "http_request_duration_seconds",
			Help: "Duration of HTTP requests in seconds",
		},
		[]string{"method", "endpoint"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

func main() {
	// Configure logger with timestamp
	log.SetFlags(log.Ldate | log.Ltime | log.LUTC)
	log.SetPrefix("[AUTH-SERVICE] ")

	var err error
	dbURL := getEnv("DATABASE_URL", "")
	log.Printf("INFO: Connecting to database...")
	db, err = sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("FATAL: Failed to connect to database: %v", err)
	}
	defer db.Close()

	log.Printf("INFO: Database connection initialized (lazy connection)")

	http.HandleFunc("/login", loggingMiddleware(handleLogin))
	http.HandleFunc("/verify", loggingMiddleware(handleVerify))
	http.HandleFunc("/healthz", handleHealth)
	http.HandleFunc("/livez", handleHealth)
	http.Handle("/metrics", promhttp.Handler())

	port := getEnv("PORT", "4000")
	log.Printf("INFO: Starting Auth Service on port %s", port)
	log.Printf("INFO: Endpoints registered: /login, /verify, /healthz, /livez, /metrics")
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("FATAL: Server failed to start: %v", err)
	}
}

type Claims struct {
	User string `json:"user"`
	jwt.RegisteredClaims
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	type creds struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	var c creds
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		log.Printf("WARN: Failed to decode login request: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if c.Username == "" || c.Password == "" {
		log.Printf("WARN: Login attempt with empty credentials from %s", r.RemoteAddr)
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	var dbPassword string
	err := db.QueryRow("SELECT password FROM users WHERE username=$1", c.Username).Scan(&dbPassword)
	if err != nil {
		log.Printf("WARN: Failed login attempt for user '%s' from %s: user not found", c.Username, r.RemoteAddr)
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	// Compare bcrypt hashed password
	err = bcrypt.CompareHashAndPassword([]byte(dbPassword), []byte(c.Password))
	if err != nil {
		log.Printf("WARN: Failed login attempt for user '%s' from %s: invalid password", c.Username, r.RemoteAddr)
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	expirationTime := time.Now().Add(time.Hour)
	claims := &Claims{
		User: c.Username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		log.Printf("ERROR: Failed to sign JWT for user '%s': %v", c.Username, err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	log.Printf("INFO: Successful login for user '%s' from %s", c.Username, r.RemoteAddr)
	json.NewEncoder(w).Encode(map[string]string{"token": tokenString})
}

func handleVerify(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		log.Printf("WARN: Token verification failed from %s: missing authorization header", r.RemoteAddr)
		http.Error(w, "Missing token", http.StatusUnauthorized)
		return
	}

	if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
		log.Printf("WARN: Token verification failed from %s: invalid authorization format", r.RemoteAddr)
		http.Error(w, "Invalid token format", http.StatusUnauthorized)
		return
	}

	tokenString := authHeader[7:]
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil {
		log.Printf("WARN: Token verification failed from %s: %v", r.RemoteAddr, err)
		http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
		return
	}
	if !token.Valid {
		log.Printf("WARN: Token verification failed from %s: invalid token", r.RemoteAddr)
		http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
		return
	}
	
	// Extract username from claims for logging
	if claims, ok := token.Claims.(jwt.MapClaims); ok {
		if user, exists := claims["user"]; exists {
			log.Printf("INFO: Token verified successfully for user '%v' from %s", user, r.RemoteAddr)
		}
	}
	
	json.NewEncoder(w).Encode(map[string]string{"valid": "true"})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next(rw, r)
		duration := time.Since(start)
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration.Seconds())
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, http.StatusText(rw.statusCode)).Inc()
		log.Printf("INFO: %s %s completed in %v from %s", r.Method, r.URL.Path, duration, r.RemoteAddr)
	}
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func getEnv(key, fallback string) string {
	if val, exists := os.LookupEnv(key); exists {
		return val
	}
	return fallback
}