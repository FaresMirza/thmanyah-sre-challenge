package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	_ "github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"
)

var db *sql.DB
var jwtSecret = []byte(getEnv("JWT_SECRET", ""))

func main() {
	var err error
	db, err = sql.Open("postgres", getEnv("DATABASE_URL", ""))
	if err != nil {
		panic(err)
	}
	defer db.Close()

	http.HandleFunc("/login", handleLogin)
	http.HandleFunc("/verify", handleVerify)
	http.HandleFunc("/healthz", handleHealth)
	http.HandleFunc("/livez", handleHealth)

	port := getEnv("PORT", "4000")
	fmt.Println("🔐 Auth Service running on port " + port)
	http.ListenAndServe(":"+port, nil)
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
	json.NewDecoder(r.Body).Decode(&c)

	var dbPassword string
	err := db.QueryRow("SELECT password FROM users WHERE username=$1", c.Username).Scan(&dbPassword)
	if err != nil {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	// Compare bcrypt hashed password
	err = bcrypt.CompareHashAndPassword([]byte(dbPassword), []byte(c.Password))
	if err != nil {
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
	tokenString, _ := token.SignedString(jwtSecret)

	json.NewEncoder(w).Encode(map[string]string{"token": tokenString})
}

func handleVerify(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" {
		http.Error(w, "Missing token", http.StatusUnauthorized)
		return
	}

	tokenString := authHeader[len("Bearer "):]
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil || !token.Valid {
		http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"valid": "true"})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

func getEnv(key, fallback string) string {
	if val, exists := os.LookupEnv(key); exists {
		return val
	}
	return fallback
}