# censorcheck

A bash script for checking the accessibility of websites potentially affected by Deep Packet Inspection (DPI) blocking or geographic restrictions.

![image](https://i.imgur.com/mQvcta0.png)

## Important note about status codes

> [!WARNING]
> Some websites may not return expected status codes due to various security measures

- Sites like [chatgpt.com](https://chatgpt.com), [claude.ai](https://claude.ai) consistently return `403` status due to JavaScript verification checks, even when accessed from unrestricted locations
- Sites like [intel.com](https://intel.com) may return `200` status but still display blocking notifications in the actual content
- Results should be verified manually when behavior seems inconsistent with your actual location

## Features

- Tests both HTTP and HTTPS protocols for each domain
- Detects different access scenarios: available, blocked, redirected, or access denied
- Includes predefined lists of commonly DPI-blocked and geo-restricted websites
- Supports custom domain lists via file input
- Configurable connection timeout and retry parameters
- Color-coded output for easy readability

## Included Domain Lists

The script contains predefined lists of websites commonly affected by:

- **DPI Blocking**: Includes social media, video platforms, and other commonly restricted services
- **Geographic Restrictions**: Popular streaming services and platforms that implement geo-blocking

## Dependencies

- bash
- curl
- nslookup
- netcat

## Usage

For local usage, download the script:

```bash
wget https://github.com/vernette/censorcheck/raw/master/censorcheck.sh
chmod +x censorcheck.sh
```

### Common Use Cases

```bash
# Show help message
./censorcheck.sh --help

# Check DPI-blocked sites
./censorcheck.sh --mode dpi

# Check DPI-blocked sites using IPv6
./censorcheck.sh --mode dpi --ipv6

# Check custom domain list with increased timeout and retries
./censorcheck.sh --file sites.txt --timeout 10 --retries 3

# Check if a specific site is accessible through a proxy
./censorcheck.sh --domain example.com --proxy 127.0.0.1:1080

# Check only HTTP protocol for a specific domain
./censorcheck.sh --domain example.com --http-only

# Check only HTTPS protocol for all DPI-blocked sites
./censorcheck.sh --mode dpi --https-only
```

You could run the script directly from GitHub:

```bash
bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh) --mode dpi
```

All options available in the help message (`-h, --help`) can be used and combined.

## Options

```
Usage: censorcheck.sh [OPTIONS]

Checks accessibility of websites that might be blocked by DPI or geolocation restrictions

Options:
  -h, --help         Display this help message and exit
  -m, --mode         Set checking mode: 'dpi', 'geoblock', or 'both' (default: both)
  -t, --timeout      Set connection timeout in seconds (default: 5)
  -r, --retries      Set number of connection retries (default: 2)
  -u, --user-agent   Set custom User-Agent string (default: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0)
  -f, --file         Read domains from specified file instead of using built-in lists
  -6, --ipv6         Use IPv6 (default: IPv4)
  -p, --proxy        Use SOCKS5 proxy (format: host:port)
  -d, --domain       Specify a single domain to check
  --http-only        Check only HTTP protocol
  --https-only       Check only HTTPS protocol
  -j, --json         Output results in JSON format

Examples:
  censorcheck.sh                               # Check all predefined domains with default settings
  censorcheck.sh --mode dpi                    # Check only DPI-blocked sites
  censorcheck.sh --timeout 10 --retries 3      # Use longer timeout and more retries
  censorcheck.sh --user-agent "MyAgent/1.0"    # Use custom User-Agent
  censorcheck.sh --file my-domains.txt         # Check domains from custom file
  censorcheck.sh --ipv6                        # Use IPv6 instead of IPv4
  censorcheck.sh --proxy 127.0.0.1:1080        # Check domains using SOCKS5 proxy
  censorcheck.sh --domain example.com          # Check a single domain
  censorcheck.sh --file my-domains.txt --json  # Check custom domains and output JSON

The domain file should contain one domain per line. Lines starting with # are ignored
```

## Custom domain list

You can check your own list of domains by creating a text file with one domain per line:

```
# My custom domains to check
example.com
test-site.net
# Commented lines are ignored
another-domain.org

# Empty lines are also ignored
```

Then run the script with:

```bash
./censorcheck.sh --file my-domains.txt
```

## Test results

The script provides color-coded results for each domain:

- **Green**: Site is available (HTTP 200)
- **Red**: Site is blocked, unreachable, or access denied (HTTP 403)
- **Blue**: Site redirects to another URL
- **Orange**: Other HTTP status codes

## Contributing

Contributions are welcome! Feel free to submit pull requests to add new domains to the predefined lists or improve the script's functionality.

## TODO

- [ ] DNS spoofing detection by ISP or hosting provider
- [ ] Results table
- [x] JSON output
- [ ] Debug mode
