#ifndef C_PROCESS_STATS_H
#define C_PROCESS_STATS_H

#include <stdint.h>

typedef struct {
    int32_t pid;
    uint64_t start_ticks;
    uint64_t cpu_user_ticks;
    uint64_t cpu_system_ticks;
    uint64_t sampled_ticks;
    uint64_t footprint_bytes;
    char executable_path[4096];
    char name[256];
} MSProcessReading;

// Returns a process count, or a nonpositive value if enumeration failed.
int ms_list_process_ids(int32_t *pids, int capacity);

// Returns zero on success, or an errno value for inaccessible/exited processes.
int ms_read_process(int32_t pid, MSProcessReading *reading);

#endif
