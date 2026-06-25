#!/bin/bash

# =========================================
# Domain Reconnaissance Script (v3)
# =========================================
# Script Name: domain_recon.sh
#
# Description:
# This script performs a comprehensive domain reconnaissance.
# Given a domain name, it fetches:
#   - DNS Records (A, AAAA, MX, NS, TXT, CAA)
#   - SPF & DMARC email security records
#   - Hosting IP and geolocation information
#   - Domain WHOIS details (Registrar, creation/expiry, nameservers)
#   - Web server headers
#   - Technology fingerprinting (generic, stack-agnostic)
#   - SSL certificate SANs to find subdomains
#   - Known subdomains from Certificate Transparency logs (crt.sh)
#
# How it works:
#   1. Uses `dig` to query DNS and email/security records.
#   2. Extracts the A record IP, fetches WHOIS and geolocation info.
#   3. Uses `curl` to check HTTP headers and analyze HTML for tech stack patterns.
#   4. Uses `openssl` to inspect SSL certificate SANs.
#   5. Uses `curl` + `jq` to parse crt.sh JSON output for subdomains.
#
# Requirements:
#   - bash (Linux/macOS terminal)
#   - dig (dnsutils)
#   - whois
#   - curl
#   - openssl
#   - jq (for JSON parsing)
#
# Usage:
#   chmod +x domain_recon.sh
#   ./domain_recon.sh example.com
# =========================================

if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN=$1

# -----------------------
# Timestamp + Output File
# -----------------------
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUTDIR="recon_results"
OUTFILE="$OUTDIR/${DOMAIN}_${TIMESTAMP}.txt"

mkdir -p "$OUTDIR"

# Redirect everything to file AND screen
exec > >(tee -a "$OUTFILE") 2>&1

# -----------------------
# Header
# -----------------------
echo "========================================="
echo " Domain Recon Report"
echo "========================================="
echo " Domain: $DOMAIN"
echo " Date: $(date)"
echo " Output File: $OUTFILE"
echo "========================================="
echo

# -----------------------
# DNS Records
# -----------------------
echo "[*] A Record"
dig +short A $DOMAIN
echo

echo "[*] AAAA Record"
dig +short AAAA $DOMAIN
echo

echo "[*] MX Records"
dig +short MX $DOMAIN | sort
echo

echo "[*] NS Records"
dig +short NS $DOMAIN
echo

echo "[*] TXT Records"
dig +short TXT $DOMAIN
echo

echo "[*] CAA Records"
dig +short CAA $DOMAIN || echo "No CAA record found"
echo

echo "[*] SPF Record"
dig +short TXT $DOMAIN | grep -i spf || echo "No SPF record found"
echo

echo "[*] DMARC Record"
dig +short TXT _dmarc.$DOMAIN || echo "No DMARC record found"
echo

# -----------------------
# IP + WHOIS
# -----------------------
IP=$(dig +short A $DOMAIN | head -n1)

if [ -n "$IP" ]; then
    echo "[*] Hosting IP: $IP"
    echo "[*] IP WHOIS (basic org info)"
    whois $IP | grep -E "OrgName|OrgId|Address|City|Country"
    echo

    echo "[*] IP Geolocation"
    curl -s ipinfo.io/$IP
    echo
fi

echo "[*] Domain WHOIS"
whois $DOMAIN | grep -E "Registrar|Creation Date|Expiry Date|Name Server"
echo

# -----------------------
# Web Info
# -----------------------
echo "[*] HTTP Headers"
curl -s -I https://$DOMAIN | grep -E "Server|X-Redirect-By|Location"
echo

# -----------------------
# Technology Fingerprinting (Generic)
# -----------------------
echo "[*] Technology Fingerprinting (Generic Analysis)"

HTML=$(curl -s https://$DOMAIN)
HEADERS=$(curl -s -I https://$DOMAIN)

TECH_FOUND=0

# 1. CDN detection
if echo "$HEADERS" | grep -qi "cloudflare\|cf-ray\|akamai\|fastly"; then
    echo "Detected: CDN (Cloudflare/Akamai/Fastly or similar)"
    TECH_FOUND=1
fi

# 2. API / backend detection
if echo "$HTML" | grep -qi "application/json\|api\|/v1/\|/v2/\|graphql"; then
    echo "Detected: API-driven backend system"
    TECH_FOUND=1
fi

# 3. SPA detection (React / Vue / Angular / Next.js)
if echo "$HTML" | grep -qi "root id=\"app\"\|react\|vue\|angular\|__NEXT_DATA__"; then
    echo "Detected: Single Page Application (SPA)"
    TECH_FOUND=1
fi

# 4. Static site detection
WORD_COUNT=$(echo "$HTML" | wc -c)
if [ "$WORD_COUNT" -lt 5000 ]; then
    echo "Detected: Lightweight / Static website"
    TECH_FOUND=1
fi

# 5. Server-side rendering hints
if echo "$HTML" | grep -qi "php\|aspnet\|jsp\|ruby\|django\|flask"; then
    echo "Detected: Server-side rendered application"
    TECH_FOUND=1
fi

# 6. Admin panels / dashboards
if echo "$HTML" | grep -qi "admin\|dashboard\|login"; then
    echo "Detected: Web application with authentication system"
    TECH_FOUND=1
fi

# 7. Default fallback
if [ "$TECH_FOUND" -eq 0 ]; then
    echo "Detected: Custom / Unknown / Obfuscated technology stack"
fi
echo

# -----------------------
# SSL Certificate SANs
# -----------------------
echo "[*] SSL Certificate SANs"
openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>/dev/null \
| openssl x509 -text | grep DNS:
echo

# -----------------------
# Subdomains (crt.sh)
# -----------------------
echo "[*] Subdomains (crt.sh)"
curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" \
| jq -r '.[].name_value' 2>/dev/null \
| sed 's/\*\.//g' \
| sort -u || echo "No subdomains found"
echo

# -----------------------
# Footer
# -----------------------
echo "========================================="
echo " Recon Completed"
echo " Saved To: $OUTFILE"
echo "========================================="
