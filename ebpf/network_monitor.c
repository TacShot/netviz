#include <linux/bpf.h>
#include <linux/ptrace.h>
#include <linux/tcp.h>
#include <linux/inet.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include "network_monitor.h"

// License for eBPF loader
char _license[] SEC("license") = "GPL";

// Function to convert IPv4 address from struct to __u32
static __always_inline __u32 get_ip_from_sock(struct sock *sk) {
    __be32 saddr;

    // Get source address from socket
    bpf_probe_read(&saddr, sizeof(saddr), &sk->__sk_common.skc_rcv_saddr);
    return (__u32)ntohl(saddr);
}

static __always_inline __u32 get_daddr_from_sock(struct sock *sk) {
    __be32 daddr;

    // Get destination address from socket
    bpf_probe_read(&daddr, sizeof(daddr), &sk->__sk_common.skc_daddr);
    return (__u32)ntohl(daddr);
}

static __always_inline __u16 get_port_from_sock(struct sock *sk, bool is_dest) {
    __u16 port;

    if (is_dest) {
        bpf_probe_read(&port, sizeof(port), &sk->__sk_common.skc_dport);
        return ntohs(port);
    } else {
        bpf_probe_read(&port, sizeof(port), &sk->__sk_common.skc_num);
        return port;
    }
}

// Main hook function for tcp_connect
SEC("kprobe/tcp_connect")
int trace_tcp_connect(struct pt_regs *ctx) {
    struct sock *sk;
    struct connection_event_t event = {};
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u32 tid = (__u32)pid_tgid;

    // Get socket pointer from first argument
    sk = (struct sock *)PT_REGS_PARM1(ctx);
    if (!sk) {
        return 0;
    }

    // Fill connection event structure
    event.timestamp = bpf_ktime_get_ns();
    event.pid = pid;
    event.saddr = get_ip_from_sock(sk);
    event.daddr = get_daddr_from_sock(sk);
    event.sport = get_port_from_sock(sk, false);
    event.dport = get_port_from_sock(sk, true);
    event.protocol = 6; // TCP

    // Get process name
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    // Get command line (simplified - just use comm for now)
    __builtin_memcpy(event.cmdline, event.comm, MAX_COMM_LEN);

    // Send event to userspace via perf buffer
    bpf_perf_event_output(ctx, &connections, BPF_F_CURRENT_CPU, &event, sizeof(event));

    return 0;
}

// Alternative hook using tracepoints for more recent kernels
SEC("tracepoint/inet_sock_set_state")
int trace_inet_sock_set_state(struct trace_event_raw_inet_sock_set_state *ctx) {
    struct connection_event_t event = {};
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;

    // Filter for TCP connections only
    if (ctx->protocol != IPPROTO_TCP) {
        return 0;
    }

    // Filter for connection establishment events
    if (ctx->newstate != TCP_ESTABLISHED) {
        return 0;
    }

    // Fill connection event structure
    event.timestamp = bpf_ktime_get_ns();
    event.pid = pid;
    event.saddr = ctx->saddr;
    event.daddr = ctx->daddr;
    event.sport = ctx->sport;
    event.dport = ctx->dport;
    event.protocol = ctx->protocol;

    // Get process name
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    // Get command line (simplified)
    __builtin_memcpy(event.cmdline, event.comm, MAX_COMM_LEN);

    // Send event to userspace via perf buffer
    bpf_perf_event_output(ctx, &connections, BPF_F_CURRENT_CPU, &event, sizeof(event));

    return 0;
}