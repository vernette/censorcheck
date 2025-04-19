![image](https://i.imgur.com/9QLDY90.png)

```
Usage: censorcheck.sh [OPTIONS]

Checks accessibility of websites that might be blocked by DPI or geolocation restrictions

Options:
  -h, --help             Display this help message and exit
  -m, --mode MODE        Set checking mode: 'dpi', 'geoblock', or 'both' (default: both)
  -t, --timeout SEC      Set connection timeout in seconds (default: 5)
  -r, --retries NUM      Set number of connection retries (default: 2)
  -u, --user-agent STR   Set custom User-Agent string (default: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0)
  -f, --file PATH        Read domains from specified file instead of using built-in lists

Examples:
  censorcheck.sh                              # Check all predefined domains with default settings
  censorcheck.sh --mode dpi                   # Check only DPI-blocked sites
  censorcheck.sh --timeout 10 --retries 3     # Use longer timeout and more retries
  censorcheck.sh --user-agent "MyAgent/1.0"   # Use custom User-Agent
  censorcheck.sh --file my-domains.txt        # Check domains from custom file

The domain file should contain one domain per line. Lines starting with # are ignored
```

## Usage

```bash
bash <(wget -qO- https://github.com/vernette/censorcheck/raw/master/censorcheck.sh)
```
