package mdns

import (
	"fmt"
	"net"
	"os"

	"github.com/hashicorp/mdns"
)

type Advertiser struct {
	server *mdns.Server
}

func StartAdvertiser(port int) (*Advertiser, error) {
	host, err := os.Hostname()
	if err != nil {
		host = "moment-coordinator"
	}

	var ip net.IP

	// Prioritize querying network interfaces for a non-loopback IPv4 address
	addrs, err := net.InterfaceAddrs()
	if err == nil {
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
				if ipnet.IP.To4() != nil {
					ip = ipnet.IP
					break
				}
			}
		}
	}

	// Fallback to hostname DNS lookup if no active interfaces were resolved
	if ip == nil {
		ips, err := net.LookupIP(host)
		if err == nil && len(ips) > 0 {
			for _, lookupIP := range ips {
				if !lookupIP.IsLoopback() && lookupIP.To4() != nil {
					ip = lookupIP
					break
				}
			}
		}
	}

	// Ultimate fallback to loopback
	if ip == nil {
		ip = net.IPv4(127, 0, 0, 1)
	}

	service, err := mdns.NewMDNSService(
		"moment-coordinator",
		"_moment-coord._tcp",
		"",
		"",
		port,
		[]net.IP{ip},
		[]string{"path=/ws"},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create mDNS service: %w", err)
	}

	server, err := mdns.NewServer(&mdns.Config{Zone: service})
	if err != nil {
		return nil, fmt.Errorf("failed to start mDNS server: %w", err)
	}

	return &Advertiser{server: server}, nil
}

func (a *Advertiser) Stop() {
	if a.server != nil {
		a.server.Shutdown()
	}
}
