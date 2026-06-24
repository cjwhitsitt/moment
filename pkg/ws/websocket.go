package ws

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"moment/pkg/domain"

	"github.com/gorilla/websocket"
	"github.com/skip2/go-qrcode"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// For local development and booth setups, allow connections from any origin
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// Hub maintains the set of active client connections and broadcasts messages.
type Hub struct {
	clients    map[int]*Client // Registered camera nodes by camera_index (1-5)
	clientsMu  sync.RWMutex
	register   chan *Client
	unregister chan *Client
}

// Client represents a single paired smartphone connection.
type Client struct {
	Index       int
	Hub         *Hub
	Conn        *websocket.Conn
	Send        chan []byte
	IPAddress   string
	DeviceName  string
	ClockOffset time.Duration
	mu          sync.Mutex
}

// NewHub creates and initializes a new WebSocket Hub.
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[int]*Client),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

// Run starts the Hub orchestration loop.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			// Client registration is handled on successful JSON registration handshake
			log.Printf("[HUB] WebSocket connected from %s", client.IPAddress)

		case client := <-h.unregister:
			h.clientsMu.Lock()
			if client.Index > 0 && h.clients[client.Index] == client {
				delete(h.clients, client.Index)
				log.Printf("[HUB] Unregistered Camera Node %d (%s)", client.Index, client.IPAddress)
			}
			h.clientsMu.Unlock()
			client.Conn.Close()
		}
	}
}

// RegisterClient associates a client with a camera index (1-5) after handshake validation.
func (h *Hub) RegisterClient(client *Client, index int, deviceName string) bool {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if index < 1 || index > 5 {
		log.Printf("[HUB] Rejected registration for invalid camera index %d from %s", index, client.IPAddress)
		return false
	}

	// Unregister any existing client at this index
	if existing, exists := h.clients[index]; exists {
		log.Printf("[HUB] Replacing existing Camera Node %d connection at %s", index, existing.IPAddress)
		existing.Conn.Close()
		delete(h.clients, index)
	}

	client.Index = index
	client.DeviceName = deviceName
	h.clients[index] = client
	log.Printf("[HUB] Successfully paired Camera Node %d (%s, %s)", index, deviceName, client.IPAddress)
	return true
}

// GetClients returns a slice of currently registered clients.
func (h *Hub) GetClients() []domain.ClientNode {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	list := make([]domain.ClientNode, 0, len(h.clients))
	for _, c := range h.clients {
		list = append(list, domain.ClientNode{
			Index:       c.Index,
			IPAddress:   c.IPAddress,
			DeviceName:  c.DeviceName,
			ConnectedAt: time.Now(), // Placeholder or track connected at
			IsReady:     true,
			ClockOffset: c.ClockOffset,
		})
	}
	return list
}

// Broadcast sends a message to all connected and registered clients.
func (h *Hub) Broadcast(event string, data interface{}) {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	rawPayload, err := json.Marshal(data)
	if err != nil {
		log.Printf("[HUB] Error marshaling broadcast data: %v", err)
		return
	}

	msg := domain.Message{
		Event: event,
		Data:  rawPayload,
	}

	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[HUB] Error marshaling Message container: %v", err)
		return
	}

	for _, client := range h.clients {
		select {
		case client.Send <- msgBytes:
		default:
			log.Printf("[HUB] Send buffer full for Camera Node %d at %s. Disconnecting.", client.Index, client.IPAddress)
			h.unregister <- client
		}
	}
}

// WritePump pumps messages from the Hub to the WebSocket connection.
func (c *Client) WritePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.Hub.unregister <- c
	}()
	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued chat messages to the current websocket message.
			n := len(c.Send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.Send)
			}

			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ReadPump pumps messages from the WebSocket connection to the Hub.
func (c *Client) ReadPump() {
	defer func() {
		c.Hub.unregister <- c
	}()
	c.Conn.SetReadLimit(512 * 1024) // limit payloads to 512KB
	c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.Conn.SetPongHandler(func(string) error { c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second)); return nil })

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[CLIENT] Error reading socket: %v", err)
			}
			break
		}

		var msg domain.Message
		if err := json.Unmarshal(message, &msg); err != nil {
			log.Printf("[CLIENT] Error unmarshaling WS message: %v", err)
			continue
		}

		c.handleMessage(msg)
	}
}

// handleMessage routes messages received from client nodes.
func (c *Client) handleMessage(msg domain.Message) {
	switch msg.Event {
	case "client_register":
		var payload domain.RegisterPayload
		if err := json.Unmarshal(msg.Data, &payload); err != nil {
			log.Printf("[CLIENT] Invalid registration payload: %v", err)
			return
		}

		success := c.Hub.RegisterClient(c, payload.CameraIndex, payload.DeviceName)
		resp := domain.RegisterResponse{
			CameraIndex: payload.CameraIndex,
			Status:      "failed",
		}
		if success {
			resp.Status = "ready"
		}

		rawResp, _ := json.Marshal(resp)
		replyMsg := domain.Message{
			Event: "client_registered",
			Data:  rawResp,
		}
		replyBytes, _ := json.Marshal(replyMsg)
		c.Send <- replyBytes

	case "pong":
		var payload domain.PongPayload
		if err := json.Unmarshal(msg.Data, &payload); err != nil {
			return
		}
		// RTT calculation and clock drift tracking
		clientTime := time.UnixMilli(payload.ClientTimestampMs)
		coordTime := time.Now()
		// Simple drift calculation: clientTime - coordTime
		drift := clientTime.Sub(coordTime)

		c.mu.Lock()
		c.ClockOffset = drift
		c.mu.Unlock()
		log.Printf("[CLIENT] Camera Node %d clock offset calibrated: %v", c.Index, drift)

	case "status_update":
		var payload domain.StatusUpdatePayload
		if err := json.Unmarshal(msg.Data, &payload); err != nil {
			return
		}
		log.Printf("[CLIENT] Session %s Node %d status updated: %s", payload.SessionID, payload.CameraIndex, payload.Status)

		if payload.Status == "completed" && payload.GifURL != "" {
			// Print sharing QR code
			log.Println("==================================================")
			log.Printf("[COORDINATOR] Stitching Complete for Session: %s", payload.SessionID)
			log.Printf("[COORDINATOR] Guest GIF URL: %s", payload.GifURL)
			log.Println("==================================================")

			qr, err := qrcode.New(payload.GifURL, qrcode.Medium)
			if err == nil {
				fmt.Println(qr.ToSmallString(false))
			} else {
				log.Printf("[ERROR] Failed to generate guest QR code: %v", err)
			}
		}
	}
}

// ServeWs handles WebSocket upgrade requests from the peer.
func ServeWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[HTTP] Error upgrading to WebSocket: %v", err)
		return
	}

	client := &Client{
		Hub:       hub,
		Conn:      conn,
		Send:      make(chan []byte, 256),
		IPAddress: r.RemoteAddr,
	}

	client.Hub.register <- client

	// Start read/write pumps in separate goroutines
	go client.WritePump()
	go client.ReadPump()
}
