#!/usr/bin/env bash

readonly SCRIPT_NAME=$(basename "$0")
readonly DEPENDENCIES=("curl" "nslookup" "netcat" "jq" "column")

readonly COLOR_WHITE="\033[97m"
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_BLUE="\033[36m"
readonly COLOR_ORANGE="\033[33m"
readonly COLOR_RESET="\033[0m"
readonly CURL_SEPARATOR="--UNIQUE-SEPARATOR--"

readonly DNS_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
readonly DOH_SERVERS=(
  "https://cloudflare-dns.com/dns-query"
  "https://dns.google/dns-query"
  "https://dns.quad9.net/dns-query"
)

# Default values
TIMEOUT=5
RETRIES=2
MODE="both"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0"
DOMAINS_FILE=""
IP_VERSION="4"
PROXY=""
SINGLE_DOMAIN=""
PROTOCOL="both"
JSON_OUTPUT=false

readonly DPI_BLOCKED_SITES=(
  "youtube.com"
  "discord.com"
  "instagram.com"
  "facebook.com"
  "x.com"
  "linkedin.com"
  "rutracker.org"
  "digitalocean.com"
  # "ntc.party"
  "amnezia.org"
  "getoutline.org"
  "mailfence.com"
  "flibusta.is"
  "rezka.ag"
  "api.telegram.org"
)

readonly GEO_BLOCKED_SITES=(
  "spotify.com"
  "netflix.com"
  "patreon.com"
  "swagger.io"
  "snyk.io"
  "mongodb.com"
  "autodesk.com"
  "graylog.org"
  "redis.io"
)

readonly MSG_AVAILABLE="Available"
readonly MSG_BLOCKED="Blocked"
readonly MSG_BLOCKED_TEMPLATE="$MSG_BLOCKED or site didn't respond after %ss timeout"
readonly MSG_REDIRECT="Redirected"
readonly MSG_ACCESS_DENIED="Denied"
readonly MSG_OTHER="Responded with status code"

declare -a TEXT_RESULTS=()

declare -A DEPENDENCY_COMMANDS=(
  [curl]="curl"
  [nslookup]="nslookup"
  [netcat]="nc"
  [column]="column"
)

error_exit() {
  local message="$1"
  local exit_code="${2:-1}"
  printf "[%b%s%b] %b%s%b\n" "$COLOR_RED" "ERROR" "$COLOR_RESET" "$COLOR_WHITE" "$message" "$COLOR_RESET" >&2
  display_help
  exit "$exit_code"
}

show_progress() {
  local current=$1
  local total=$2
  local domain=$3

  if ! $JSON_OUTPUT; then
    printf "\r\033[K%b[%d/%d] Checking:%b %b%s%b" \
      "$COLOR_BLUE" \
      "$current" \
      "$total" \
      "$COLOR_RESET" \
      "$COLOR_WHITE" \
      "$domain" \
      "$COLOR_RESET"
  fi
}

clear_progress() {
  if ! $JSON_OUTPUT; then
    printf "\r%80s\r" " "
  fi
}

cleanup() {
  clear_progress
  exit 130
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
  --http-only        Test only HTTP
  --https-only       Test only HTTPS
  -j, --json         Output results in JSON format

Examples:
  $SCRIPT_NAME                               # Check all predefined domains with default settings
  $SCRIPT_NAME --mode dpi                    # Check only DPI-blocked sites
  $SCRIPT_NAME --timeout 10 --retries 3      # Use longer timeout and more retries
  $SCRIPT_NAME --user-agent "MyAgent/1.0"    # Use custom User-Agent
  $SCRIPT_NAME --file my-domains.txt         # Check domains from custom file
  $SCRIPT_NAME --ipv6                        # Use IPv6 instead of IPv4
  $SCRIPT_NAME --proxy 127.0.0.1:1080        # Use SOCKS5 proxy
  $SCRIPT_NAME --domain example.com          # Check a single domain
  $SCRIPT_NAME --http-only                   # Test only HTTP
  $SCRIPT_NAME --https-only                  # Test only HTTPS

The domain file should contain one domain per line. Lines starting with # are ignored
EOF
}

