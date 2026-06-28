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
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// Hub maintains the set of active client connections and broadcasts messages.
type Hub struct {
	clients       map[int]*Client // Registered camera nodes by camera_index (1-10)
	operators     map[*Client]bool // Registered operator connections
	clientsMu     sync.RWMutex
	register      chan *Client
	unregister    chan *Client
	activeSession *domain.ActiveSessionStatus // Track active session status
}

// Client represents a single paired smartphone connection.
type Client struct {
	Index        int
	Hub          *Hub
	Conn         *websocket.Conn
	Send         chan []byte
	IPAddress    string
	DeviceName   string
	ClockOffset  time.Duration
	BatteryLevel int
	State        string // "idle" | "capturing" | "uploading" | "uploaded" | "failed"
	IsOperator   bool
	mu           sync.Mutex
}

// NewHub creates and initializes a new WebSocket Hub.
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[int]*Client),
		operators:  make(map[*Client]bool),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

// Run starts the Hub orchestration loop.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			log.Printf("[HUB] WebSocket connected from %s", client.IPAddress)

		case client := <-h.unregister:
			h.clientsMu.Lock()
			if client.IsOperator {
				delete(h.operators, client)
				log.Printf("[HUB] Unregistered Operator Connection (%s)", client.IPAddress)
			} else if client.Index > 0 && h.clients[client.Index] == client {
				delete(h.clients, client.Index)
				log.Printf("[HUB] Unregistered Camera Node %d (%s)", client.Index, client.IPAddress)
				go h.SyncDashboard()
			}
			h.clientsMu.Unlock()
			client.Conn.Close()
		}
	}
}

// RegisterClient associates a client with a camera index (1-10) after handshake validation.
func (h *Hub) RegisterClient(client *Client, index int, deviceName string) bool {
	h.clientsMu.Lock()
	defer h.clientsMu.Unlock()

	if index < 1 || index > 10 {
		log.Printf("[HUB] Rejected registration for invalid camera index %d from %s", index, client.IPAddress)
		return false
	}

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
			ConnectedAt: time.Now(),
			IsReady:     true,
			ClockOffset: c.ClockOffset,
		})
	}
	return list
}

