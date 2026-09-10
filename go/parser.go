package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"net/url"
	"strconv"
	"strings"
)

func parseURIToOutbound(raw string) (map[string]interface{}, error) {
	if index := strings.IndexByte(raw, '#'); index >= 0 {
		raw = raw[:index]
	}
	if strings.HasPrefix(strings.ToLower(raw), "ss://") {
		return parseSS(raw)
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, fmt.Errorf("URL parse: %w", err)
	}
	switch strings.ToLower(u.Scheme) {
	case "vless":
		return parseVless(u)
	case "vmess":
		return parseVmess(raw)
	case "trojan":
		return parseTrojan(u)
	case "hysteria2", "hy2":
		return parseHysteria2(u)
	default:
		return nil, fmt.Errorf("unsupported scheme: %s", u.Scheme)
	}
}

func parseSS(raw string) (map[string]interface{}, error) {
	payload := raw[strings.Index(raw, "://")+3:]
	var method, password, host string
	var port int
	if !strings.Contains(payload, "@") {
		decoded, err := decodeBase64(strings.SplitN(payload, "?", 2)[0])
		if err != nil {
			return nil, fmt.Errorf("ss: invalid full base64 payload: %w", err)
		}
		at := strings.LastIndex(decoded, "@")
		if at < 1 {
			return nil, fmt.Errorf("ss: decoded payload is missing server")
		}
		credentials, address := decoded[:at], decoded[at+1:]
		method, password, err = splitCredentials(credentials, "ss")
		if err != nil {
			return nil, err
		}
		host, port, err = splitAddress(address, "ss")
		if err != nil {
			return nil, err
		}
	} else {
		u, err := url.Parse(raw)
		if err != nil || u.User == nil {
			return nil, fmt.Errorf("ss: missing credentials")
		}
		credentials := u.User.Username()
		if inlinePassword, ok := u.User.Password(); ok {
			credentials += ":" + inlinePassword
		} else if decoded, decodeErr := decodeBase64(credentials); decodeErr == nil {
			credentials = decoded
		}
		method, password, err = splitCredentials(credentials, "ss")
		if err != nil {
			return nil, err
		}
		host, port, err = validatedHostPort(u, "ss")
		if err != nil {
			return nil, err
		}
	}
	return map[string]interface{}{
		"protocol": "shadowsocks",
		"settings": map[string]interface{}{"servers": []interface{}{map[string]interface{}{
			"address": host, "port": port, "method": method, "password": password,
		}}},
		"streamSettings": map[string]interface{}{"network": "tcp"},
		"tag":            "proxy",
	}, nil
}

func parseVless(u *url.URL) (map[string]interface{}, error) {
	if u.User == nil || u.User.Username() == "" {
		return nil, fmt.Errorf("vless: missing user ID")
	}
	host, port, err := validatedHostPort(u, "vless")
	if err != nil {
		return nil, err
	}
	query := u.Query()
	stream, err := buildStreamSettings(query.Get("type"), query.Get("security"), query, host)
	if err != nil {
		return nil, fmt.Errorf("vless: %w", err)
	}
	user := map[string]interface{}{"id": u.User.Username(), "encryption": "none"}
	if flow := query.Get("flow"); flow != "" {
		user["flow"] = flow
	}
	return map[string]interface{}{
		"protocol": "vless",
		"settings": map[string]interface{}{"vnext": []interface{}{map[string]interface{}{
			"address": host, "port": port, "users": []interface{}{user},
		}}},
		"streamSettings": stream,
		"tag":            "proxy",
	}, nil
}

