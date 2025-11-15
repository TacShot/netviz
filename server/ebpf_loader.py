"""
eBPF Loader Module
Handles loading, attachment, and cleanup of eBPF programs
"""

import asyncio
import ctypes
import logging
import os
import sys
from pathlib import Path
from typing import Optional, Dict, Any

from bcc import BPF

logger = logging.getLogger(__name__)

class EBPFLoader:
    """Manages eBPF program lifecycle using BCC"""

    def __init__(self, connection_handler):
        self.connection_handler = connection_handler
        self.bpf: Optional[BPF] = None
        self.loaded = False
        self.retry_count = 0
        self.max_retries = 3

        # Paths
        self.ebpf_dir = Path(__file__).parent.parent / "ebpf"
        self.c_file = self.ebpf_dir / "network_monitor.c"

        # C program text for embedding
        self.c_program = """
#include <linux/bpf.h>
#include <linux/ptrace.h>
#include <linux/tcp.h>
#include <linux/inet.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define MAX_COMM_LEN 16
#define MAX_CMDLINE_LEN 256

struct connection_event_t {
    u64 timestamp;
    u32 pid;
    char comm[MAX_COMM_LEN];
    char cmdline[MAX_CMDLINE_LEN];
    u32 saddr;
    u32 daddr;
    u16 sport;
    u16 dport;
    u8 protocol;
};

BPF_PERF_OUTPUT(connections);

static __always_inline u32 get_ip_from_sock(struct sock *sk) {
    u32 saddr;
    bpf_probe_read(&saddr, sizeof(saddr), &sk->__sk_common.skc_rcv_saddr);
    return ntohl(saddr);
}

static __always_inline u32 get_daddr_from_sock(struct sock *sk) {
    u32 daddr;
    bpf_probe_read(&daddr, sizeof(daddr), &sk->__sk_common.skc_daddr);
    return ntohl(daddr);
}

static __always_inline u16 get_port_from_sock(struct sock *sk, bool is_dest) {
    u16 port;
    if (is_dest) {
        bpf_probe_read(&port, sizeof(port), &sk->__sk_common.skc_dport);
        return ntohs(port);
    } else {
        bpf_probe_read(&port, sizeof(port), &sk->__sk_common.skc_num);
        return port;
    }
}

int trace_tcp_connect(struct pt_regs *ctx) {
    struct sock *sk = (struct sock *)PT_REGS_PARM1(ctx);
    struct connection_event_t event = {};
    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid >> 32;

    if (!sk) {
        return 0;
    }

    event.timestamp = bpf_ktime_get_ns();
    event.pid = pid;
    event.saddr = get_ip_from_sock(sk);
    event.daddr = get_daddr_from_sock(sk);
    event.sport = get_port_from_sock(sk, false);
    event.dport = get_port_from_sock(sk, true);
    event.protocol = 6; // TCP

    bpf_get_current_comm(&event.comm, sizeof(event.comm));
    __builtin_memcpy(event.cmdline, event.comm, MAX_COMM_LEN);

    connections.perf_submit(ctx, &event, sizeof(event));
    return 0;
}

int trace_inet_sock_set_state(struct trace_event_raw_inet_sock_set_state *ctx) {
    struct connection_event_t event = {};
    u64 pid_tgid = bpf_get_current_pid_tgid();
    u32 pid = pid_tgid >> 32;

    if (ctx->protocol != IPPROTO_TCP || ctx->newstate != TCP_ESTABLISHED) {
        return 0;
    }

    event.timestamp = bpf_ktime_get_ns();
    event.pid = pid;
    event.saddr = ctx->saddr;
    event.daddr = ctx->daddr;
    event.sport = ctx->sport;
    event.dport = ctx->dport;
    event.protocol = ctx->protocol;

    bpf_get_current_comm(&event.comm, sizeof(event.comm));
    __builtin_memcpy(event.cmdline, event.comm, MAX_COMM_LEN);

    connections.perf_submit(ctx, &event, sizeof(event));
    return 0;
}
"""

    async def load_and_attach(self) -> bool:
        """Load and attach eBPF program to kernel"""
        try:
            logger.info("Loading eBPF program...")

            # Check if running as root
            if os.geteuid() != 0:
                logger.warning("eBPF program requires root privileges. Running without network monitoring.")
                return False

            # Initialize BPF program
            self.bpf = BPF(text=self.c_program)

            # Try to attach to tcp_connect kprobe first
            try:
                self.bpf.attach_kprobe(event="tcp_connect", fn_name="trace_tcp_connect")
                logger.info("Attached to tcp_connect kprobe")
            except Exception as e:
                logger.warning(f"Failed to attach to tcp_connect kprobe: {e}")
                # Try tracepoint instead
                try:
                    self.bpf.attach_tracepoint(
                        tp="inet_sock_set_state",
                        fn_name="trace_inet_sock_set_state"
                    )
                    logger.info("Attached to inet_sock_set_state tracepoint")
                except Exception as e2:
                    logger.error(f"Failed to attach to tracepoint: {e2}")
                    raise

            # Setup perf buffer for data reception
            self.bpf["connections"].open_perf_buffer(
                self.handle_connection_event,
                page_cnt=64
            )

            # Start background task to poll perf buffer
            asyncio.create_task(self.poll_perf_buffer())

            self.loaded = True
            logger.info("eBPF program loaded and attached successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to load eBPF program: {e}")
            self.retry_count += 1

            if self.retry_count < self.max_retries:
                logger.info(f"Retrying in 2 seconds... (attempt {self.retry_count + 1}/{self.max_retries})")
                await asyncio.sleep(2)
                return await self.load_and_attach()
            else:
                logger.error("Max retries reached. Giving up.")
                return False

    def handle_connection_event(self, cpu, data, size):
        """Handle connection events from eBPF program"""
        try:
            # Parse the event data
            event = self.bpf["connections"].event(data)

            # Convert to dictionary format
            event_dict = {
                'timestamp': event.timestamp,
                'pid': event.pid,
                'comm': event.comm.decode('utf-8', errors='ignore').rstrip('\x00'),
                'cmdline': event.cmdline.decode('utf-8', errors='ignore').rstrip('\x00'),
                'saddr': event.saddr,
                'daddr': event.daddr,
                'sport': event.sport,
                'dport': event.dport,
                'protocol': event.protocol
            }

            # Forward to connection handler
            if self.connection_handler:
                asyncio.create_task(
                    self.connection_handler.process_connection_event(event_dict)
                )

        except Exception as e:
            logger.error(f"Error processing eBPF event: {e}")

    async def poll_perf_buffer(self):
        """Background task to poll perf buffer for events"""
        while self.loaded:
            try:
                self.bpf.perf_buffer_poll(100)  # 100ms timeout
                await asyncio.sleep(0.001)  # Yield to event loop
            except Exception as e:
                if not self.loaded:  # Expected during shutdown
                    break
                logger.error(f"Error polling perf buffer: {e}")
                await asyncio.sleep(0.1)

    async def cleanup(self):
        """Clean up eBPF resources"""
        logger.info("Cleaning up eBPF program...")

        self.loaded = False

        if self.bpf:
            try:
                # Cleanup perf buffer
                if "connections" in self.bpf:
                    self.bpf["connections"].close()

                # Cleanup BPF program
                self.bpf.cleanup()
            except Exception as e:
                logger.error(f"Error during eBPF cleanup: {e}")

        self.bpf = None
        logger.info("eBPF cleanup complete")

    def is_loaded(self) -> bool:
        """Check if eBPF program is currently loaded"""
        return self.loaded and self.bpf is not None

    def get_statistics(self) -> Dict[str, Any]:
        """Get eBPF program statistics"""
        if not self.is_loaded():
            return {"loaded": False}

        try:
            return {
                "loaded": True,
                "retry_count": self.retry_count,
                "perf_buffer_active": "connections" in self.bpf if self.bpf else False
            }
        except Exception as e:
            logger.error(f"Error getting eBPF statistics: {e}")
            return {"loaded": False, "error": str(e)}