// TriggerCapture triggers a synchronized capture session across all registered clients.
func (h *Hub) TriggerCapture() (string, error) {
	h.clientsMu.Lock()
	n := len(h.clients)
	h.clientsMu.Unlock()

	if n < 3 || n > 10 {
		return "", fmt.Errorf("invalid camera count: %d. Must be between 3 and 10", n)
	}

	sessionId := fmt.Sprintf("session-%d", time.Now().UnixNano())
	triggerTime := time.Now().Add(500 * time.Millisecond).UnixMilli()

	h.clientsMu.Lock()
	h.activeSession = &domain.ActiveSessionStatus{
		SessionID: sessionId,
		Status:    "triggered",
	}
	h.clientsMu.Unlock()

	log.Printf("[TRIGGER] Broadcasting capture trigger for Session: %s at time: %d with %d expected frames", sessionId, triggerTime, n)

	h.Broadcast("capture_trigger", domain.TriggerPayload{
		SessionID:      sessionId,
		TriggerEpochMs: triggerTime,
		ExpectedFrames: n,
	})

	go h.SyncDashboard()

	return sessionId, nil
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

// SyncDashboard gathers the current state and pushes it to all registered operators.
func (h *Hub) SyncDashboard() {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()

	if len(h.operators) == 0 {
		return
	}

	cameras := make([]domain.CameraNodeStatus, 0, len(h.clients))
	for _, c := range h.clients {
		c.mu.Lock()
		offsetMs := float64(c.ClockOffset.Milliseconds())
		battery := c.BatteryLevel
		state := c.State
		if state == "" {
			state = "idle"
		}
		cameras = append(cameras, domain.CameraNodeStatus{
			CameraIndex:   c.Index,
			DeviceName:    c.DeviceName,
			State:         state,
			BatteryLevel:  battery,
			ClockOffsetMs: offsetMs,
			IsReady:       true,
		})
		c.mu.Unlock()
	}

	syncPayload := domain.DashboardSyncPayload{
		Cameras:       cameras,
		ActiveSession: h.activeSession,
	}

	rawPayload, err := json.Marshal(syncPayload)
	if err != nil {
		log.Printf("[HUB] Error marshaling dashboard sync data: %v", err)
		return
	}

	msg := domain.Message{
		Event: "dashboard_sync",
		Data:  rawPayload,
	}

	msgBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("[HUB] Error marshaling Message container: %v", err)
		return
	}

	for op := range h.operators {
		select {
		case op.Send <- msgBytes:
		default:
			log.Printf("[HUB] Operator buffer full. Unregistering operator.")
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
	c.Conn.SetReadLimit(512 * 1024)
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
			c.mu.Lock()
			c.State = "idle"
			c.mu.Unlock()
		}

		rawResp, _ := json.Marshal(resp)
		replyMsg := domain.Message{
			Event: "client_registered",
			Data:  rawResp,
		}
		replyBytes, _ := json.Marshal(replyMsg)
		c.Send <- replyBytes
		go c.Hub.SyncDashboard()

	case "operator_register":
		c.IsOperator = true
		c.Hub.clientsMu.Lock()
		c.Hub.operators[c] = true
		c.Hub.clientsMu.Unlock()

		resp := domain.OperatorRegisterResponse{
			Status: "ready",
		}
		rawResp, _ := json.Marshal(resp)
		replyMsg := domain.Message{
			Event: "operator_registered",
			Data:  rawResp,
		}
		replyBytes, _ := json.Marshal(replyMsg)
		c.Send <- replyBytes

		go c.Hub.SyncDashboard()
		log.Printf("[HUB] Operator registered from %s", c.IPAddress)

	case "pong":
		var payload domain.PongPayload
		if err := json.Unmarshal(msg.Data, &payload); err != nil {
			return
		}
		clientTime := time.UnixMilli(payload.ClientTimestampMs)
		coordTime := time.Now()
		drift := clientTime.Sub(coordTime)

		c.mu.Lock()
		c.ClockOffset = drift
		c.mu.Unlock()
		log.Printf("[CLIENT] Camera Node %d clock offset calibrated: %v", c.Index, drift)
		go c.Hub.SyncDashboard()

	case "status_update":
		var payload domain.StatusUpdatePayload
		if err := json.Unmarshal(msg.Data, &payload); err != nil {
			return
		}
		c.mu.Lock()
		c.State = payload.Status
		c.BatteryLevel = payload.BatteryLevel
		c.ClockOffset = time.Duration(payload.ClockOffsetMs * float64(time.Millisecond))
		c.mu.Unlock()

		log.Printf("[CLIENT] Session %s Node %d status updated: %s (Battery: %d%%, Offset: %.2fms)", payload.SessionID, payload.CameraIndex, payload.Status, payload.BatteryLevel, payload.ClockOffsetMs)

		c.Hub.clientsMu.Lock()
		if c.Hub.activeSession != nil && c.Hub.activeSession.SessionID == payload.SessionID {
			if payload.Status == "completed" {
				c.Hub.activeSession.Status = "done"
			} else if payload.Status == "failed" {
				c.Hub.activeSession.Status = "failed"
			}
		}
		c.Hub.clientsMu.Unlock()

		go c.Hub.SyncDashboard()

	case "operator_capture_trigger":
		if c.IsOperator {
			sessionId, err := c.Hub.TriggerCapture()
			if err != nil {
				log.Printf("[OPERATOR] Failed to trigger capture: %v", err)
				resp := map[string]interface{}{"event": "error", "error": err.Error()}
				respBytes, _ := json.Marshal(resp)
				c.Send <- respBytes
			} else {
				log.Printf("[OPERATOR] Capturing session %s triggered successfully", sessionId)
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

	go client.WritePump()
	go client.ReadPump()
}
