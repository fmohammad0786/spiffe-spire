package main

import (
    "context"
    "fmt"
    "io"
    "log"
    "net/http"
    "os"
    "time"
    
    "github.com/spiffe/go-spiffe/v2/spiffeid"
    "github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
    "github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
    ctx := context.Background()
    
    targetURL := os.Getenv("TARGET_URL")
    if targetURL == "" {
        targetURL = "https://server-a.test-app.svc.cluster.local:8443"
    }
    
    targetSPIFFEID := os.Getenv("TARGET_SPIFFE_ID")
    if targetSPIFFEID == "" {
        targetSPIFFEID = "spiffe://bb-team.org/server-a"
    }
    
    source, err := workloadapi.NewX509Source(ctx)
    if err != nil {
        log.Fatalf("Unable to create X509Source: %v", err)
    }
    defer source.Close()
    
    svid, err := source.GetX509SVID()
    if err != nil {
        log.Fatalf("Unable to get SVID: %v", err)
    }
    log.Printf("Client started with SPIFFE ID: %s", svid.ID)
    log.Printf("Target: %s (%s)", targetURL, targetSPIFFEID)
    
    expectedID, err := spiffeid.FromString(targetSPIFFEID)
    if err != nil {
        log.Fatalf("Invalid target SPIFFE ID: %v", err)
    }
    
    authorizer := tlsconfig.AuthorizeID(expectedID)
    tlsConfig := tlsconfig.MTLSClientConfig(source, source, authorizer)
    client := &http.Client{
        Transport: &http.Transport{TLSClientConfig: tlsConfig},
        Timeout: 10 * time.Second,
    }
    
    makeRequest(client, targetURL)
    
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        makeRequest(client, targetURL)
    }
}

func makeRequest(client *http.Client, url string) {
    log.Printf("Making request to %s...", url)
    
    resp, err := client.Get(url)
    if err != nil {
        log.Printf("❌ Request failed: %v", err)
        return
    }
    defer resp.Body.Close()
    
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        log.Printf("❌ Failed to read response: %v", err)
        return
    }
    
    log.Printf("✓ Response (Status: %s):", resp.Status)
    fmt.Println(string(body))
}
