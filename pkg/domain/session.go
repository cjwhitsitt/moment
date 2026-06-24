package domain

import (
	"encoding/json"
	"time"
)

// SessionStatus defines the current lifecycle state of a capture session
type SessionStatus string

const (
	StatusPending    SessionStatus = "pending"
	StatusUploading  SessionStatus = "uploading"
	StatusProcessing SessionStatus = "processing"
	StatusCompleted  SessionStatus = "completed"
	StatusFailed     SessionStatus = "failed"
)

// Message is the generic container for all JSON-over-WebSocket messages
type Message struct {
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

// RegisterPayload is sent by a client smartphone when pairing
type RegisterPayload struct {
	CameraIndex int    `json:"camera_index"`
	DeviceName  string `json:"device_name"`
}

// RegisterResponse is sent back to the client to confirm pairing
type RegisterResponse struct {
	CameraIndex int    `json:"camera_index"`
	Status      string `json:"status"`
}

// PingPayload is sent by coordinator for heartbeats
type PingPayload struct {
	CoordinatorTimestampMs int64 `json:"coordinator_timestamp_ms"`
}

// PongPayload is sent back by client for heartbeat drift calculation
type PongPayload struct {
	CoordinatorTimestampMs int64 `json:"coordinator_timestamp_ms"`
	ClientTimestampMs      int64 `json:"client_timestamp_ms"`
}

// TriggerPayload is broadcasted by coordinator to trigger cameras at a future sync time
type TriggerPayload struct {
	SessionID      string `json:"session_id"`
	TriggerEpochMs int64  `json:"trigger_epoch_ms"`
}

// StatusUpdatePayload is sent by client to report upload/shutter progress
type StatusUpdatePayload struct {
	SessionID    string `json:"session_id"`
	CameraIndex  int    `json:"camera_index"`
	Status       string `json:"status"` // "capturing" | "uploading" | "uploaded" | "completed" | "failed"
	GifURL       string `json:"gif_url,omitempty"`
	ErrorMessage string `json:"error_message,omitempty"`
}

// ClientNode tracks metadata of a connected camera client
type ClientNode struct {
	Index       int           `json:"index"`
	IPAddress   string        `json:"ip_address"`
	DeviceName  string        `json:"device_name"`
	ConnectedAt time.Time     `json:"connected_at"`
	IsReady     bool          `json:"is_ready"`
	ClockOffset time.Duration `json:"clock_offset"` // Drift calculated via NTP
}

// CaptureSession tracks the status of a local shooting session
type CaptureSession struct {
	SessionID string                  `json:"session_id"`
	Status    SessionStatus           `json:"status"`
	CreatedAt time.Time               `json:"created_at"`
	Frames    map[int]string          `json:"frames"` // Camera index -> Storage URL
	Error     string                  `json:"error,omitempty"`
}
