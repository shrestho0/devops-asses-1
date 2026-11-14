#!/usr/bin/env bash
# Collect Linux system health metrics, write a JSONL log entry, and report status.

set -euo pipefail
set -E

readonly DEFAULT_CPU_THRESHOLD=90
readonly DEFAULT_MEM_THRESHOLD=85
readonly DEFAULT_DISK_THRESHOLD=80
readonly MAX_LOG_BYTES=5242880  # 5 MiB
readonly MAX_LOG_FILES=5

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

CPU_THRESHOLD=$DEFAULT_CPU_THRESHOLD
MEM_THRESHOLD=$DEFAULT_MEM_THRESHOLD
DISK_THRESHOLD=$DEFAULT_DISK_THRESHOLD
JSON_OUTPUT=false
LOG_FILE="$SCRIPT_DIR/health_log.txt"

usage() {
    cat <<'USAGE'
Usage: system_health.sh [OPTIONS]

Collect CPU, memory, filesystem, load-average, and top-process metrics.
A JSON Lines entry is always appended to health_log.txt (or --log-file).

Options:
  --cpu PERCENT       CPU warning threshold (default: 90)
  --mem PERCENT       Memory warning threshold (default: 85)
  --disk PERCENT      Per-filesystem disk warning threshold (default: 80)
  --log-file PATH     Log file path (default: health_log.txt beside the script)
  --json              Print the report as JSON to stdout
  --help              Show this help

Exit codes:
  0  All metrics are within thresholds
  1  One or more warning thresholds were exceeded
  2  A collection, configuration, or logging error occurred

Critical status is reserved for execution/collection failures because this
interface defines warning thresholds only; no separate critical thresholds
were specified.

Log rotation: 5 MiB maximum active log size, with up to 5 rotated files.
USAGE
}

critical_error() {
    printf '[CRITICAL] %s\n' "$1" >&2
    exit 2
}

trap 'printf "[CRITICAL] Unexpected command failure (exit %s) at line %s.\n" "$?" "$LINENO" >&2; exit 2' ERR

validate_threshold() {
    local name=$1
    local value=$2

    if ! awk -v value="$value" 'BEGIN {
        if (value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0 && value <= 100) {
            exit 0
        }
        exit 1
    }'; then
        critical_error "Invalid $name threshold '$value'; expected a number from 0 to 100."
    fi
}

while (($# > 0)); do
    case "$1" in
        --cpu|--mem|--disk|--log-file)
            if (($# < 2)); then
                critical_error "Option '$1' requires a value."
            fi
            case "$1" in
                --cpu) CPU_THRESHOLD=$2 ;;
                --mem) MEM_THRESHOLD=$2 ;;
                --disk) DISK_THRESHOLD=$2 ;;
                --log-file) LOG_FILE=$2 ;;
            esac
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            critical_error "Unknown option '$1'. Use --help for usage."
            ;;
    esac
done

validate_threshold CPU "$CPU_THRESHOLD"
validate_threshold memory "$MEM_THRESHOLD"
validate_threshold disk "$DISK_THRESHOLD"

normalize_threshold() {
    awk -v value="$1" 'BEGIN { printf "%.15g", value + 0 }'
}

CPU_THRESHOLD=$(normalize_threshold "$CPU_THRESHOLD")
MEM_THRESHOLD=$(normalize_threshold "$MEM_THRESHOLD")
DISK_THRESHOLD=$(normalize_threshold "$DISK_THRESHOLD")

json_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

is_over_threshold() {
    local value=$1
    local threshold=$2
    awk -v value="$value" -v threshold="$threshold" 'BEGIN { exit !(value > threshold) }'
}

