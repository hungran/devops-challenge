#!/usr/bin/env bash
# Read-only disk triage for an Ubuntu NGINX load balancer.
# Changes nothing; safe to run on a production host. Run as root for full results.
#
#   sudo ./disk-triage.sh            # root filesystem
#   sudo ./disk-triage.sh /var       # a specific mount
set -uo pipefail

TARGET=${1:-/}
hr() { printf '\n==== %s ====\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

hr "1. Which filesystem is actually full? (ignore loop/squashfs snap mounts: always 100%)"
df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
hr "Inodes"
df -i -x tmpfs -x devtmpfs -x squashfs -x overlay

hr "2. Is the disk fully allocated? (LVM / grown cloud volume not extended)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
have vgs && vgs 2>/dev/null
have lvs && lvs 2>/dev/null
dev=$(findmnt -no SOURCE "$TARGET")
if have tune2fs && [[ $(findmnt -no FSTYPE "$TARGET") == ext4 ]]; then
  tune2fs -l "$dev" 2>/dev/null | grep -E 'Reserved block count|Block count|Block size'
fi

hr "3. Space held by DELETED files still open (df says full, du disagrees)"
if have lsof; then
  lsof -nP +L1 2>/dev/null | awk 'NR==1 || $7 > 10485760' | head -20
else
  find /proc/[0-9]*/fd -lname '*(deleted)' -printf '%p -> %l\n' 2>/dev/null | head -20
fi
used_df=$(df -B1 --output=used "$TARGET" | tail -1)
used_du=$(du -sxB1 "$TARGET" 2>/dev/null | cut -f1)
printf 'df used: %s   du used: %s   gap (deleted-but-open / mounted-over): %s\n' \
  "$(numfmt --to=iec "$used_df")" "$(numfmt --to=iec "$used_du")" \
  "$(numfmt --to=iec $(( used_df > used_du ? used_df - used_du : 0 )))"

hr "4. Biggest directories on this filesystem"
du -xh --max-depth=2 "$TARGET" 2>/dev/null | sort -rh | head -20

hr "5. Biggest files (> 200M)"
find "$TARGET" -xdev -type f -size +200M -printf '%s\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null \
  | sort -rn | head -20 | awk -F'\t' '{ cmd="numfmt --to=iec "$1; cmd | getline h; close(cmd); print h"\t"$2"\t"$3 }'

hr "6. What grew in the last 24h (> 50M)"
find "$TARGET" -xdev -type f -size +50M -mmin -1440 -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -15

hr "7. NGINX: where does it write?"
if have nginx; then
  directives='^\s*(access_log|error_log|proxy_cache_path|proxy_temp_path|client_body_temp_path|proxy_max_temp_file_size|proxy_buffering)\b'
  if ! nginx -T 2>/dev/null | grep -E "$directives" | sort -u; then
    # nginx -T fails if the running config doesn't validate; read the files instead.
    grep -rhE "$directives" /etc/nginx 2>/dev/null | sed 's/^\s*//' | sort -u
  fi
  for d in /var/log/nginx /var/lib/nginx /var/cache/nginx; do [[ -d $d ]] && du -sh "$d" 2>/dev/null; done
  ls -lhS /var/log/nginx 2>/dev/null | head -10
fi

hr "8. Log rotation for nginx"
cat /etc/logrotate.d/nginx 2>/dev/null || echo "!! /etc/logrotate.d/nginx missing"
systemctl list-timers logrotate.timer --no-pager 2>/dev/null | head -3
grep -h nginx /var/lib/logrotate/status 2>/dev/null | head -5
journalctl -u logrotate --since "-3 days" --no-pager -p warning 2>/dev/null | tail -5

hr "9. System logs, crash dumps, package cruft"
journalctl --disk-usage 2>/dev/null
du -sh /var/log/syslog* /var/log/kern.log* /var/log/ufw.log* 2>/dev/null | sort -rh | head
du -sh /var/crash /var/lib/systemd/coredump 2>/dev/null
du -sh /var/cache/apt /var/lib/snapd 2>/dev/null
dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}'
have snap && snap list --all 2>/dev/null | awk '/disabled/'

hr "10. Other usual suspects"
du -sh /tmp /var/tmp /home/* /root 2>/dev/null | sort -rh | head
have docker && docker system df 2>/dev/null
find / -xdev \( -name '*.pcap' -o -name '*.hprof' -o -name 'core' -o -name 'core.[0-9]*' \) -size +10M 2>/dev/null | head

hr "Done (nothing was changed)"
