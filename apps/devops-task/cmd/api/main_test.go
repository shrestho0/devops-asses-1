package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRootHandler_Success(t *testing.T) {
	// Setup test configuration
	cfg := Config{
		Port:     "8080",
		LogLevel: "info",
		EnvName:  "test-env",
		AppVer:   "1.0.0-test",
	}

	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	// Create a ResponseRecorder to record the response
	rr := httptest.NewRecorder()
	handler := rootHandler(cfg)

	// Call the handler directly
	handler.ServeHTTP(rr, req)

	// 1. Check status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}

	// 2. Check Content-Type header
	expectedContentType := "application/json"
	if ct := rr.Header().Get("Content-Type"); ct != expectedContentType {
		t.Errorf("handler returned wrong content type: got %v want %v", ct, expectedContentType)
	}

	// 3. Check JSON response body
	var response map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&response); err != nil {
		t.Fatalf("could not decode response body: %v", err)
	}

	expectedMessage := "Hello from DevOps Task!"
	if response["message"] != expectedMessage {
		t.Errorf("expected message %v, got %v", expectedMessage, response["message"])
	}

	if response["version"] != cfg.AppVer {
		t.Errorf("expected version %v, got %v", cfg.AppVer, response["version"])
	}

	if response["environment"] != cfg.EnvName {
		t.Errorf("expected environment %v, got %v", cfg.EnvName, response["environment"])
	}
}

func TestRootHandler_NotFound(t *testing.T) {
	cfg := Config{} // Config doesn't matter for 404
	req, err := http.NewRequest("GET", "/invalid-path", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := rootHandler(cfg)

	handler.ServeHTTP(rr, req)

	// Check status code is 404 Not Found
	if status := rr.Code; status != http.StatusNotFound {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusNotFound)
	}
}

func TestHealthHandler(t *testing.T) {
	req, err := http.NewRequest("GET", "/health", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(healthHandler)

	handler.ServeHTTP(rr, req)

	// 1. Check status code
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}

	// 2. Check Content-Type header
	expectedContentType := "application/json"
	if ct := rr.Header().Get("Content-Type"); ct != expectedContentType {
		t.Errorf("handler returned wrong content type: got %v want %v", ct, expectedContentType)
	}

	// 3. Check JSON response body
	var response map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&response); err != nil {
		t.Fatalf("could not decode response body: %v", err)
	}

	if response["status"] != "ok" {
		t.Errorf("expected status 'ok', got %v", response["status"])
	}
}