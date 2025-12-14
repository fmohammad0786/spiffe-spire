package main

import (
    "context"
    "fmt"
    "log"
    "net/http"
    "time"
    
    "github.com/spiffe/go-spiffe/v2/spiffeid"
    "github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
    "github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
    ctx := context.Background()
    
    source, err := workloadapi.NewX509Source(ctx)
    if err != nil {
        log.Fatalf("Unable to create X509Source: %v", err)
    }
    defer source.Close()
    
    svid, err := source.GetX509SVID()
    if err != nil {
        log.Fatalf("Unable to get SVID: %v", err)
    }
    log.Printf("Server started with SPIFFE ID: %s", svid.ID)
    
    authorizer := tlsconfig.AuthorizeAny()
    serverConfig := tlsconfig.MTLSServerConfig(source, source, authorizer)
    server := &http.Server{
        Addr:      ":8443",
        TLSConfig: serverConfig,
    }
    
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        var peerID string
        if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
            id, err := spiffeid.FromURI(r.TLS.PeerCertificates[0].URIs[0])
            if err == nil {
                peerID = id.String()
            }
        }
        
        response := fmt.Sprintf(`{
  "server": "Cluster A (bb-team.org)",
  "server_spiffe_id": "%s",
  "client_spiffe_id": "%s",
  "timestamp": "%s",
  "message": "✓ Successfully authenticated via SPIFFE Federation!"
}`, svid.ID, peerID, time.Now().Format(time.RFC3339))
        
        log.Printf("Request from: %s", peerID)
        w.Header().Set("Content-Type", "application/json")
        fmt.Fprintln(w, response)
    })
    
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "OK")
    })
    
    log.Printf("Server listening on :8443")
    if err := server.ListenAndServeTLS("", ""); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}
