#ifndef NETWORK_MONITOR_H
#define NETWORK_MONITOR_H

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/ptrace.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>

#define MAX_COMM_LEN 16
#define MAX_CMDLINE_LEN 256
#define TASK_COMM_LEN 16
#define IP_LENGTH 16

// Connection event structure sent to userspace
struct connection_event_t {
    __u64 timestamp;           // Connection timestamp
    __u32 pid;                // Process ID
    char comm[MAX_COMM_LEN];   // Process name
    char cmdline[MAX_CMDLINE_LEN]; // Command line (truncated)
    __u32 saddr;              // Source IP address
    __u32 daddr;              // Destination IP address
    __u16 sport;              // Source port
    __u16 dport;              // Destination port
    __u8 protocol;            // IP protocol (TCP=6)
};

// Perf buffer map for sending events to userspace
struct bpf_map_def SEC("maps") connections = {
    .type = BPF_MAP_TYPE_PERF_EVENT_ARRAY,
    .key_size = sizeof(__u32),
    .value_size = sizeof(__u32),
};

// Helper function to get command line from task struct
static __always_inline void get_cmdline(struct pt_regs *ctx, char *cmdline, size_t maxlen) {
    struct task_struct *task = (struct task_struct *)bpf_get_current_task();
    void *args_ptr;

    // Get argv from task struct (simplified version)
    bpf_probe_read(&args_ptr, sizeof(void *), &task->mm->arg_start);
    bpf_probe_read_user_str(cmdline, maxlen, args_ptr);
}

#endif // NETWORK_MONITOR_H