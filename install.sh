#!/bin/bash
set -e

GRE_NAME="gre1"
THIS_PUBLIC_IP=$(curl -s ipv4.icanhazip.com)

function header() {
  clear
  echo "=========================================="
  echo "   GRE Smart Manager | IPv4 + IPv6 Private "
  echo "=========================================="
  echo "📍 This Server Public IP : $THIS_PUBLIC_IP"
  echo
}

function enable_bbr() {
  echo "🔧 Select TCP Congestion Control:"
  echo "1) BBR (recommended)"
  echo "2) BBR2"
  echo "3) Cubic (default Linux)"
  read -rp "Your choice: " bbr

  case $bbr in
    1) algo="bbr" ;;
    2) algo="bbr2" ;;
    3) algo="cubic" ;;
    *) echo "❌ Invalid choice"; return ;;
  esac

  sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

  cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=$algo
EOF

  sysctl -p >/dev/null
  echo "✅ TCP Congestion Control set to $algo"
}

function create_gre() {
  echo "🌐 Enter Public IP of the server you want to connect (Server Peer):"
  read -rp "> " REMOTE_PUBLIC_IP

  echo "🔹 Enter Private IPv4 for this server (e.g., 10.50.60.1/30):"
  read -rp "> " PRIVATE_IPV4

  echo "🔹 Enter Private IPv6 for this server (e.g., fd00:50:60::1/126):"
  read -rp "> " PRIVATE_IPV6

  echo "🔹 Enter MTU (recommended: 1400):"
  read -rp "> " MTU
  MTU=${MTU:-1400}

  echo
  echo "📋 Configuration Summary:"
  echo "This server      : $THIS_PUBLIC_IP"
  echo "Peer server      : $REMOTE_PUBLIC_IP"
  echo "Private IPv4     : $PRIVATE_IPV4"
  echo "Private IPv6     : $PRIVATE_IPV6"
  echo "MTU              : $MTU"
  echo
  read -rp "Continue? (y/n): " c
  [[ "$c" != "y" ]] && return

  echo "🚀 Creating GRE Tunnel..."

  modprobe ip_gre || true
  ip tunnel del $GRE_NAME 2>/dev/null || true

  ip tunnel add $GRE_NAME mode gre \
    local $THIS_PUBLIC_IP \
    remote $REMOTE_PUBLIC_IP \
    ttl 255

  ip link set $GRE_NAME up
  ip link set $GRE_NAME mtu $MTU

  ip addr add $PRIVATE_IPV4 dev $GRE_NAME
  ip -6 addr add $PRIVATE_IPV6 dev $GRE_NAME

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

  iptables -C INPUT -p gre -j ACCEPT 2>/dev/null || iptables -A INPUT -p gre -j ACCEPT

  echo "✅ GRE Tunnel is UP"
  ip addr show $GRE_NAME
}

function remove_gre() {
  echo "⚠ Removing GRE Tunnel..."
  ip addr flush dev $GRE_NAME 2>/dev/null || true
  ip tunnel del $GRE_NAME 2>/dev/null || true
  echo "🗑 GRE Tunnel removed"
}

while true; do
  header
  echo "1) Create / Rebuild GRE Tunnel"
  echo "2) Remove GRE Tunnel"
  echo "3) Enable TCP BBR / BBR2"
  echo "0) Exit"
  echo
  read -rp "Select an option: " opt

  case $opt in
    1) create_gre ;;
    2) remove_gre ;;
    3) enable_bbr ;;
    0) exit 0 ;;
    *) echo "❌ Invalid option"; sleep 1 ;;
  esac

  echo
  read -rp "Press Enter to continue..."
done