is_installed() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

check_missing_dependencies() {
  local missing_pkgs=()
  local cmd

  for pkg in "${DEPENDENCIES[@]}"; do
    cmd="${DEPENDENCY_COMMANDS[$pkg]:-$pkg}"
    if ! is_installed "$cmd"; then
      missing_pkgs+=("$pkg")
    fi
  done

  echo "${missing_pkgs[@]}"
}

prompt_for_installation() {
  local missing_pkgs=("$@")

  echo "Missing dependencies: ${missing_pkgs[*]}"
  read -r -p "Do you want to install them? [y/N]: " answer
  answer=${answer,,}

  case "${answer,,}" in
    y | yes)
      return 0
      ;;
    *)
      exit 0
      ;;
  esac
}

get_package_manager() {
  # Check if the script is running in Termux
  if [[ -d /data/data/com.termux ]]; then
    echo "termux"
    return
  fi

  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
      debian | ubuntu)
        echo "apt"
        ;;
      arch)
        echo "pacman"
        ;;
      fedora)
        echo "dnf"
        ;;
      centos | rhel | rocky | almalinux)
        if command -v dnf >/dev/null 2>&1; then echo "dnf"; else echo "yum"; fi
        ;;
      *)
        error_exit "Unknown distribution: $ID. Please install dependencies manually."
        ;;
    esac
  else
    error_exit "File /etc/os-release not found, unable to determine distribution. Please install dependencies manually."
  fi
}

install_with_package_manager() {
  local pkg_manager="$1"
  local use_sudo=""
  local packages=()
  shift

  for dep in "$@"; do
    case "$pkg_manager" in
      apt | termux)
        case "$dep" in
          nslookup) packages+=("dnsutils") ;;
          netcat) packages+=("netcat-openbsd") ;;
		  column) packages+=("bsdextrautils") ;;
          *) packages+=("$dep") ;;
        esac
        ;;
      pacman)
        case "$dep" in
          nslookup) packages+=("bind") ;;
          netcat) packages+=("openbsd-netcat") ;;
		  column) packages+=("util-linux") ;;
          *) packages+=("$dep") ;;
        esac
        ;;
      dnf | yum)
        case "$dep" in
          nslookup) packages+=("bind-utils") ;;
          netcat) packages+=("netcat") ;;
		  column) packages+=("util-linux") ;;
          *) packages+=("$dep") ;;
        esac
        ;;
      *)
        packages+=("$dep")
        ;;
    esac
  done

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    use_sudo="sudo"
  fi

  case "$pkg_manager" in
    apt)
      $use_sudo apt update
      $use_sudo env NEEDRESTART_MODE=a apt install -y "${packages[@]}"
      ;;
    pacman)
      $use_sudo pacman -Syy --noconfirm "${packages[@]}"
      ;;
    dnf)
      $use_sudo dnf install -y "${packages[@]}"
      ;;
    yum)
      $use_sudo yum install -y "${packages[@]}"
      ;;
    termux)
      apt update
      apt install -y "${packages[@]}"
      ;;
    *)
      error_exit "Unknown package manager: $pkg_manager"
      ;;
  esac
}

install_dependencies() {
  local missing_packages
  local pkg_manager

  read -r -a missing_packages <<<"$(check_missing_dependencies)"

  if [[ ${#missing_packages[@]} -eq 0 ]]; then
    return 0
  fi

  prompt_for_installation "${missing_packages[@]}"

  pkg_manager=$(get_package_manager)
  install_with_package_manager "$pkg_manager" "${missing_packages[@]}"
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
      --http-only)
        PROTOCOL="http"
        shift
        ;;
      --https-only)
        PROTOCOL="https"
        shift
        ;;
      -j | --json)
        JSON_OUTPUT=true
        shift
        ;;
      *)
        error_exit "Unknown option: $1"
        ;;
    esac
  done
}