read_cpu_counters() {
    local -a cpu_fields=()

    read -r -a cpu_fields < /proc/stat || return 1
    ((${#cpu_fields[@]} >= 9)) || return 1
    [[ ${cpu_fields[0]} == cpu ]] || return 1

    CPU_TOTAL=$((cpu_fields[1] + cpu_fields[2] + cpu_fields[3] + cpu_fields[4] + cpu_fields[5] + cpu_fields[6] + cpu_fields[7] + cpu_fields[8]))
    CPU_IDLE=$((cpu_fields[4] + cpu_fields[5]))
}

collect_cpu() {
    local total_before idle_before total_after idle_after delta_total delta_idle

    read_cpu_counters || critical_error 'Unable to read CPU counters from /proc/stat.'
    total_before=$CPU_TOTAL
    idle_before=$CPU_IDLE
    sleep 1
    read_cpu_counters || critical_error 'Unable to read CPU counters from /proc/stat.'
    total_after=$CPU_TOTAL
    idle_after=$CPU_IDLE

    delta_total=$((total_after - total_before))
    delta_idle=$((idle_after - idle_before))
    if ((delta_total <= 0)); then
        critical_error 'Unable to calculate CPU usage from /proc/stat.'
    fi

    CPU_USAGE=$(awk -v total="$delta_total" -v idle="$delta_idle" \
        'BEGIN { printf "%.1f", 100 * (total - idle) / total }')
}

collect_memory() {
    local memory_values

    memory_values=$(awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { available = $2 }
        END {
            if (total <= 0 || available == "") {
                exit 1
            }
            used = total - available
            if (used < 0) {
                used = 0
            }
            printf "%.0f %.0f %.1f\n", total * 1024, used * 1024, 100 * used / total
        }
    ' /proc/meminfo) || critical_error 'Unable to read memory metrics from /proc/meminfo.'

    read -r MEM_TOTAL_BYTES MEM_USED_BYTES MEM_USAGE <<< "$memory_values"
}

collect_load_average() {
    local -a load_fields=()

    read -r -a load_fields < /proc/loadavg || \
        critical_error 'Unable to read load average from /proc/loadavg.'
    ((${#load_fields[@]} >= 3)) || \
        critical_error 'Invalid load average data in /proc/loadavg.'
    LOAD_1M=${load_fields[0]}
    LOAD_5M=${load_fields[1]}
    LOAD_15M=${load_fields[2]}
}

collect_disks() {
    local df_output line filesystem total_kb used_kb available_kb usage mountpoint

    df_output=$(df -P -k) || critical_error 'Unable to collect filesystem usage with df.'

    DISK_FILESYSTEMS=()
    DISK_MOUNTPOINTS=()
    DISK_TOTAL_KB=()
    DISK_USED_KB=()
    DISK_AVAILABLE_KB=()
    DISK_USAGE=()

    while IFS= read -r line; do
        [[ -z $line || $line == Filesystem* ]] && continue
        read -r filesystem total_kb used_kb available_kb usage mountpoint <<< "$line"
        usage=${usage%\%}
        if [[ ! $usage =~ ^[0-9]+$ ]]; then
            critical_error "Unable to parse df output line: $line"
        fi
        DISK_FILESYSTEMS+=("$filesystem")
        DISK_MOUNTPOINTS+=("$mountpoint")
        DISK_TOTAL_KB+=("$total_kb")
        DISK_USED_KB+=("$used_kb")
        DISK_AVAILABLE_KB+=("$available_kb")
        DISK_USAGE+=("$usage")
    done <<< "$df_output"

    if ((${#DISK_FILESYSTEMS[@]} == 0)); then
        critical_error 'No mounted filesystems were returned by df.'
    fi
}

collect_top_processes() {
    local ps_output pid name memory_percent rss_kb

    ps_output=$(ps -eo pid=,comm=,%mem=,rss= --sort=-%mem) || \
        critical_error 'Unable to collect process metrics with ps.'

    TOP_PIDS=()
    TOP_NAMES=()
    TOP_MEMORY_PERCENT=()
    TOP_RSS_KB=()

    while IFS=$'\t' read -r pid name memory_percent rss_kb; do
        [[ -z $pid ]] && continue
        TOP_PIDS+=("$pid")
        TOP_NAMES+=("$name")
        TOP_MEMORY_PERCENT+=("$memory_percent")
        TOP_RSS_KB+=("$rss_kb")
    done < <(printf '%s\n' "$ps_output" | awk '
        NR <= 5 {
            pid = $1
            memory = $(NF - 1)
            rss = $NF
            name = $2
            for (i = 3; i <= NF - 2; i++) {
                name = name " " $i
            }
            printf "%s\t%s\t%.1f\t%s\n", pid, name, memory, rss
        }
    ')
}

add_warning() {
    WARNINGS+=("$1")
    EXIT_CODE=1
    STATUS=warning
}

check_thresholds() {
    local i message

    WARNINGS=()
    EXIT_CODE=0
    STATUS=healthy

    if is_over_threshold "$CPU_USAGE" "$CPU_THRESHOLD"; then
        message="CPU usage ${CPU_USAGE}% exceeds threshold ${CPU_THRESHOLD}%"
        add_warning "$message"
    fi

    if is_over_threshold "$MEM_USAGE" "$MEM_THRESHOLD"; then
        message="Memory usage ${MEM_USAGE}% exceeds threshold ${MEM_THRESHOLD}%"
        add_warning "$message"
    fi

    for i in "${!DISK_USAGE[@]}"; do
        if is_over_threshold "${DISK_USAGE[$i]}" "$DISK_THRESHOLD"; then
            message="Disk usage ${DISK_USAGE[$i]}% on ${DISK_MOUNTPOINTS[$i]} exceeds threshold ${DISK_THRESHOLD}%"
            add_warning "$message"
        fi
    done
}

build_json_report() {
    local i escaped_value timestamp_escaped filesystem_escaped mountpoint_escaped process_name_escaped

    timestamp_escaped=$(json_escape "$TIMESTAMP")
    printf '{"timestamp":"%s","status":"%s","exit_code":%d' \
        "$timestamp_escaped" "$STATUS" "$EXIT_CODE"
    printf ',"cpu":{"usage_percent":%s,"warning_threshold_percent":%s}' \
        "$CPU_USAGE" "$CPU_THRESHOLD"
    printf ',"memory":{"used_bytes":%s,"total_bytes":%s,"usage_percent":%s,"warning_threshold_percent":%s}' \
        "$MEM_USED_BYTES" "$MEM_TOTAL_BYTES" "$MEM_USAGE" "$MEM_THRESHOLD"

    printf ',"disk_filesystems":['
    for i in "${!DISK_FILESYSTEMS[@]}"; do
        ((i > 0)) && printf ','
        filesystem_escaped=$(json_escape "${DISK_FILESYSTEMS[$i]}")
        mountpoint_escaped=$(json_escape "${DISK_MOUNTPOINTS[$i]}")
        printf '{"filesystem":"%s","mountpoint":"%s","total_kb":%s,"used_kb":%s,"available_kb":%s,"usage_percent":%s,"warning_threshold_percent":%s}' \
            "$filesystem_escaped" "$mountpoint_escaped" \
            "${DISK_TOTAL_KB[$i]}" "${DISK_USED_KB[$i]}" \
            "${DISK_AVAILABLE_KB[$i]}" "${DISK_USAGE[$i]}" "$DISK_THRESHOLD"
    done
    printf ']'

    printf ',"load_average":{"1m":%s,"5m":%s,"15m":%s}' \
        "$LOAD_1M" "$LOAD_5M" "$LOAD_15M"

    printf ',"top_processes_by_memory":['
    for i in "${!TOP_PIDS[@]}"; do
        ((i > 0)) && printf ','
        process_name_escaped=$(json_escape "${TOP_NAMES[$i]}")
        printf '{"pid":%s,"name":"%s","memory_percent":%s,"rss_kb":%s}' \
            "${TOP_PIDS[$i]}" "$process_name_escaped" \
            "${TOP_MEMORY_PERCENT[$i]}" "${TOP_RSS_KB[$i]}"
    done
    printf ']'

    printf ',"warnings":['
    for i in "${!WARNINGS[@]}"; do
        ((i > 0)) && printf ','
        escaped_value=$(json_escape "${WARNINGS[$i]}")
        printf '"%s"' "$escaped_value"
    done
    printf ']}'
}

print_human_report() {
    local i

    printf 'System health report: %s\n' "$TIMESTAMP"
    printf 'Status: %s (exit code %s)\n' "$STATUS" "$EXIT_CODE"
    printf 'CPU usage: %s%% (warning threshold: %s%%)\n' "$CPU_USAGE" "$CPU_THRESHOLD"
    printf 'Memory usage: %s%% (%s / %s bytes; warning threshold: %s%%)\n' \
        "$MEM_USAGE" "$MEM_USED_BYTES" "$MEM_TOTAL_BYTES" "$MEM_THRESHOLD"
    printf 'Load average: %s %s %s (1m, 5m, 15m)\n' "$LOAD_1M" "$LOAD_5M" "$LOAD_15M"

    printf 'Disk usage (all filesystems reported by df):\n'
    for i in "${!DISK_FILESYSTEMS[@]}"; do
        printf '  %s on %s: %s%% (warning threshold: %s%%)\n' \
            "${DISK_FILESYSTEMS[$i]}" "${DISK_MOUNTPOINTS[$i]}" \
            "${DISK_USAGE[$i]}" "$DISK_THRESHOLD"
    done

    printf 'Top 5 processes by memory:\n'
    for i in "${!TOP_PIDS[@]}"; do
        printf '  PID %s  %-24s %s%% MEM  %s KiB RSS\n' \
            "${TOP_PIDS[$i]}" "${TOP_NAMES[$i]}" \
            "${TOP_MEMORY_PERCENT[$i]}" "${TOP_RSS_KB[$i]}"
    done

    for i in "${!WARNINGS[@]}"; do
        printf '[WARNING] %s\n' "${WARNINGS[$i]}"
    done
    if ((EXIT_CODE == 0)); then
        printf '[OK] All configured thresholds are within limits.\n'
    fi
}

rotate_log_if_needed() {
    local log_dir file_size index

    log_dir=$(dirname -- "$LOG_FILE")
    mkdir -p -- "$log_dir" || critical_error "Unable to create log directory '$log_dir'."

    if [[ -f $LOG_FILE ]]; then
        file_size=$(wc -c < "$LOG_FILE") || critical_error "Unable to inspect log file '$LOG_FILE'."
        file_size=${file_size//[[:space:]]/}
        if ((file_size >= MAX_LOG_BYTES)); then
            rm -f -- "$LOG_FILE.$MAX_LOG_FILES" || critical_error 'Unable to remove oldest rotated log.'
            for ((index = MAX_LOG_FILES - 1; index >= 1; index--)); do
                if [[ -f $LOG_FILE.$index ]]; then
                    mv -f -- "$LOG_FILE.$index" "$LOG_FILE.$((index + 1))" || \
                        critical_error "Unable to rotate '$LOG_FILE.$index'."
                fi
            done
            mv -f -- "$LOG_FILE" "$LOG_FILE.1" || critical_error "Unable to rotate '$LOG_FILE'."
        fi
    fi
}

collect_cpu
collect_memory
collect_load_average
collect_disks
collect_top_processes

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || critical_error 'Unable to generate timestamp.'
check_thresholds
JSON_REPORT=$(build_json_report)

rotate_log_if_needed
printf '%s\n' "$JSON_REPORT" >> "$LOG_FILE" || critical_error "Unable to append to log file '$LOG_FILE'."

if [[ $JSON_OUTPUT == true ]]; then
    printf '%s\n' "$JSON_REPORT"
    for warning in "${WARNINGS[@]}"; do
        printf '[WARNING] %s\n' "$warning" >&2
    done
else
    print_human_report
fi

exit "$EXIT_CODE"