func parseVmess(raw string) (map[string]interface{}, error) {
	decoded, err := decodeBase64(raw[strings.Index(raw, "://")+3:])
	if err != nil {
		return nil, fmt.Errorf("vmess base64: %w", err)
	}
	var value map[string]interface{}
	if err := json.Unmarshal([]byte(decoded), &value); err != nil {
		return nil, fmt.Errorf("vmess JSON: %w", err)
	}
	host, _ := value["add"].(string)
	userID, _ := value["id"].(string)
	port, err := integerValue(value["port"])
	if host == "" || userID == "" || err != nil || port < 1 || port > 65535 {
		return nil, fmt.Errorf("vmess: missing or invalid address, port, or user ID")
	}
	query := url.Values{}
	copyStringValue(query, value, "net", "type")
	copyStringValue(query, value, "tls", "security")
	for _, key := range []string{"sni", "host", "path", "serviceName", "fp", "pbk", "sid", "authority"} {
		copyStringValue(query, value, key, key)
	}
	stream, err := buildStreamSettings(query.Get("type"), query.Get("security"), query, host)
	if err != nil {
		return nil, fmt.Errorf("vmess: %w", err)
	}
	alterID, _ := integerValue(value["aid"])
	return map[string]interface{}{
		"protocol": "vmess",
		"settings": map[string]interface{}{"vnext": []interface{}{map[string]interface{}{
			"address": host, "port": port, "users": []interface{}{map[string]interface{}{
				"id": userID, "alterId": alterID, "security": "auto",
			}},
		}}},
		"streamSettings": stream,
		"tag":            "proxy",
	}, nil
}

func parseTrojan(u *url.URL) (map[string]interface{}, error) {
	if u.User == nil || u.User.Username() == "" {
		return nil, fmt.Errorf("trojan: missing password")
	}
	host, port, err := validatedHostPort(u, "trojan")
	if err != nil {
		return nil, err
	}
	query := u.Query()
	network := query.Get("type")
	security := query.Get("security")
	if security == "" {
		security = "tls"
	}
	stream, err := buildStreamSettings(network, security, query, host)
	if err != nil {
		return nil, fmt.Errorf("trojan: %w", err)
	}
	return map[string]interface{}{
		"protocol": "trojan",
		"settings": map[string]interface{}{"servers": []interface{}{map[string]interface{}{
			"address": host, "port": port, "password": userInfoValue(u.User),
		}}},
		"streamSettings": stream,
		"tag":            "proxy",
	}, nil
}

func parseHysteria2(u *url.URL) (map[string]interface{}, error) {
	if u.User == nil || u.User.Username() == "" {
		return nil, fmt.Errorf("hysteria2: missing authentication secret")
	}
	host, port, err := validatedHostPort(u, "hysteria2")
	if err != nil {
		return nil, err
	}
	query := u.Query()
	tls := map[string]interface{}{"serverName": firstNonEmpty(query.Get("sni"), host)}
	if parseBool(query.Get("insecure")) {
		tls["allowInsecure"] = true
	}
	return map[string]interface{}{
		"protocol": "hysteria",
		"settings": map[string]interface{}{"version": 2, "address": host, "port": port},
		"streamSettings": map[string]interface{}{
			"network": "hysteria", "security": "tls", "tlsSettings": tls,
			"hysteriaSettings": map[string]interface{}{"version": 2, "auth": userInfoValue(u.User)},
		},
		"tag": "proxy",
	}, nil
}