print_header() {
  local mode

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

  case $PROTOCOL in
    http)
      printf "Protocol set to: %bHTTP only%b\n" "$COLOR_WHITE" "$COLOR_RESET"
      ;;
    https)
      printf "Protocol set to: %bHTTPS only%b\n" "$COLOR_WHITE" "$COLOR_RESET"
      ;;
    both)
      printf "Protocol set to: %bHTTP and HTTPS%b\n" "$COLOR_WHITE" "$COLOR_RESET"
      ;;
  esac

  check_dns_hijacking
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
  local ip_version_to_use=${4:-$IP_VERSION}
  local curl_output
  local curl_opts=(
    -s
    --compressed
    -o /dev/null
    -w "%{http_code}${CURL_SEPARATOR}%{redirect_url}"
    --retry-connrefused
    --retry-all-errors
    --retry "$RETRIES"
    --connect-timeout "$TIMEOUT"
    --max-time "$TIMEOUT"
    -"$ip_version_to_use"
    -A "$USER_AGENT"
    -H "Sec-Fetch-Site: none"
    -H "Accept-Language: en-US,en;q=0.5"
  )

  if [ -n "$PROXY" ]; then
    curl_opts+=(--proxy "socks5://$PROXY")
  fi

  if [ "$follow_redirects" = true ]; then
    curl_opts+=(-L)
  fi

  if curl_output=$(curl "${curl_opts[@]}" "${protocol}://${url}"); then
    echo "$curl_output"
  else
    echo "000${CURL_SEPARATOR}"
  fi
}

