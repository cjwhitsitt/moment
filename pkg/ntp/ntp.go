package ntp

import (
	"encoding/binary"
	"log"
	"net"
	"time"
)

// NTP server epoch is Jan 1, 1900. Unix epoch is Jan 1, 1970.
// Offset in seconds is 2208988800.
const ntpEpochOffset = 2208988800

type NTPServer struct {
	conn *net.UDPConn
}

func StartNTPServer(addr string) (*NTPServer, error) {
	udpAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return nil, err
	}
	conn, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		return nil, err
	}

	server := &NTPServer{conn: conn}
	go server.serve()
	return server, nil
}

func (n *NTPServer) serve() {
	buf := make([]byte, 48)
	for {
		numBytes, src, err := n.conn.ReadFromUDP(buf)
		if err != nil {
			// Silently break/return if socket is closed
			return
		}
		if numBytes < 48 {
			continue
		}

		// Read client transmit timestamp (bytes 40-47)
		transmitSec := binary.BigEndian.Uint32(buf[40:44])
		transmitFrac := binary.BigEndian.Uint32(buf[44:48])

		// Prepare reply packet
		reply := make([]byte, 48)
		// Leap Indicator (0), Version (4), Mode (4 = server) -> 00 100 100 = 0x24
		reply[0] = 0x24
		// Stratum 1 (primary reference)
		reply[1] = 1
		// Poll interval (6 = 64 seconds)
		reply[2] = 6
		// Precision (-20)
		reply[3] = 0xEC

		// Reference Identifier: "LOCL"
		copy(reply[12:16], []byte("LOCL"))

		now := time.Now()
		ntpSec, ntpFrac := toNTPTime(now)

		// Reference Timestamp (when system clock was last set)
		binary.BigEndian.PutUint32(reply[16:20], ntpSec)
		binary.BigEndian.PutUint32(reply[20:24], ntpFrac)

		// Origin Timestamp (client transmit timestamp copied back)
		binary.BigEndian.PutUint32(reply[24:28], transmitSec)
		binary.BigEndian.PutUint32(reply[28:32], transmitFrac)

		// Receive Timestamp (when server got packet)
		binary.BigEndian.PutUint32(reply[32:36], ntpSec)
		binary.BigEndian.PutUint32(reply[36:40], ntpFrac)

		// Transmit Timestamp (when server sent reply)
		binary.BigEndian.PutUint32(reply[40:44], ntpSec)
		binary.BigEndian.PutUint32(reply[44:48], ntpFrac)

		_, err = n.conn.WriteToUDP(reply, src)
		if err != nil {
			log.Printf("[NTP] Error writing UDP response to %v: %v", src, err)
		}
	}
}

func toNTPTime(t time.Time) (uint32, uint32) {
	sec := uint32(t.Unix() + ntpEpochOffset)
	nanosec := t.Nanosecond()
	frac := uint32((float64(nanosec) / 1e9) * 4294967296.0)
	return sec, frac
}

func (n *NTPServer) Close() {
	n.conn.Close()
}
