#!/usr/bin/env bash
# mbf:requires log exec os net crypto
# ==============================================================================
# mbf plugin: ssl
# Automated Let's Encrypt SSL (Certbot) & Self-Signed Certificate Lifecycle
# ==============================================================================

# Provision a Let's Encrypt certificate for `<domain>` via certbot
# Usage: mbf::ssl::issue_letsencrypt <domain> <email> [webroot_dir]
function mbf::ssl::issue_letsencrypt() {
    local domain="$1"
    local email="$2"
    local webroot="${3:-}"

    if [ -z "$domain" ] || [ -z "$email" ]; then
        mbf::log::error "mbf::ssl::issue_letsencrypt: <domain> and <email> are required"
        return 1
    fi

    if ! command -v certbot >/dev/null 2>&1 && ! mbf::is_dryrun; then
        mbf::os::pkg_install certbot python3-certbot-nginx || return 1
    fi

    if [ -n "$webroot" ]; then
        mbf::exec::sudo certbot certonly --non-interactive --agree-tos -m "$email" --webroot -w "$webroot" -d "$domain"
    else
        mbf::exec::sudo certbot --nginx --non-interactive --agree-tos -m "$email" -d "$domain" --redirect
    fi
}

# Generate a self-signed TLS certificate and private key in `<dest_dir>`
# Usage: mbf::ssl::issue_self_signed <domain> <dest_dir> [days]
function mbf::ssl::issue_self_signed() {
    local domain="$1"
    local dest_dir="$2"
    local days="${3:-365}"

    mkdir -p "$dest_dir" || return 1
    if mbf::is_dryrun; then
        mbf::log::info "[DRYRUN] Would generate self-signed cert for $domain in $dest_dir"
        return 0
    fi

    MSYS2_ARG_CONV_EXCL="/CN=" openssl req -x509 -nodes -days "$days" -newkey rsa:2048 \
        -keyout "${dest_dir}/${domain}.key" \
        -out "${dest_dir}/${domain}.crt" \
        -subj "/CN=${domain}" 2>/dev/null
}

# Check all `.crt` / `fullchain.pem` files in a directory and warn if expiring within `<warn_days>`
# Usage: mbf::ssl::check_renewals [certs_dir] [warn_days]
function mbf::ssl::check_renewals() {
    local certs_dir="${1:-/etc/letsencrypt/live}"
    local warn_days="${2:-14}"
    local rc=0 cert days

    [ -d "$certs_dir" ] || return 0

    while IFS= read -r -d $'\0' cert; do
        if days="$(mbf::crypto::cert_expiry_days "$cert")"; then
            if [ "$days" -le "$warn_days" ]; then
                mbf::log::warn "Certificate $cert expires in ${days} days (<= ${warn_days})"
                rc=1
            else
                mbf::log::info "Certificate $cert valid for ${days} days"
            fi
        fi
    done < <(find "$certs_dir" -type f \( -name "*.crt" -o -name "fullchain.pem" \) -print0 2>/dev/null)

    return $rc
}
