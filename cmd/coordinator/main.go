package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"

	"moment/pkg/mdns"
	"moment/pkg/ntp"
	"moment/pkg/ws"

	"github.com/skip2/go-qrcode"
)

func getLocalIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "127.0.0.1"
	}
	for _, address := range addrs {
		// check the address type and if it is not a loopback the display it
		if ipnet, ok := address.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				ipStr := ipnet.IP.String()
				// Return typical local private networks
				if strings.HasPrefix(ipStr, "192.168.") || strings.HasPrefix(ipStr, "10.") || strings.HasPrefix(ipStr, "172.16.") {
					return ipStr
				}
			}
		}
	}
	return "127.0.0.1"
}

func main() {
	port := flag.Int("port", 8080, "WebSocket server port")
	ntpPort := flag.Int("ntp-port", 1230, "UDP NTP server port")
	flag.Parse()

	localIP := getLocalIP()
	wsURL := fmt.Sprintf("ws://%s:%d/ws", localIP, *port)

	log.Println("==================================================")
	log.Printf("[SERVER] Starting Project Moment Coordinator")
	log.Printf("[SERVER] Local IP Address resolved: %s", localIP)
	log.Printf("[SERVER] WebSocket Endpoint: %s", wsURL)
	log.Printf("[SERVER] UDP NTP Server Endpoint: %s:%d", localIP, *ntpPort)
	log.Println("==================================================")

	// Start mDNS advertiser
	adv, err := mdns.StartAdvertiser(*port)
	if err != nil {
		log.Printf("[WARNING] Failed to start mDNS advertiser: %v", err)
	} else {
		defer adv.Stop()
		log.Printf("[mDNS] Advertising service _moment-coordinator._tcp on port %d", *port)
	}

	// Start local NTP server
	ntpAddr := fmt.Sprintf("%s:%d", localIP, *ntpPort)
	_, err = ntp.StartNTPServer(ntpAddr)
	if err != nil {
		log.Fatalf("[ERROR] Failed to start local NTP server: %v", err)
	}
	log.Printf("[NTP] Server running on %s", ntpAddr)

	// Generate QR Code for client node pairing
	qr, err := qrcode.New(wsURL, qrcode.Medium)
	if err != nil {
		log.Fatalf("[ERROR] Failed to generate QR code: %v", err)
	}

	log.Println("[SERVER] Scan this QR code with the smartphone clients to pair:")
	fmt.Println(qr.ToSmallString(false))

	hub := ws.NewHub()
	go hub.Run()

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		ws.ServeWs(hub, w, r)
	})

	// HTTP trigger endpoint to fire all cameras simultaneously
	// HTTP trigger endpoint to fire all cameras simultaneously
	http.HandleFunc("/trigger", func(w http.ResponseWriter, r *http.Request) {
		sessionId, err := hub.TriggerCapture()
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"error":"%s"}`, err.Error())
			return
		}

		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"triggered","session_id":"%s"}`, sessionId)
	})

	serverAddr := fmt.Sprintf(":%d", *port)
	log.Printf("[SERVER] Listening for incoming WebSockets on %s...", serverAddr)
	log.Printf("[SERVER] HTTP Trigger URL: http://%s:%d/trigger", localIP, *port)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Fatalf("[ERROR] ListenAndServe failed: %v", err)
	}
}
