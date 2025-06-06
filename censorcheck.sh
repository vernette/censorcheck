#!/usr/bin/env bash

readonly SCRIPT_NAME=$(basename "$0")
readonly COLOR_WHITE="\033[97m"
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_BLUE="\033[36m"
readonly COLOR_ORANGE="\033[33m"
readonly COLOR_RESET="\033[0m"

# Default values
TIMEOUT=5
RETRIES=2
MODE="both"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0"
DOMAINS_FILE=""
IP_VERSION="4"
PROXY=""
SINGLE_DOMAIN=""

readonly DPI_BLOCKED_SITES=(
  "youtube.com"
  "discord.com"
  "instagram.com"
  "facebook.com"
  "x.com"
  "patreon.com"
  "linkedin.com"
  "rutracker.org"
  "nnmclub.to"
  "digitalocean.com"
  "medium.com"
  "ntc.party"
  "amnezia.org"
  "getoutline.org"
  "mailfence.com"
  "flibusta.is"
  "rezka.ag"
)

readonly GEO_BLOCKED_SITES=(
  "spotify.com"
  "netflix.com"
  "swagger.io"
  "snyk.io"
  "mongodb.com"
  "autodesk.com"
  "graylog.org"
  "redis.io"
)

readonly MSG_AVAILABLE="Available"
readonly MSG_BLOCKED_TEMPLATE="Blocked or site didn't respond after %ss timeout"
readonly MSG_REDIRECT="Redirected"
readonly MSG_ACCESS_DENIED="Denied"
readonly MSG_OTHER="Responded with status code"

error_exit() {
  local message="$1"
  local exit_code="${2:-1}"
  printf "[%b%s%b] %b%s%b\n" "$COLOR_RED" "ERROR" "$COLOR_RESET" "$COLOR_WHITE" "$message" "$COLOR_RESET" >&2
  display_help
  exit "$exit_code"
}

display_help() {
  cat <<EOF

Usage: $SCRIPT_NAME [OPTIONS]

Checks accessibility of websites that might be blocked by DPI or geolocation restrictions

Options:
  -h, --help         Display this help message and exit
  -m, --mode         Set checking mode: 'dpi', 'geoblock', or 'both' (default: $MODE)
  -t, --timeout      Set connection timeout in seconds (default: $TIMEOUT)
  -r, --retries      Set number of connection retries (default: $RETRIES)
  -u, --user-agent   Set custom User-Agent string (default: $USER_AGENT)
  -f, --file         Read domains from specified file instead of using built-in lists
  -6, --ipv6         Use IPv6 (default: IPv$IP_VERSION)
  -p, --proxy        Use SOCKS5 proxy (format: host:port)
  -d, --domain       Specify a single domain to check

Examples:
  $SCRIPT_NAME                               # Check all predefined domains with default settings
  $SCRIPT_NAME --mode dpi                    # Check only DPI-blocked sites
  $SCRIPT_NAME --timeout 10 --retries 3      # Use longer timeout and more retries
  $SCRIPT_NAME --user-agent "MyAgent/1.0"    # Use custom User-Agent
  $SCRIPT_NAME --file my-domains.txt         # Check domains from custom file
  $SCRIPT_NAME --ipv6                        # Use IPv6 instead of IPv4
  $SCRIPT_NAME --proxy 127.0.0.1:1080        # Use SOCKS5 proxy
  $SCRIPT_NAME --domain example.com          # Check a single domain

The domain file should contain one domain per line. Lines starting with # are ignored
EOF
}

