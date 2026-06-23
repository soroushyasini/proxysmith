package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"strings"
)

func parseURIToOutbound(uri string) (map[string]interface{}, error) {
	// strip fragment (remark)
	if idx := strings.Index(uri, "#"); idx != -1 {
		uri = uri[:idx]
	}

	u, err := url.Parse(uri)
	if err != nil {
		return nil, fmt.Errorf("url parse: %w", err)
	}

	switch u.Scheme {
	case "ss":
		return parseSS(u)
	case "vless":
		return parseVless(u)
	case "vmess":
		return parseVmess(uri)
	case "trojan":
		return parseTrojan(u)
	default:
		return nil, fmt.Errorf("unsupported scheme: %s", u.Scheme)
	}
}

// ── Shadowsocks ───────────────────────────────────────────────────────────────
func parseSS(u *url.URL) (map[string]interface{}, error) {
	host := u.Hostname()
	port := u.Port()

	// userinfo is base64(method:password)
	userInfo := u.User.Username()
	// sometimes it's already decoded (method:pass directly)
	decoded, err := base64.StdEncoding.DecodeString(userInfo)
	if err != nil {
		// try URL-safe base64
		decoded, err = base64.RawURLEncoding.DecodeString(userInfo)
		if err != nil {
			// assume it's already plaintext method:pass
			decoded = []byte(userInfo)
		}
	}

	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return nil, fmt.Errorf("ss: cannot parse method:password from %q", string(decoded))
	}
	method, password := parts[0], parts[1]

	portNum := 0
	fmt.Sscanf(port, "%d", &portNum)

	return map[string]interface{}{
		"protocol": "shadowsocks",
		"settings": map[string]interface{}{
			"servers": []interface{}{
				map[string]interface{}{
					"address":  host,
					"port":     portNum,
					"method":   method,
					"password": password,
				},
			},
		},
		"streamSettings": map[string]interface{}{
			"network": "tcp",
		},
		"tag": "proxy",
	}, nil
}

// ── VLESS ─────────────────────────────────────────────────────────────────────
func parseVless(u *url.URL) (map[string]interface{}, error) {
	uuid := u.User.Username()
	host := u.Hostname()
	port := u.Port()
	q := u.Query()

	portNum := 0
	fmt.Sscanf(port, "%d", &portNum)

	network := q.Get("type")
	if network == "" {
		network = "tcp"
	}
	security := q.Get("security")
	if security == "" {
		security = "none"
	}
	flow := q.Get("flow")

	streamSettings := map[string]interface{}{
		"network":  network,
		"security": security,
	}

	switch security {
	case "tls":
		tlsSettings := map[string]interface{}{}
		if sni := q.Get("sni"); sni != "" {
			tlsSettings["serverName"] = sni
		}
		if fp := q.Get("fp"); fp != "" {
			tlsSettings["fingerprint"] = fp
		}
		streamSettings["tlsSettings"] = tlsSettings

	case "reality":
		realitySettings := map[string]interface{}{
			"fingerprint": q.Get("fp"),
			"serverName":  q.Get("sni"),
			"publicKey":   q.Get("pbk"),
			"shortId":     q.Get("sid"),
		}
		streamSettings["realitySettings"] = realitySettings
	}

	switch network {
	case "ws":
		wsSettings := map[string]interface{}{}
		if path := q.Get("path"); path != "" {
			wsSettings["path"] = path
		}
		if host2 := q.Get("host"); host2 != "" {
			wsSettings["headers"] = map[string]interface{}{"Host": host2}
		}
		streamSettings["wsSettings"] = wsSettings
	case "tcp":
		streamSettings["tcpSettings"] = map[string]interface{}{
			"header": map[string]interface{}{"type": "none"},
		}
	}

	userObj := map[string]interface{}{
		"id":         uuid,
		"encryption": "none",
	}
	if flow != "" {
		userObj["flow"] = flow
	}

	return map[string]interface{}{
		"protocol": "vless",
		"settings": map[string]interface{}{
			"vnext": []interface{}{
				map[string]interface{}{
					"address": host,
					"port":    portNum,
					"users":   []interface{}{userObj},
				},
			},
		},
		"streamSettings": streamSettings,
		"tag":            "proxy",
	}, nil
}

// ── VMess ─────────────────────────────────────────────────────────────────────
func parseVmess(raw string) (map[string]interface{}, error) {
	b64 := strings.TrimPrefix(raw, "vmess://")
	// pad if needed
	for len(b64)%4 != 0 {
		b64 += "="
	}
	decoded, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		decoded, err = base64.RawStdEncoding.DecodeString(strings.TrimPrefix(raw, "vmess://"))
		if err != nil {
			return nil, fmt.Errorf("vmess base64: %w", err)
		}
	}

	var v map[string]interface{}
	if err := json.Unmarshal(decoded, &v); err != nil {
		return nil, fmt.Errorf("vmess json: %w", err)
	}

	host, _ := v["add"].(string)
	portRaw := v["port"]
	var portNum int
	switch p := portRaw.(type) {
	case float64:
		portNum = int(p)
	case string:
		fmt.Sscanf(p, "%d", &portNum)
	}

	uuid, _ := v["id"].(string)
	alterId := 0
	if aid, ok := v["aid"].(float64); ok {
		alterId = int(aid)
	}
	network, _ := v["net"].(string)
	if network == "" {
		network = "tcp"
	}
	security, _ := v["tls"].(string)

	streamSettings := map[string]interface{}{
		"network":  network,
		"security": security,
	}
	if security == "tls" {
		tlsSettings := map[string]interface{}{}
		if sni, ok := v["sni"].(string); ok && sni != "" {
			tlsSettings["serverName"] = sni
		}
		streamSettings["tlsSettings"] = tlsSettings
	}
	if network == "ws" {
		wsSettings := map[string]interface{}{}
		if path, ok := v["path"].(string); ok {
			wsSettings["path"] = path
		}
		if h, ok := v["host"].(string); ok && h != "" {
			wsSettings["headers"] = map[string]interface{}{"Host": h}
		}
		streamSettings["wsSettings"] = wsSettings
	}

	return map[string]interface{}{
		"protocol": "vmess",
		"settings": map[string]interface{}{
			"vnext": []interface{}{
				map[string]interface{}{
					"address": host,
					"port":    portNum,
					"users": []interface{}{
						map[string]interface{}{
							"id":       uuid,
							"alterId":  alterId,
							"security": "auto",
						},
					},
				},
			},
		},
		"streamSettings": streamSettings,
		"tag":            "proxy",
	}, nil
}

// ── Trojan ────────────────────────────────────────────────────────────────────
func parseTrojan(u *url.URL) (map[string]interface{}, error) {
	password := u.User.Username()
	host, portStr, _ := net.SplitHostPort(u.Host)
	portNum := 0
	fmt.Sscanf(portStr, "%d", &portNum)
	q := u.Query()

	streamSettings := map[string]interface{}{
		"network":  "tcp",
		"security": "tls",
	}
	tlsSettings := map[string]interface{}{}
	if sni := q.Get("sni"); sni != "" {
		tlsSettings["serverName"] = sni
	}
	if fp := q.Get("fp"); fp != "" {
		tlsSettings["fingerprint"] = fp
	}
	streamSettings["tlsSettings"] = tlsSettings

	return map[string]interface{}{
		"protocol": "trojan",
		"settings": map[string]interface{}{
			"servers": []interface{}{
				map[string]interface{}{
					"address":  host,
					"port":     portNum,
					"password": password,
				},
			},
		},
		"streamSettings": streamSettings,
		"tag":            "proxy",
	}, nil
}
