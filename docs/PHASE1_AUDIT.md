# SIO – Phase 1: Infrastructure Audit

Status: **waiting for VPS audit results.** No changes have been made to the server.

## Run from Android (Termux)

```bash
# 1. Connect to the VPS
ssh <user>@<vps-ip>

# 2. Fetch the read-only audit script (or copy-paste it)
curl -fsSLO https://raw.githubusercontent.com/mlfridi/mlfridi/ccr-4e94e293-xabgab/scripts/audit/vps_audit.sh
# If the repo is private: copy scripts/audit/vps_audit.sh with nano instead.

# 3. Read it before running it, then run it
less vps_audit.sh
sudo bash vps_audit.sh

# 4. Show the report and paste it back (redact the IP if you wish)
cat sio_audit_*.txt
```

## What the script does / does not do

| Does (read-only)                         | Never does                              |
|------------------------------------------|-----------------------------------------|
| OS, kernel, CPU, RAM, swap, disk         | install / remove / upgrade packages     |
| network, public IP, outbound reachability| change SSH, firewall or any config      |
| listening ports, services, processes     | restart services or reboot              |
| Docker / Compose status, containers      | print private keys, /etc/shadow, .env   |
| SSH effective settings, key counts       | write anywhere except its report file   |
| UFW / nftables / iptables / fail2ban     |                                         |
| pending updates, cron jobs, timers, OOMs |                                         |

## Preliminary sizing (to confirm against real audit)

| Component                        | Est. RAM   | Notes                               |
|----------------------------------|------------|-------------------------------------|
| PostgreSQL 16 (tuned small)      | 150–300 MB | internal Docker network only        |
| FastAPI backend + scheduler      | 150–250 MB | RSS engine, workers in-process      |
| Telegram bot (long polling)      | 50–80 MB   | no inbound port needed              |
| Caddy (reverse proxy + auto TLS) | 20–40 MB   | only ports 80/443 exposed           |
| Frontend                         | ~0         | static files served by Caddy        |
| **Total SIO core**               | **~0.4–0.7 GB** | fits a 2 GB VPS; n8n (+300–500 MB) only if ≥4 GB |

AI cost is the only variable cost: it'll be capped with a monthly budget limit in config,
with provider-agnostic adapters (Anthropic / OpenAI-compatible / local) and caching.
No paid service will be subscribed to without approval.
