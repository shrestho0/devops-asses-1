
1. CPU Usage

Linux provides CPU counters through:

/proc/stat

It contains cumulative CPU time spent in different states, including:
- user: Time executing user-space processes.
- nice: Time executing niced processes.
- system: Time executing kernel code.
- idle: Idle CPU time.
- iowait: Time waiting for I/O.
- irq / softirq: Interrupt handling.
- steal: Time taken by the hypervisor for other virtual machines.


\[
CPU\ Usage = \frac{\Delta Total-\Delta Idle}{\Delta Total}\times100
\]

For this calculation, treat idle time as idle + iowait. The total should include the first eight CPU fields, without adding guest and guest_nice again.




2. Memory Usage

/proc/meminfo

Important fields:
Field	Meaning
MemTotal	Total physical memory
MemFree	Completely unused memory
MemAvailable	Estimated memory available without swapping
Buffers	Kernel buffer memory
Cached	Filesystem cache

For monitoring, use MemAvailable, not just MemFree.

Why? Linux intentionally uses otherwise-unused RAM for filesystem caching. That memory can be reclaimed when applications need it.

The calculation:
\[
Memory\ Usage = \frac{MemTotal-MemAvailable}{MemTotal}\times100
\]

Your output should ideally include both the percentage and absolute usage.



3. Disk usage — all mounted filesystems
Which Linux utility?

df — reports filesystem disk space usage.

You need to collect:
- Filesystem name
- Total size
- Used space
- Available space
- Usage percentage
- Mount point
One important consideration: use the portable output format (-P) to avoid filesystem entries wrapping across multiple lines.

There is also a design decision:
- Normal df output generally excludes certain pseudo-filesystems.
- df -a includes them.
Since the assignment explicitly says all mounted filesystems, decide whether pseudo-filesystems such as /proc, /sys, and /dev should also appear.

For a strict interpretation, include them. For practical capacity monitoring, filtering non-storage pseudo-filesystems is usually more useful.


4. 4. Load average
Where?

/proc/loadavg

Linux exposes three load averages:
Value	Measurement
First	1-minute average
Second	5-minute average
Third	15-minute average

Example:

0.42 0.38 0.31

These values represent average runnable and uninterruptible tasks, not CPU utilization percentages.

An important operational distinction:

A load average of 4 means different things on a 4-core machine and a 32-core machine.

You can also collect the number of CPU cores to provide context, although the assignment doesn't explicitly require it.


5. 5. Top 5 processes by memory usage
Which Linux utility?

ps

You need to retrieve:
Field	Purpose
PID	Process ID
COMMAND	Process name
%MEM	Percentage of physical memory
RSS	Resident memory in KB

The implementation logic:
1. Retrieve all processes.
2. Sort by memory percentage in descending order.
3. Select the first five processes.
4. Preserve the column headers in the output.
Use the process name rather than full command-line arguments unless you specifically need them. Command-line arguments can contain sensitive information.


Implemented features
- CPU usage measured over a 1-second sampling interval.
- Memory usage based on MemAvailable.
- Disk usage across all filesystems reported by df.
- 1, 5 and 15-minute load averages.
- Top 5 processes sorted by memory consumption.
- Timestamped JSON Lines logging.
- --json for machine-readable stdout.
- Configurable --cpu, --mem, and --disk thresholds.
- Automatic log rotation: 5 MiB maximum active log, up to 5 backups.
- --help and meaningful exit codes.
Exit code interpretation
Code	Meaning
0	Healthy
1	One or more thresholds exceeded
2	Critical execution, collection, configuration or logging failure


--------------------------------


 
| File                  | Purpose                              |
| --------------------- | ------------------------------------ |
| system_health.sh      | Main production-oriented Bash script |
| system-health.service | Systemd oneshot service              |
| system-health.timer   | Executes every 5 minutes             |

### **Implemented features**

- CPU usage measured over a 1-second sampling interval.
- Memory usage based on `MemAvailable`.
- Disk usage across all filesystems reported by `df`.
- 1, 5 and 15-minute load averages.
- Top 5 processes sorted by memory consumption.
- Timestamped JSON Lines logging.
- `--json` for machine-readable stdout.
- Configurable `--cpu`, `--mem`, and `--disk` thresholds.
- Automatic log rotation: 5 MiB maximum active log, up to 5 backups.
- `--help` and meaningful exit codes.

### **Exit code interpretation**

| Code | Meaning                                                          |
| ---- | ---------------------------------------------------------------- |
| 0    | Healthy                                                          |
| 1    | One or more thresholds exceeded                                  |
| 2    | Critical execution, collection, configuration or logging failure |

**Important:** The assessment specifies warning thresholds but does not define separate critical thresholds. Therefore, code `2` is reserved for execution and collection failures rather than inventing additional metric thresholds.

### **Installation**

```
sudo install -m 0755 system_health.sh /usr/local/sbin/system_health.sh

sudo install -m 0644 system-health.service \
  /etc/systemd/system/

sudo install -m 0644 system-health.timer \
  /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now system-health.timer
```

Verify scheduling:

```
systemctl list-timers system-health.timer
```

Inspect execution logs:

```
journalctl -u system-health.service
```

### **Validation**








## Uninstall commands

Run the following commands to completely remove the System Health Monitoring script and its systemd scheduling configuration.

1. Stop and disable the timer

bash

```bash
sudo systemctl stop system-health.timer
sudo systemctl disable system-health.timer
```

2. Stop the service (if running)

bash

```bash
sudo systemctl stop system-health.service
```

3. Remove the systemd files

bash

```bash
sudo rm -f /etc/systemd/system/system-health.service
sudo rm -f /etc/systemd/system/system-health.timer
```

4. Remove the Bash monitoring script

bash

```bash
sudo rm -f /usr/local/sbin/system_health.sh
```

5. Reload systemd

bash

```bash
sudo systemctl daemon-reload
sudo systemctl reset-failed
```

6. Verify removal

bash

```bash
systemctl status system-health.timer
systemctl status system-health.service
```

Both should report that the units could not be found.

### Optional: Remove monitoring logs

If your script stores logs in `/var/log/system-health/`, remove them with:

bash

```bash
sudo rm -rf /var/log/system-health/
```

Only run this if you no longer need the historical monitoring data.

### Complete uninstall (all commands together)

bash

```bash
sudo systemctl stop system-health.timer
sudo systemctl disable system-health.timer
sudo systemctl stop system-health.service

sudo rm -f /etc/systemd/system/system-health.service
sudo rm -f /etc/systemd/system/system-health.timer
sudo rm -f /usr/local/sbin/system_health.sh

sudo systemctl daemon-reload
sudo systemctl reset-failed
```

Uninstallation completeThe systemd timer, service configuration, and monitoring script will be removed. Historical logs are preserved unless you explicitly delete them.





-----

Verification: 
root@localhost:~/devops-asses-1/scripts/system_health_check# shellcheck system_health.sh
root@localhost:~/devops-asses-1/scripts/system_health_check# echo $?
0

![alt text](./assets/21-linux-script-verification.png)

