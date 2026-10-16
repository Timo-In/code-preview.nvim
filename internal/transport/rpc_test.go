package transport

import (
	"net"
	"testing"
	"time"
)

func TestClientReportsRPCDisconnect(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()

	accepted := make(chan struct{})
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		close(accepted)
		_ = conn.Close()
	}()

	client, err := Connect(listener.Addr().String())
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer client.Close()
	<-accepted

	select {
	case <-client.Disconnected():
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for RPC disconnect")
	}
}
