#!/usr/bin/env bash
# =====================================================================
# SIO – Strategic Intelligence Observatory
# PHASE 1 – INFRASTRUCTURE AUDIT (READ-ONLY)
#
# This script ONLY READS system state. It does NOT install, modify,
# restart, delete or enable anything. Safe to run on a production VPS.
#
# Usage (on the VPS):
#   sudo bash vps_audit.sh            # recommended (complete results)
#   bash vps_audit.sh                 # works without root, less detail
#
# Output: ./sio_audit_<host>_<date>.txt
# Secrets: the script never prints private keys, /etc/shadow, .env
# files or passwords. It does print your public IP and hostname —
# redact them before sharing if you prefer.
# =====================================================================
set -u
export LC_ALL=C

OUT="sio_audit_$(hostname -s 2>/dev/null || echo vps)_$(date +%Y%m%d_%H%M%S).txt"
SUDO=""
[ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && SUDO="sudo -n"

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n==================== %s ====================\n' "$1"; }
run() { printf '\n$ %s\n' "$*"; timeout 20 bash -c "$*" 2>&1 | head -n 200 || true; }

{
section "0. META"
echo "Audit date (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
echo "Running as: $(id -un) (uid=$(id -u))  sudo-noninteractive: ${SUDO:+yes}${SUDO:-no}"

section "1. OPERATING SYSTEM"
run "cat /etc/os-release"
run "uname -a"
run "hostnamectl 2>/dev/null | grep -Ev 'Machine ID|Boot ID'"
run "systemd-detect-virt 2>/dev/null || echo unknown"
run "uptime"
run "timedatectl 2>/dev/null | head -n 8"

section "2. CPU"
run "nproc"
run "lscpu | grep -E 'Model name|Architecture|^CPU\\(s\\)|Thread|Core|Socket|MHz|Virtualization|Hypervisor'"
run "cat /proc/loadavg"

section "3. MEMORY / SWAP"
run "free -h"
run "swapon --show"
run "cat /proc/sys/vm/swappiness"

section "4. STORAGE"
run "df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs"
run "df -i / | tail -n 1"
run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT"
run "$SUDO du -sh /var/lib/docker /var/log /home /opt /srv 2>/dev/null"

section "5. NETWORK"
run "ip -brief address"
run "ip route"
run "grep -v '^#' /etc/resolv.conf"
run "curl -s -m 5 https://ifconfig.me || echo 'public IP lookup failed'"
run "curl -s -o /dev/null -m 8 -w 'outbound HTTPS: %{http_code} in %{time_total}s\\n' https://api.telegram.org"
run "curl -s -o /dev/null -m 8 -w 'RSS reachability (bbc): %{http_code}\\n' https://feeds.bbci.co.uk/news/world/rss.xml"

section "6. LISTENING PORTS (what is exposed)"
if have ss; then run "$SUDO ss -tulpn"; else run "$SUDO netstat -tulpn"; fi

section "7. RUNNING SERVICES"
run "systemctl list-units --type=service --state=running --no-pager --no-legend"
run "systemctl list-unit-files --state=enabled --no-pager --no-legend | head -n 80"
run "systemctl --failed --no-pager --no-legend"
run "ps aux --sort=-%mem | head -n 15"

section "8. DOCKER"
if have docker; then
  run "docker --version"
  run "docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo 'compose: not found'"
  run "systemctl is-active docker; systemctl is-enabled docker"
  run "$SUDO docker info 2>/dev/null | grep -E 'Server Version|Storage Driver|Logging Driver|Cgroup|Docker Root Dir|Containers|Running|Images|Total Memory|CPUs'"
  run "$SUDO docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
  run "$SUDO docker network ls"
  run "$SUDO docker volume ls"
  run "$SUDO docker system df"
  run "$SUDO docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null"
else
  echo "Docker: NOT INSTALLED"
fi

section "9. WEB SERVERS / REVERSE PROXIES / DATABASES / PANELS"
for b in nginx apache2 httpd caddy traefik postgres psql mysql mariadb redis-server mongod node python3 pip3 git ufw fail2ban-client certbot; do
  if have "$b"; then printf '%-15s %s\n' "$b" "$($b --version 2>&1 | head -n1 || echo present)"; else printf '%-15s %s\n' "$b" "-"; fi
done
run "ls /usr/local/cpanel /usr/local/CyberCP /usr/local/hestia /opt/coolify /etc/easypanel 2>/dev/null; ls -d /var/www/* 2>/dev/null"

section "10. SSH CONFIGURATION (no keys printed)"
run "$SUDO sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|challengeresponseauthentication|maxauthtries|allowusers|allowgroups|x11forwarding|usepam|clientaliveinterval)\\b'"
run "ls /etc/ssh/sshd_config.d/ 2>/dev/null"
run "for d in /root /home/*; do f=\$d/.ssh/authorized_keys; [ -r \$f ] && echo \"\$f: \$(grep -cvE '^\\s*(#|$)' \$f) key(s)\"; done 2>/dev/null"
run "awk -F: '\$3==0 || \$3>=1000 {print \$1\" uid=\"\$3\" shell=\"\$7}' /etc/passwd"
run "getent group sudo wheel docker 2>/dev/null"
run "$SUDO lastb 2>/dev/null | wc -l | xargs echo 'failed login attempts recorded:'"
run "last -n 10 2>/dev/null"

section "11. FIREWALL / INTRUSION PROTECTION"
run "$SUDO ufw status verbose 2>/dev/null || echo 'ufw: not available'"
run "$SUDO firewall-cmd --state 2>/dev/null || echo 'firewalld: not available'"
run "$SUDO nft list ruleset 2>/dev/null | head -n 60 || echo 'nft: not available'"
run "$SUDO iptables -S 2>/dev/null | head -n 60"
run "$SUDO fail2ban-client status 2>/dev/null || echo 'fail2ban: not installed/running'"

section "12. UPDATES & SECURITY PATCHING"
if have apt; then
  run "apt list --upgradable 2>/dev/null | wc -l | xargs echo 'upgradable packages (cached, no refresh):'"
  run "apt list --upgradable 2>/dev/null | grep -i security | head -n 20"
  run "dpkg -l unattended-upgrades 2>/dev/null | tail -n 1"
  run "cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null"
  run "[ -f /var/run/reboot-required ] && echo 'REBOOT REQUIRED' || echo 'no reboot pending'"
elif have dnf; then
  run "dnf -C check-update 2>/dev/null | tail -n +1 | wc -l"
fi

section "13. SCHEDULED JOBS & BACKUPS"
run "$SUDO crontab -l 2>/dev/null || echo 'no root crontab'"
run "crontab -l 2>/dev/null || echo 'no user crontab'"
run "ls /etc/cron.d /etc/cron.daily 2>/dev/null"
run "systemctl list-timers --no-pager --no-legend | head -n 20"

section "14. KERNEL / LIMITS RELEVANT TO CONTAINERS"
run "sysctl net.ipv4.ip_forward vm.overcommit_memory fs.file-max 2>/dev/null"
run "ulimit -n"
run "$SUDO dmesg 2>/dev/null | grep -iE 'oom|killed process' | tail -n 10 || true"

section "END OF AUDIT"
} > "$OUT" 2>&1

echo "Done. Report written to: $(pwd)/$OUT"
echo "Review it, redact anything you consider sensitive, then share it."