func buildStreamSettings(network, security string, query url.Values, host string) (map[string]interface{}, error) {
	if network == "" {
		network = "tcp"
	}
	switch network {
	case "xhttp", "splithttp":
		network = "splithttp"
	case "tcp", "raw", "ws", "grpc", "httpupgrade":
	default:
		return nil, fmt.Errorf("unsupported transport %q", network)
	}
	if network == "raw" {
		network = "tcp"
	}
	if security == "" {
		security = "none"
	}
	if security != "none" && security != "tls" && security != "reality" {
		return nil, fmt.Errorf("unsupported security %q", security)
	}
	stream := map[string]interface{}{"network": network, "security": security}
	serverName := firstNonEmpty(query.Get("sni"), host)
	if security == "tls" {
		settings := map[string]interface{}{"serverName": serverName}
		if fingerprint := query.Get("fp"); fingerprint != "" {
			settings["fingerprint"] = fingerprint
		}
		if parseBool(query.Get("allowInsecure")) || parseBool(query.Get("insecure")) {
			settings["allowInsecure"] = true
		}
		stream["tlsSettings"] = settings
	} else if security == "reality" {
		if query.Get("pbk") == "" {
			return nil, fmt.Errorf("Reality public key is missing")
		}
		stream["realitySettings"] = map[string]interface{}{
			"serverName": serverName, "fingerprint": firstNonEmpty(query.Get("fp"), "chrome"),
			"publicKey": query.Get("pbk"), "shortId": query.Get("sid"), "spiderX": query.Get("spx"),
		}
	}
	switch network {
	case "ws":
		settings := map[string]interface{}{"path": firstNonEmpty(query.Get("path"), "/")}
		if headerHost := query.Get("host"); headerHost != "" {
			settings["headers"] = map[string]interface{}{"Host": headerHost}
		}
		stream["wsSettings"] = settings
	case "grpc":
		settings := map[string]interface{}{"serviceName": firstNonEmpty(query.Get("serviceName"), query.Get("path"))}
		if authority := query.Get("authority"); authority != "" {
			settings["authority"] = authority
		}
		stream["grpcSettings"] = settings
	case "splithttp":
		settings := map[string]interface{}{"path": firstNonEmpty(query.Get("path"), "/")}
		if headerHost := query.Get("host"); headerHost != "" {
			settings["host"] = headerHost
		}
		stream["splithttpSettings"] = settings
	case "httpupgrade":
		stream["httpupgradeSettings"] = map[string]interface{}{"path": firstNonEmpty(query.Get("path"), "/"), "host": firstNonEmpty(query.Get("host"), serverName)}
	case "tcp":
		stream["tcpSettings"] = map[string]interface{}{"header": map[string]interface{}{"type": "none"}}
	}
	return stream, nil
}

func validatedHostPort(u *url.URL, scheme string) (string, int, error) {
	host := u.Hostname()
	port, err := strconv.Atoi(u.Port())
	if host == "" || err != nil || port < 1 || port > 65535 {
		return "", 0, fmt.Errorf("%s: missing or invalid host and port", scheme)
	}
	return host, port, nil
}

func splitAddress(address, scheme string) (string, int, error) {
	u, err := url.Parse(scheme + "://" + address)
	if err != nil {
		return "", 0, fmt.Errorf("%s: invalid server address", scheme)
	}
	return validatedHostPort(u, scheme)
}

func splitCredentials(value, scheme string) (string, string, error) {
	parts := strings.SplitN(value, ":", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("%s: credentials must contain method and password", scheme)
	}
	return parts[0], parts[1], nil
}

func decodeBase64(value string) (string, error) {
	for _, encoding := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.URLEncoding, base64.RawURLEncoding} {
		if decoded, err := encoding.DecodeString(value); err == nil {
			return string(decoded), nil
		}
	}
	return "", fmt.Errorf("invalid base64")
}

func integerValue(value interface{}) (int, error) {
	switch typed := value.(type) {
	case float64:
		if math.Trunc(typed) != typed {
			return 0, fmt.Errorf("integer contains a fractional value")
		}
		return int(typed), nil
	case string:
		return strconv.Atoi(typed)
	case nil:
		return 0, fmt.Errorf("missing integer")
	default:
		return 0, fmt.Errorf("invalid integer")
	}
}

func copyStringValue(values url.Values, source map[string]interface{}, sourceKey, destinationKey string) {
	if value, ok := source[sourceKey].(string); ok && value != "" {
		values.Set(destinationKey, value)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func parseBool(value string) bool {
	switch strings.ToLower(value) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}

func userInfoValue(user *url.Userinfo) string {
	value := user.Username()
	if password, ok := user.Password(); ok {
		value += ":" + password
	}
	return value
}