check_ipv6_support() {
  if [[ -n $(ip -6 addr show scope global 2>/dev/null) ]]; then
    return 0
  fi

  return 1
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        display_help
        exit 0
        ;;
      -m | --mode)
        if [[ $2 == "dpi" || $2 == "geoblock" || $2 == "both" ]]; then
          MODE=$2
        else
          error_exit "Invalid mode: $2. Valid modes are: dpi, geoblock, both"
        fi
        shift 2
        ;;
      -t | --timeout)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          TIMEOUT=$2
        else
          error_exit "Invalid timeout value: $2. Timeout must be a positive integer"
        fi
        shift 2
        ;;
      -r | --retries)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          RETRIES=$2
        else
          error_exit "Invalid retries value: $2. Retry count must be a positive integer"
        fi
        shift 2
        ;;
      -u | --user-agent)
        if [[ -n "$2" ]]; then
          USER_AGENT=$2
        else
          error_exit "User-Agent cannot be empty"
        fi
        shift 2
        ;;
      -f | --file)
        if [[ -n "${2:-}" ]]; then
          if [[ -f "$2" ]]; then
            DOMAINS_FILE="$2"
          else
            error_exit "File '$2' does not exist"
          fi
        else
          error_exit "File path cannot be empty"
        fi
        shift 2
        ;;
      -6 | --ipv6)
        if ! check_ipv6_support; then
          error_exit "IPv6 is not supported on this system"
        fi

        IP_VERSION="6"
        shift
        ;;
      -p | --proxy)
        if [[ -n "${2:-}" ]]; then
          PROXY="$2"
        else
          error_exit "Proxy address cannot be empty"
        fi
        shift 2
        ;;
      -d | --domain)
        if [[ -n "$2" ]]; then
          SINGLE_DOMAIN="$2"
        else
          error_exit "Domain cannot be empty"
        fi
        shift 2
        ;;
      *)
        error_exit "Unknown option: $1"
        ;;
    esac
  done
}

print_header() {
  local mode

  cat <<'EOF'
---------------------------------------------------------------------------------

 ██████╗███████╗███╗   ██╗███████╗ ██████╗ ██████╗  ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗
██╔════╝██╔════╝████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝
██║     █████╗  ██╔██╗ ██║███████╗██║   ██║██████╔╝██║     ███████║█████╗  ██║     █████╔╝ 
██║     ██╔══╝  ██║╚██╗██║╚════██║██║   ██║██╔══██╗██║     ██╔══██║██╔══╝  ██║     ██╔═██╗ 
╚██████╗███████╗██║ ╚████║███████║╚██████╔╝██║  ██║╚██████╗██║  ██║███████╗╚██████╗██║  ██╗
 ╚═════╝╚══════╝╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝

---------------------------------------------------------------------------------
EOF

  printf "\nTimeout set to: %b%ss%b\n" "$COLOR_WHITE" "$TIMEOUT" "$COLOR_RESET"
  printf "Retries set to: %b%s%b\n" "$COLOR_WHITE" "$RETRIES" "$COLOR_RESET"

  case $MODE in
    dpi)
      mode="DPI"
      ;;
    geoblock)
      mode="Geoblock"
      ;;
    both)
      mode="DPI and Geoblock"
      ;;
  esac

  if [[ -z "$DOMAINS_FILE" ]] && [[ -z "$SINGLE_DOMAIN" ]]; then
    printf "Mode set to: %b%s%b\n" "$COLOR_WHITE" "$mode" "$COLOR_RESET"
  fi

  printf "User-Agent set to: %b%s%b\n" "$COLOR_WHITE" "$USER_AGENT" "$COLOR_RESET"

  if [[ -n "$DOMAINS_FILE" ]]; then
    printf "Domain mode set to: %buser domains from %s%b\n" "$COLOR_WHITE" "$DOMAINS_FILE" "$COLOR_RESET"
  elif [[ -n "$SINGLE_DOMAIN" ]]; then
    printf "Checking single domain: %b%s%b\n" "$COLOR_WHITE" "$SINGLE_DOMAIN" "$COLOR_RESET"
  else
    printf "Domain mode set to: %bpredefined domains%b\n" "$COLOR_WHITE" "$COLOR_RESET"
  fi

  printf "IP version set to: %bIPv%s%b\n" "$COLOR_WHITE" "$IP_VERSION" "$COLOR_RESET"

  if [ -n "$PROXY" ]; then
    printf "SOCKS5 proxy set to: %b%s%b\n" "$COLOR_WHITE" "$PROXY" "$COLOR_RESET"
  fi
}

read_domains_from_file() {
  local file=$1
  local domains=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
      line=$(echo "$line" | xargs)
      if [[ -n "$line" ]]; then
        domains+=("$line")
      fi
    fi
  done <"$file"

  echo "${domains[@]}"
}

