#include "CProcessStats.h"

#include <errno.h>
#include <limits.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <string.h>
#include <sys/resource.h>

int ms_list_process_ids(int32_t *pids, int capacity) {
    if (capacity < 0 || capacity > INT_MAX / (int)sizeof(int32_t)) {
        errno = EINVAL;
        return -1;
    }
    return proc_listallpids(pids, capacity * (int)sizeof(int32_t));
}

int ms_read_process(int32_t pid, MSProcessReading *reading) {
    struct rusage_info_v0 before = {0};
    struct rusage_info_v0 after = {0};
    memset(reading, 0, sizeof(*reading));
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&before) != 0) {
        return errno ? errno : EIO;
    }

    // Metadata can be unavailable while resource usage remains accessible.
    // Zero initialization and the final terminators make both strings bounded.
    proc_pidpath(pid, reading->executable_path, sizeof(reading->executable_path));
    proc_name(pid, reading->name, sizeof(reading->name));
    reading->executable_path[sizeof(reading->executable_path) - 1] = '\0';
    reading->name[sizeof(reading->name) - 1] = '\0';

    // Recheck identity after metadata collection to reject PID reuse or an
    // executable replacement during the read. exec preserves the start time.
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&after) != 0) {
        return errno ? errno : EIO;
    }
    if (before.ri_proc_start_abstime != after.ri_proc_start_abstime ||
        memcmp(before.ri_uuid, after.ri_uuid, sizeof(before.ri_uuid)) != 0 ||
        after.ri_proc_exit_abstime != 0) {
        return ESRCH;
    }

    reading->pid = pid;
    reading->start_ticks = after.ri_proc_start_abstime;
    // XNU exposes these CPU counters in Mach absolute time units. Keep the
    // interval timestamp in the same units, including on Apple Silicon.
    reading->cpu_user_ticks = after.ri_user_time;
    reading->cpu_system_ticks = after.ri_system_time;
    reading->sampled_ticks = mach_absolute_time();
    reading->footprint_bytes = after.ri_phys_footprint;
    return 0;
}
