package main

import (
	"net"
	"time"
)

var netDialer = net.Dialer{
	Timeout:   10 * time.Second,
	KeepAlive: 30 * time.Second,
}