execute_curl() {
  local url=$1
  local protocol=$2
  local follow_redirects=$3
  local curl_opts=(
    -s
    -o /dev/null
    -w '%{http_code}\n%{redirect_url}'
    --retry-connrefused
    --retry-all-errors
    --retry "$RETRIES"
    --connect-timeout "$TIMEOUT"
    --max-time "$TIMEOUT"
    -"$IP_VERSION"
    -A "$USER_AGENT"
    -H "Sec-Fetch-Site: none"
    -H "Accept-Language: en-US,en;q=0.5"
    -H "Accept-Encoding: gzip, deflate, br, zstd"
  )

  if [ -n "$PROXY" ]; then
    curl_opts+=(--proxy "socks5://$PROXY")
  fi

  if [ "$follow_redirects" = true ]; then
    curl_opts+=(-L)
  fi

  curl "${curl_opts[@]}" "${protocol}://${url}" || echo "000"
}

format_result() {
  local protocol=$1
  local status_code=$2
  local redirect_url=$3
  local msg

  if [ -z "$status_code" ] || [ "$status_code" = "000" ]; then
    msg=$(printf "$MSG_BLOCKED_TEMPLATE" "$TIMEOUT")
  elif [ "$status_code" -ge 300 ] && [ "$status_code" -lt 400 ]; then
    if [[ -z "$redirect_url" ]]; then
      redirect_url="<empty>"
    fi
    msg=$(printf "$MSG_REDIRECT (%s) to %b%s%b" "$status_code" "$COLOR_WHITE" "$redirect_url" "$COLOR_RESET")
  elif [ "$status_code" -eq 200 ]; then
    msg="$MSG_AVAILABLE ($status_code)"
  elif [ "$status_code" -eq 403 ]; then
    msg="$MSG_ACCESS_DENIED ($status_code)"
  else
    msg="$MSG_OTHER $status_code"
  fi

  first_word="${msg%% *}"
  rest="${msg#* }"

  case "$first_word" in
    Blocked)
      first_word_color=$COLOR_RED
      ;;
    Available)
      first_word_color=$COLOR_GREEN
      ;;
    Redirected)
      first_word_color=$COLOR_BLUE
      ;;
    Denied)
      first_word_color=$COLOR_RED
      ;;
    *)
      first_word_color=$COLOR_ORANGE
      ;;
  esac

  printf "  %b%s%b: %b%s%b %s\n" "$COLOR_WHITE" "$protocol" "$COLOR_RESET" "$first_word_color" "$first_word" "$COLOR_RESET" "$rest"
}

check_domain_exists() {
  local domain=$1
  nslookup "$domain" >/dev/null 2>&1
  return $?
}

check_url() {
  local url=$1
  local protocol=$2
  local follow_redirects=false

  if [ "$protocol" = "HTTPS" ]; then
    follow_redirects=true
  fi

  response=$(execute_curl "$url" "$protocol" "$follow_redirects")
  status_code=$(echo "$response" | head -1)
  redirect_url=$(echo "$response" | tail -1)

  format_result "$protocol" "$status_code" "$redirect_url"
}

get_domains_to_check() {
  if [[ -n "$SINGLE_DOMAIN" ]]; then
    echo "$SINGLE_DOMAIN"
  elif [[ -z "$DOMAINS_FILE" ]]; then
    case $MODE in
      # TODO: Replace echo with function
      dpi) echo "${DPI_BLOCKED_SITES[@]}" ;;
      geoblock) echo "${GEO_BLOCKED_SITES[@]}" ;;
      both) echo "${DPI_BLOCKED_SITES[@]}" "${GEO_BLOCKED_SITES[@]}" ;;
    esac
  else
    read_domains_from_file "$DOMAINS_FILE"
  fi
}

check_all_domains() {
  local domains
  read -r -a domains <<<"$(get_domains_to_check)"

  for domain in "${domains[@]}"; do
    # TODO: Remove newline character from the beginning
    printf "\n--------------------------------\n\n"
    printf "Testing %b%s%b:\n" "$COLOR_WHITE" "$domain" "$COLOR_RESET"

    if check_domain_exists "$domain"; then
      check_url "$domain" "HTTP"
      check_url "$domain" "HTTPS"
    else
      printf "  %bDomain doesn't exist%b\n" "$COLOR_ORANGE" "$COLOR_RESET"
    fi
  done
}

main() {
  set -euo pipefail

  parse_arguments "$@"
  print_header
  check_all_domains
}

main "$@"