format_result() {
  local protocol=$1
  local status_code=$2
  local redirect_url=$3
  local msg

  if [ -z "$status_code" ] || [ "$status_code" = "000" ] || [ "$status_code" -eq 0 ]; then
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

get_single_check_result() {
  local domain=$1
  local protocol=$2
  local follow_redirects=$3
  local ip_version=$4
  local response status_code redirect_url

  response=$(execute_curl "$domain" "$protocol" "$follow_redirects" "$ip_version")
  status_code="${response%%$CURL_SEPARATOR*}"
  redirect_url="${response#*$CURL_SEPARATOR}"

  jq -n \
    --argjson status "${status_code:-0}" \
    --arg redirect_url "${redirect_url:-}" \
    '
    {
      "status": ($status|tonumber),
      "redirect_url": (if $redirect_url == "" then null else $redirect_url end)
    }
    '
}

gather_single_domain_result() {
  local domain=$1
  local ipv6_supported
  local http_ipv4=null http_ipv6=null https_ipv4=null https_ipv6=null

  check_ipv6_support && ipv6_supported=true || ipv6_supported=false

  if [[ "$PROTOCOL" == "both" || "$PROTOCOL" == "http" ]]; then
    http_ipv4=$(get_single_check_result "$domain" "HTTP" false 4)
    if $ipv6_supported; then
      http_ipv6=$(get_single_check_result "$domain" "HTTP" false 6)
    fi
  fi
  if [[ "$PROTOCOL" == "both" || "$PROTOCOL" == "https" ]]; then
    https_ipv4=$(get_single_check_result "$domain" "HTTPS" true 4)
    if $ipv6_supported; then
      https_ipv6=$(get_single_check_result "$domain" "HTTPS" true 6)
    fi
  fi

  jq -n \
    --arg service "$domain" \
    --argjson http_ipv4 "$http_ipv4" \
    --argjson http_ipv6 "$http_ipv6" \
    --argjson https_ipv4 "$https_ipv4" \
    --argjson https_ipv6 "$https_ipv6" \
    '
        {
          "service": $service,
          "http": {
            "ipv4": $http_ipv4,
            "ipv6": $http_ipv6
          },
          "https": {
            "ipv4": $https_ipv4,
            "ipv6": $https_ipv6
          }
        }
        '
}

get_domain_ip() {
  local domain=$1
  local ip
  nslookup "$domain" | awk '/^Address: / && !/#/ {print $2; exit}' || true
}

get_domain_ips_via_dns() {
  local domain=$1
  local server=$2
  local output

  if [[ -n "$server" ]]; then
    output=$(nslookup "$domain" "$server" 2>/dev/null)
  else
    output=$(nslookup "$domain" 2>/dev/null)
  fi

  awk '/Address:/ && !/#/ && !/[:].*[:]/ {print $2}' <<<"$output" || true
}

get_domain_ips_via_doh() {
  local domain=$1
  local doh_server=$2

  curl -s -H "accept: application/dns-json" \
    "${doh_server}?name=${domain}&type=A" |
    jq -r '.Answer[]?.data // empty' 2>/dev/null
}

have_ip_intersection() {
  local -n first_ips=$1
  local -n second_ips=$2

  declare -A ip_set=()
  local ip

  for ip in "${first_ips[@]}"; do
    ip_set["$ip"]=1
  done

  for ip in "${second_ips[@]}"; do
    [[ -n ${ip_set["$ip"]+1} ]] && return 0
  done

  return 1
}

check_dns_hijacking() {
  local test_domains=("rutracker.org" "linkedin.com" "flibusta.is")
  local regular_dns_ips=()
  local doh_ips=()
  local hijacked_domain=""
  local hijacked_ip=""

  for test_domain in "${test_domains[@]}"; do
    regular_dns_ips=()
    doh_ips=()

    for dns_server in "${DNS_SERVERS[@]}"; do
      mapfile -t regular_dns_ips < <(get_domain_ips_via_dns "$test_domain" "$dns_server")
      [[ ${#regular_dns_ips[@]} -gt 0 ]] && break
    done

    for doh_server in "${DOH_SERVERS[@]}"; do
      mapfile -t doh_ips < <(get_domain_ips_via_doh "$test_domain" "$doh_server")
      [[ ${#doh_ips[@]} -gt 0 ]] && break
    done

    [[ ${#regular_dns_ips[@]} -eq 0 ]] || [[ ${#doh_ips[@]} -eq 0 ]] && continue

    if ! have_ip_intersection regular_dns_ips doh_ips; then
      hijacked_domain="$test_domain"
      hijacked_ip="${regular_dns_ips[0]}"
      break
    fi
  done

  if [[ -n "$hijacked_domain" ]]; then
    printf "\n%b%s%b %s %b%s%b %s %b%s%b\n\n" \
      "$COLOR_RED" "DNS hijacking detected!" "$COLOR_RESET" \
      "ISP redirects" "$COLOR_WHITE" "$hijacked_domain" "$COLOR_RESET" "to" \
      "$COLOR_RED" "$hijacked_ip" "$COLOR_RESET"

    printf "%b%s%b\n%b%s%b\n" \
      "$COLOR_ORANGE" "DNS hijacking may affect the accuracy of this check" "$COLOR_RESET" \
      "$COLOR_ORANGE" "Configure encrypted DNS (DoH/DoT) on your system" "$COLOR_RESET"
  else
    printf "\n%b%s%b\n" \
      "$COLOR_GREEN" "Good news, no DNS hijacking detected!" "$COLOR_RESET"
  fi
}

is_ip_reachable() {
  local ip="$1"
  nc -z -w "$TIMEOUT" "$ip" 443 2>/dev/null
}

make_json_error() {
  local domain="$1"
  local error_code="$2"

  case "$error_code" in
    nxdomain)
      jq -n --arg service "$domain" '
        {
          "service": $service,
          "error": "Domain does not exist",
          "error_code": "nxdomain",
          "http": null,
          "https": null
        }
      '
      ;;
    blocked_by_ip)
      jq -n --arg service "$domain" '
        {
          "service": $service,
          "error": "Blocked by IP",
          "error_code": "blocked_by_ip",
          "http": null,
          "https": null
        }
      '
      ;;
    *)
      jq -n --arg service "$domain" --arg code "$error_code" '
        {
          "service": $service,
          "error": "Unknown error",
          "error_code": $code,
          "http": null,
          "https": null
        }
      '
      ;;
  esac
}

summarize_status_description() {
  local status_code=$1
  local redirect_url=$2
  local msg

  if [[ -z "$status_code" || "$status_code" = "000" || "$status_code" -eq 0 ]]; then
    msg=$(printf "$MSG_BLOCKED_TEMPLATE" "$TIMEOUT")
  elif [[ "$status_code" -ge 300 && "$status_code" -lt 400 ]]; then
    [[ -z "$redirect_url" ]] && redirect_url="<empty>"
    msg=$(printf "%s (%s) -> %s" "$MSG_REDIRECT" "$status_code" "$redirect_url")
  elif [[ "$status_code" -eq 200 ]]; then
    msg="$MSG_AVAILABLE ($status_code)"
  elif [[ "$status_code" -eq 403 ]]; then
    msg="$MSG_ACCESS_DENIED ($status_code)"
  else
    msg="$MSG_OTHER $status_code"
  fi

  echo "$msg"
}

colorize_summary() {
  local message="$1"
  local first_word rest first_word_color

  first_word="${message%% *}"
  if [[ "$first_word" == "$message" ]]; then
    rest=""
  else
    rest="${message#* }"
  fi

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
    N/A | Skipped)
      first_word_color=$COLOR_ORANGE
      ;;
    *)
      first_word_color=$COLOR_ORANGE
      ;;
  esac

  if [[ -z "$rest" ]]; then
    printf "%b%s%b" "$first_word_color" "$first_word" "$COLOR_RESET"
  else
    printf "%b%s%b %s" "$first_word_color" "$first_word" "$COLOR_RESET" "$rest"
  fi
}

summarize_protocol_result() {
  local result_json=$1
  local protocol=$2

  if [[ "$PROTOCOL" != "both" && "$PROTOCOL" != "$protocol" ]]; then
    echo "Skipped"
    return
  fi

  local data
  data=$(jq -c --arg protocol "$protocol" '
      if .[$protocol].ipv4 != null then .[$protocol].ipv4
      elif .[$protocol].ipv6 != null then .[$protocol].ipv6
      else null end
    ' <<<"$result_json")

  if [[ "$data" == "null" || -z "$data" ]]; then
    echo "N/A"
    return
  fi

  local status redirect
  status=$(jq -r '.status' <<<"$data")
  redirect=$(jq -r '.redirect_url // ""' <<<"$data")
  summarize_status_description "$status" "$redirect"
}

add_text_result_row() {
  local service=$1
  local ip=$2
  local http_cell=$3
  local https_cell=$4

  TEXT_RESULTS+=("$(
    jq -n \
      --arg service "$service" \
      --arg ip "$ip" \
      --arg http "$http_cell" \
      --arg https "$https_cell" \
      '{service: $service, ip: $ip, http: $http, https: $https}'
  )")
}

add_text_result_from_json() {
  local result_json=$1
  local ip=$2
  local service
  service=$(echo "$result_json" | jq -r '.service')
  local http_cell https_cell

  http_cell=$(summarize_protocol_result "$result_json" "http")
  https_cell=$(summarize_protocol_result "$result_json" "https")

  add_text_result_row "$service" "$ip" "$http_cell" "$https_cell"
}

print_table_results() {
  printf "\n"
  {
    printf "\033[1m%b%s\t%s\t%s\t%s%b\033[0m\n" \
      "$COLOR_WHITE" \
      "Service" \
      "IP" \
      "HTTP" \
      "HTTPS" \
      "$COLOR_RESET"

    for row_json in "${TEXT_RESULTS[@]}"; do
      local service http https
      service=$(jq -r '.service' <<<"$row_json")
      ip=$(jq -r '.ip' <<<"$row_json")
      http=$(jq -r '.http' <<<"$row_json")
      https=$(jq -r '.https' <<<"$row_json")

      printf "%s%b\t%s\t%s\t%s\n" \
        "$service" \
        "$COLOR_RESET" \
        "$ip" \
        "$(colorize_summary "$http")" \
        "$(colorize_summary "$https")"
    done
  } | column -t -s $'\t'
}

run_checks_and_print() {
  local domains
  local all_results_json="[]"

  read -r -a domains <<<"$(get_domains_to_check)"

  local total_domains=${#domains[@]}

  local current_index=0

  TEXT_RESULTS=()

  if ! $JSON_OUTPUT; then
    print_header
    printf "\n"
  fi

  for domain in "${domains[@]}"; do
    ((++current_index))
    show_progress "$current_index" "$total_domains" "$domain"

    local ip_address

    ip_address=$(get_domain_ip "$domain")

    if [[ -z "$ip_address" ]]; then

      if $JSON_OUTPUT; then
        all_results_json=$(echo "$all_results_json" | jq --argjson item "$(make_json_error "$domain" nxdomain)" '. + [$item]')
      else
        add_text_result_row "$domain" "N/A" "Domain does not exist" "Domain does not exist"
      fi
      continue
    fi

    if ! is_ip_reachable "$ip_address"; then
      if $JSON_OUTPUT; then
        all_results_json=$(echo "$all_results_json" | jq --argjson item "$(make_json_error "$domain" blocked_by_ip)" '. + [$item]')
      else
        add_text_result_row "$domain" "$ip_address" "Blocked by IP" "Blocked by IP"
      fi
      continue
    fi

    local domain_result_json
    domain_result_json=$(gather_single_domain_result "$domain")

    if $JSON_OUTPUT; then
      all_results_json=$(echo "$all_results_json" | jq --argjson item "$domain_result_json" '. + [$item]')
    else
      add_text_result_from_json "$domain_result_json" "$ip_address"
    fi
  done

  clear_progress

  if $JSON_OUTPUT; then
    local ipv6_supported
    check_ipv6_support && ipv6_supported=true || ipv6_supported=false

    local ip_version_param_val
    if $ipv6_supported; then
      ip_version_param_val="IPv4 & IPv6"
    else
      ip_version_param_val="IPv4"
    fi

    local params_json

    params_json=$(
      jq -n \
        --arg timeout "${TIMEOUT}s" \
        --arg retries "$RETRIES" \
        --arg mode "${MODE^^}" \
        --arg user_agent "$USER_AGENT" \
        --arg domain_mode "$(if [[ -n "$DOMAINS_FILE" ]]; then echo "user domains from $DOMAINS_FILE"; elif [[ -n "$SINGLE_DOMAIN" ]]; then echo "single domain"; else echo "predefined domains"; fi)" \
        --arg ip_version "$ip_version_param_val" \
        --arg protocol "$(if [[ "$PROTOCOL" == "both" ]]; then echo "HTTP and HTTPS"; elif [[ "$PROTOCOL" == "http" ]]; then echo "HTTP only"; else echo "HTTPS only"; fi)" \
        '[
          {"key":"timeout", "value":$timeout},

          {"key":"retries", "value":$retries},
          {"key":"mode", "value":$mode},
          {"key":"user_agent", "value":$user_agent},
          {"key":"domain_mode", "value":$domain_mode},
          {"key":"ip_version", "value":$ip_version},
          {"key":"protocol", "value":$protocol}
        ]'
    )

    jq -n \
      --argjson params "$params_json" \
      --argjson results "$all_results_json" \
      '{
				"version": 1,
				"params": $params,
				"results": $results
			}'

    return
  fi

  print_table_results
}

main() {
  set -euo pipefail

  trap cleanup EXIT INT TERM

  install_dependencies
  parse_arguments "$@"
  run_checks_and_print

  trap - EXIT INT TERM
}

main "$@"
