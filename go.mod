module moment

go 1.18

require (
	github.com/gorilla/websocket v1.5.3
	github.com/hashicorp/mdns v1.0.5
	github.com/skip2/go-qrcode v0.0.0-20200617195104-da1b6568686e
)

require (
	github.com/miekg/dns v1.1.72 // indirect
	golang.org/x/mod v0.31.0 // indirect
	golang.org/x/net v0.48.0 // indirect
	golang.org/x/sys v0.39.0 // indirect
	golang.org/x/tools v0.40.0 // indirect
)

replace (
	golang.org/x/mod => golang.org/x/mod v0.10.0
	golang.org/x/net => golang.org/x/net v0.10.0
	golang.org/x/sys => golang.org/x/sys v0.10.0
	golang.org/x/tools => golang.org/x/tools v0.9.0
)
