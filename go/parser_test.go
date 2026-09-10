package main

import (
	"encoding/base64"
	"testing"
)

func TestParseSSFullBase64Form(t *testing.T) {
	payload := base64.RawURLEncoding.EncodeToString([]byte("aes-128-gcm:p@ss@example.com:8388"))
	outbound, err := parseURIToOutbound("ss://" + payload + "#server")
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if outbound["protocol"] != "shadowsocks" {
		t.Fatalf("protocol = %v", outbound["protocol"])
	}
	server := outbound["settings"].(map[string]interface{})["servers"].([]interface{})[0].(map[string]interface{})
	if server["address"] != "example.com" || server["port"] != 8388 || server["password"] != "p@ss" {
		t.Fatalf("unexpected server: %#v", server)
	}
}

func TestParseMalformedURIsReturnErrorsInsteadOfPanicking(t *testing.T) {
	for _, raw := range []string{
		"ss://bm90LWEtY29uZmln",
		"vless://example.com:443",
		"trojan://secret@example.com",
		"vmess://e30",
	} {
		raw := raw
		t.Run(raw, func(t *testing.T) {
			defer func() {
				if recovered := recover(); recovered != nil {
					t.Fatalf("parse panicked: %v", recovered)
				}
			}()
			if _, err := parseURIToOutbound(raw); err == nil {
				t.Fatal("parse succeeded, want error")
			}
		})
	}
}

func TestParseVlessGRPCAndXHTTP(t *testing.T) {
	grpc, err := parseURIToOutbound("vless://id@example.com:443?security=tls&type=grpc&serviceName=svc")
	if err != nil {
		t.Fatalf("gRPC parse failed: %v", err)
	}
	grpcStream := grpc["streamSettings"].(map[string]interface{})
	if grpcStream["network"] != "grpc" {
		t.Fatalf("gRPC network = %v", grpcStream["network"])
	}
	if grpcStream["grpcSettings"].(map[string]interface{})["serviceName"] != "svc" {
		t.Fatalf("unexpected gRPC settings: %#v", grpcStream["grpcSettings"])
	}

	xhttp, err := parseURIToOutbound("vless://id@example.com:443?security=tls&type=xhttp&path=%2Fapi&host=edge.example")
	if err != nil {
		t.Fatalf("XHTTP parse failed: %v", err)
	}
	xhttpStream := xhttp["streamSettings"].(map[string]interface{})
	if xhttpStream["network"] != "splithttp" || xhttpStream["splithttpSettings"] == nil {
		t.Fatalf("unexpected XHTTP stream: %#v", xhttpStream)
	}
}

func TestParseHysteria2UsesPinnedXrayShape(t *testing.T) {
	outbound, err := parseURIToOutbound("hysteria2://secret@example.com:443?sni=edge.example&insecure=1")
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if outbound["protocol"] != "hysteria" {
		t.Fatalf("protocol = %v, want hysteria", outbound["protocol"])
	}
	settings := outbound["settings"].(map[string]interface{})
	if settings["version"] != 2 || settings["address"] != "example.com" || settings["port"] != 443 {
		t.Fatalf("unexpected settings: %#v", settings)
	}
	stream := outbound["streamSettings"].(map[string]interface{})
	if stream["network"] != "hysteria" {
		t.Fatalf("network = %v, want hysteria", stream["network"])
	}
	hy := stream["hysteriaSettings"].(map[string]interface{})
	if hy["version"] != 2 || hy["auth"] != "secret" {
		t.Fatalf("unexpected hysteria settings: %#v", hy)
	}
}

func TestParseVmessRejectsFractionalPort(t *testing.T) {
	payload := base64.RawStdEncoding.EncodeToString([]byte(`{"add":"example.com","port":443.5,"id":"user-id","net":"tcp"}`))
	if _, err := parseURIToOutbound("vmess://" + payload); err == nil {
		t.Fatal("fractional VMess port was accepted")
	}
}
