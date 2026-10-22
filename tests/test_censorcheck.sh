#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../censorcheck.sh
source "$SCRIPT_DIR/../censorcheck.sh"

FAILURES=0

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    printf "ok   %s\n" "$description"
    return
  fi

  printf "FAIL %s\n     expected: %s\n     actual:   %s\n" "$description" "$expected" "$actual"
  FAILURES=$((FAILURES + 1))
}

test_format_pending_labels() {
  assert_eq "pending single keeps details" "DC5 91.108.56.130" "$(format_pending_labels "DC5 91.108.56.130")"
  assert_eq "pending list short names" "DC1, DC2, DC3" \
    "$(format_pending_labels "DC1 149.154.175.50" "DC2 149.154.167.51" "DC3 149.154.175.100")"

  local domains=()
  local i
  for i in {1..20}; do
    domains+=("domain$i.example.com")
  done
  assert_eq "pending list truncated" "domain1.example.com, domain2.example.com +18" \
    "$(format_pending_labels "${domains[@]}")"
}

test_wait_with_progress() {
  local pids=()
  local labels=("slow" "fast")
  local start progress

  sleep 1.3 &
  pids+=("$!")
  sleep 0.4 &
  pids+=("$!")

  start=$EPOCHREALTIME
  progress=$(wait_with_progress pids labels 2>&1)

  assert_eq "wait progress waits for all jobs" "1" \
    "$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN {print (b - a >= 1.2) ? 1 : 0}')"
  assert_eq "wait progress lists pending jobs" "1" "$([[ "$progress" == *"[0/2] Checking:"*"slow, fast (0s)"* ]] && echo 1)"
  assert_eq "wait progress counts finished jobs" "1" "$([[ "$progress" == *"[1/2] Checking:"*"slow ("* ]] && echo 1)"

  local no_pids=()
  local no_labels=()
  assert_eq "wait progress without jobs" "" "$(wait_with_progress no_pids no_labels 2>&1)"
}

test_get_domain_host() {
  assert_eq "domain host with path" "redirector.googlevideo.com" \
    "$(get_domain_host "redirector.googlevideo.com/report_mapping?di=no")"
  assert_eq "domain host plain" "youtube.com" "$(get_domain_host youtube.com)"
}

test_get_record_type() {
  assert_eq "record type ipv4" "A" "$(get_record_type 4)"
  assert_eq "record type ipv6" "AAAA" "$(get_record_type 6)"
}

test_read_domains_from_file() {
  local file
  file=$(mktemp)
  printf "# comment\n\n  youtube.com  \n  # indented comment\ndiscord.com" >"$file"

  assert_eq "domains file" "youtube.com discord.com" "$(read_domains_from_file "$file")"
  rm -f "$file"
}

test_summarize_status_description() {
  assert_eq "status port blocked" "$MSG_BLOCKED_BY_PORT" "$(summarize_status_description -1 "")"
  assert_eq "status timeout" "$MSG_TIMEOUT" "$(summarize_status_description 000 "")"
  assert_eq "status redirect" "$MSG_REDIRECT (301) -> https://x.com/" \
    "$(summarize_status_description 301 "https://x.com/")"
  assert_eq "status redirect empty" "$MSG_REDIRECT (302) -> <empty>" "$(summarize_status_description 302 "")"
  assert_eq "status 200" "$MSG_AVAILABLE (200)" "$(summarize_status_description 200 "")"
  assert_eq "status 403" "$MSG_ACCESS_DENIED (403)" "$(summarize_status_description 403 "")"
  assert_eq "status other" "$MSG_OTHER 451" "$(summarize_status_description 451 "")"
}

test_summarize_protocol_result() {
  local result='{"service":"x.com","http":{"ipv4":{"status":200,"redirect_url":null},"ipv6":null},"https":{"ipv4":null,"ipv6":null}}'

  PROTOCOL="both"
  IP_VERSION="4"
  assert_eq "protocol result available" "$MSG_AVAILABLE (200)" "$(summarize_protocol_result "$result" http)"
  assert_eq "protocol result missing" "N/A" "$(summarize_protocol_result "$result" https)"

  local redirect='{"service":"x.com","http":{"ipv4":null,"ipv6":{"status":301,"redirect_url":"https://x.com/"}},"https":null}'
  IP_VERSION="6"
  assert_eq "protocol result ipv6 redirect" "$MSG_REDIRECT (301) -> https://x.com/" \
    "$(summarize_protocol_result "$redirect" http)"
  assert_eq "protocol result ipv6 missing" "N/A" "$(summarize_protocol_result "$result" http)"
  IP_VERSION="4"

  PROTOCOL="https"
  assert_eq "protocol result skipped" "Skipped" "$(summarize_protocol_result "$result" http)"
  PROTOCOL="both"
}

test_colorize_summary() {
  assert_eq "colorize blocked" "$(printf "%bBlocked%b by IP" "$COLOR_RED" "$COLOR_RESET")" \
    "$(colorize_summary "Blocked by IP")"
  assert_eq "colorize single word" "$(printf "%bClean%b" "$COLOR_GREEN" "$COLOR_RESET")" "$(colorize_summary "Clean")"
  assert_eq "colorize unknown" "$(printf "%bSkipped%b" "$COLOR_ORANGE" "$COLOR_RESET")" "$(colorize_summary "Skipped")"
}

test_classify_plain_answer() {
  local reference_ips=("1.2.3.4" "5.6.7.8")

  assert_eq "dns clean" "$MSG_CLEAN" "$(classify_plain_answer "NOERROR 9.9.9.9 5.6.7.8" reference_ips)"
  assert_eq "dns spoofed" "$MSG_SPOOFED (10.0.0.1)" "$(classify_plain_answer "NOERROR 10.0.0.1" reference_ips)"
  assert_eq "dns nxdomain" "$MSG_SPOOFED (NXDOMAIN)" "$(classify_plain_answer "NXDOMAIN" reference_ips)"
  assert_eq "dns no response" "$MSG_NO_RESPONSE" "$(classify_plain_answer "NOERROR" reference_ips)"
}

test_get_reference_resolver() {
  AVAILABLE_DOH=()
  AVAILABLE_DOT=("9.9.9.9")
  assert_eq "reference resolver dot" $'9.9.9.9\ttls' "$(get_reference_resolver)"

  AVAILABLE_DOH=("1.1.1.1")
  assert_eq "reference resolver doh first" $'1.1.1.1\thttps' "$(get_reference_resolver)"
  AVAILABLE_DOH=()
  AVAILABLE_DOT=()
}

test_hex_helpers() {
  assert_eq "hex roundtrip" "00ff10ee" "$(hex_to_bin 00ff10ee | bin_to_hex)"
  assert_eq "reverse hex" "04030201" "$(reverse_hex 01020304)"
  assert_eq "le32 hex" "efbeadde" "$(le32_hex 0xdeadbeef)"

  local key iv
  key=$(printf '%064d' 0)
  iv=$(printf '%032d' 0)
  assert_eq "aes ctr roundtrip" "cafebabe" \
    "$(hex_to_bin cafebabe | aes_ctr "$key" "$iv" | aes_ctr "$key" "$iv" | bin_to_hex)"
}

test_make_json_error() {
  local json
  json=$(make_json_error x.com DNS "Domain not found")

  assert_eq "json error" "x.com DNS Domain not found null" \
    "$(jq -r '"\(.service) \(.error_code) \(.error) \(.http)"' <<<"$json")"
}

test_parse_arguments() {
  parse_arguments -m both -t 10 -r 3 -p 127.0.0.1:1080 -d x.com --https-only -j

  assert_eq "args mode both" "all" "$MODE"
  assert_eq "args timeout" "10" "$TIMEOUT"
  assert_eq "args retries" "3" "$RETRIES"
  assert_eq "args proxy" "127.0.0.1:1080" "$PROXY"
  assert_eq "args domain" "x.com" "$SINGLE_DOMAIN"
  assert_eq "args protocol" "https" "$PROTOCOL"
  assert_eq "args json" "true" "$JSON_OUTPUT"
  assert_eq "domains single" "x.com" "$(get_domains_to_check)"

  parse_arguments -m geoblock
  assert_eq "args geoblock disables dns" "false" "$DNS_CHECK"
  assert_eq "args geoblock disables tg" "false" "$TG_CHECK"

  (parse_arguments -t abc >/dev/null 2>&1)
  assert_eq "args invalid timeout exits" "1" "$?"
  (parse_arguments -m nope >/dev/null 2>&1)
  assert_eq "args invalid mode exits" "1" "$?"
  (DNS_CHECK=true parse_arguments -m dns --no-dns >/dev/null 2>&1)
  assert_eq "args dns with --no-dns exits" "1" "$?"
}

test_format_pending_labels
test_wait_with_progress
test_get_domain_host
test_get_record_type
test_read_domains_from_file
test_summarize_status_description
test_summarize_protocol_result
test_colorize_summary
test_classify_plain_answer
test_get_reference_resolver
test_hex_helpers
test_make_json_error
test_parse_arguments

if ((FAILURES > 0)); then
  printf "\n%d failed\n" "$FAILURES"
  exit 1
fi

printf "\nall passed\n"
