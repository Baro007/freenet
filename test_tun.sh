#!/bin/bash
cat << 'EOF' > /tmp/sing-box-test.json
{
  "log": { "level": "debug" },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "utun9",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "stack": "gvisor",
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "tag": "proxy",
      "server": "127.0.0.1",
      "server_port": 1080
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "tun-in",
        "outbound": "proxy"
      }
    ],
    "auto_detect_interface": true
  }
}
EOF
echo "Config created at /tmp/sing-box-test.json"
