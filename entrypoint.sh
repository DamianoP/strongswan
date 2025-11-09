#!/usr/bin/env bash
set -euo pipefail

echo "=== StrongSwan IKEv2 setup ==="
echo "Server IP: ${VPN_SERVER_IP:-vpn.example.com}"
echo "Users: ${VPN_USERS:-testuser}"

mkdir -p /etc/ipsec.d/private /etc/ipsec.d/certs /etc/ipsec.d/cacerts /etc/strongswan

if [ ! -f /etc/ipsec.d/private/ca-key.pem ]; then
  echo "[+] Generating CA and server certificates..."

  ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca-key.pem
  ipsec pki --self --ca --lifetime 3650 \
    --in /etc/ipsec.d/private/ca-key.pem \
    --type rsa \
    --dn "CN=VPN Root CA" \
    --outform pem > /etc/ipsec.d/cacerts/ca-cert.pem

  ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/server-key.pem
  ipsec pki --pub --in /etc/ipsec.d/private/server-key.pem --type rsa \
    | ipsec pki --issue --lifetime 1825 \
      --cacert /etc/ipsec.d/cacerts/ca-cert.pem \
      --cakey /etc/ipsec.d/private/ca-key.pem \
      --dn "CN=${VPN_SERVER_IP:-vpn.example.com}" \
      --san "${VPN_SERVER_IP:-vpn.example.com}" \
      --flag serverAuth --flag ikeIntermediate \
      --outform pem > /etc/ipsec.d/certs/server-cert.pem
fi

# === strongswan.conf ===
cat > /etc/strongswan/strongswan.conf <<'EOF'
charon {
    load_modular = yes
    install_routes = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}
include strongswan.d/*.conf
EOF

# === ipsec.conf ===
cat > /etc/ipsec.conf <<EOF
config setup
    charondebug="ike 1, knl 1, cfg 0"

conn %default
    keyexchange=ikev2
    ike=aes256-sha2_256-modp1024
    esp=aes256-sha2_256
    rekey=no
    left=%any
    leftid=${VPN_SERVER_IP:-vpn.example.com}
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightsendcert=never
    rightdns=1.1.1.1,8.8.8.8
    eap_identity=%identity

conn ikev2-vpn
    auto=add
EOF

# === ipsec.secrets ===
cat > /etc/ipsec.secrets <<EOF
: RSA server-key.pem
EOF

IFS=',' read -ra ACCOUNTS <<< "$VPN_USERS"
for pair in "${ACCOUNTS[@]}"; do
  user="${pair%%:*}"
  pass="${pair#*:}"
  echo "$user : EAP \"$pass\"" >> /etc/ipsec.secrets
done


echo 1 > /proc/sys/net/ipv4/ip_forward
if command -v sysctl >/dev/null 2>&1; then
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
else
  echo "[WARN] sysctl non trovato, impostato forwarding via /proc"
fi

IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n 1)

if [ -n "$IFACE" ]; then
  echo "[+] Abilitando NAT su $IFACE per la subnet VPN 10.10.10.0/24"
  iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o "$IFACE" -j MASQUERADE
  iptables -A FORWARD -s 10.10.10.0/24 -o "$IFACE" -j ACCEPT
  iptables -A FORWARD -d 10.10.10.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT
else
  echo "[!] Nessuna interfaccia di default trovata, NAT non impostato."
fi

echo "[+] Configuration completed."
echo "[+] Starting StrongSwan..."

ipsec start --nofork
