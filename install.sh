#!/bin/bash
set -e

GRE_NAME="gre1"
THIS_PUBLIC_IP=$(curl -s ipv4.icanhazip.com)

function header() {
  clear
  echo "=========================================="
  echo "   GRE Smart Manager | IPv4 + IPv6 Private "
  echo "=========================================="
  echo "📍 Public IP این سرور : $THIS_PUBLIC_IP"
  echo
}

function enable_bbr() {
  echo "🔧 انتخاب الگوریتم TCP:"
  echo "1) BBR (پیشنهادی)"
  echo "2) BBR2"
  echo "3) Cubic"
  read -rp "انتخاب شما: " bbr

  case $bbr in
    1) algo="bbr" ;;
    2) algo="bbr2" ;;
    3) algo="cubic" ;;
    *) echo "❌ انتخاب نامعتبر"; return ;;
  esac

  sed -i '/net.core.default_qdisc/d;/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

  cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=$algo
EOF

  sysctl -p >/dev/null
  echo "✅ TCP روی $algo تنظیم شد"
}

function create_gre() {
  echo "🌐 IP پابلیک سروری که می‌خوای بهش وصل بشی (Server Peer):"
  read -rp "> " REMOTE_PUBLIC_IP

  echo "🔹 IPv4 پرایوت برای همین سرور (مثال: 10.50.60.1/30):"
  read -rp "> " PRIVATE_IPV4

  echo "🔹 IPv6 پرایوت برای همین سرور (مثال: fd00:50:60::1/126):"
  read -rp "> " PRIVATE_IPV6

  echo "🔹 MTU موردنظر (پیشنهادی: 1400):"
  read -rp "> " MTU
  MTU=${MTU:-1400}

  echo
  echo "📋 خلاصه تنظیمات:"
  echo "این سرور       : $THIS_PUBLIC_IP"
  echo "سرور مقابل     : $REMOTE_PUBLIC_IP"
  echo "IPv4 پرایوت     : $PRIVATE_IPV4"
  echo "IPv6 پرایوت     : $PRIVATE_IPV6"
  echo "MTU             : $MTU"
  echo
  read -rp "ادامه میدی؟ (y/n): " c
  [[ "$c" != "y" ]] && return

  echo "🚀 در حال ساخت GRE Tunnel..."

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

  echo "✅ GRE Tunnel فعال شد"
  ip addr show $GRE_NAME
}

function remove_gre() {
  echo "⚠ حذف کامل GRE Tunnel..."
  ip addr flush dev $GRE_NAME 2>/dev/null || true
  ip tunnel del $GRE_NAME 2>/dev/null || true
  echo "🗑 تانل حذف شد"
}

while true; do
  header
  echo "1) ایجاد / بازسازی GRE Tunnel"
  echo "2) حذف GRE Tunnel"
  echo "3) فعال‌سازی BBR / BBR2"
  echo "0) خروج"
  echo
  read -rp "انتخاب کنید: " opt

  case $opt in
    1) create_gre ;;
    2) remove_gre ;;
    3) enable_bbr ;;
    0) exit 0 ;;
    *) echo "❌ گزینه نامعتبر"; sleep 1 ;;
  esac

  echo
  read -rp "Enter برای ادامه..."
done
