import time
import struct
import socket
import json
from scapy.all import sniff, IP, UDP, TCP

# Load configuration
with open("config.json", "r") as config_file:
    config = json.load(config_file)

COLLECTOR_IP = config.get("COLLECTOR_IP", "127.0.0.1")
COLLECTOR_PORT = config.get("COLLECTOR_PORT", 2055)
INTERFACE = config.get("INTERFACE", "eth0")
ACTIVE_TIMEOUT = config.get("ACTIVE_TIMEOUT", 60)
INACTIVE_TIMEOUT = config.get("INACTIVE_TIMEOUT", 30)

flows = {}
flow_sequence = 1
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def generate_netflow_v5_record(src_ip, dst_ip, src_port, dst_port, proto, packets, bytes_count, start_time, end_time):
    src_ip_bytes = socket.inet_aton(src_ip)
    dst_ip_bytes = socket.inet_aton(dst_ip)
    next_hop = socket.inet_aton("0.0.0.0")
    tcp_flags = 0
    tos = 0
    src_as = dst_as = src_mask = dst_mask = input_iface = output_iface = 0

    return struct.pack(
        "!4s4s4sHHIIIIHHxBBBHHBBxx",
        src_ip_bytes, dst_ip_bytes, next_hop,
        input_iface, output_iface,
        packets, bytes_count, start_time, end_time,
        src_port, dst_port, tcp_flags, proto, tos,
        src_as, dst_as, src_mask, dst_mask
    )

def create_netflow_packet(flows):
    global flow_sequence
    version = 5
    count = len(flows)
    sys_uptime = int(time.monotonic() * 1000) & 0xFFFFFFFF
    unix_secs = int(time.time())
    unix_nsecs = int((time.time() % 1) * 1e9)
    engine_type = engine_id = sampling_interval = 0

    header = struct.pack(
        "!HHIIIIBBH",
        version, count, sys_uptime, unix_secs, unix_nsecs,
        flow_sequence, engine_type, engine_id, sampling_interval
    )

    records = b""
    for key, flow in flows.items():
        src_ip, dst_ip, src_port, dst_port, proto = key
        packets, bytes_transferred, first_seen, last_seen = flow
        records += generate_netflow_v5_record(
            socket.inet_ntoa(struct.pack("!I", src_ip)),
            socket.inet_ntoa(struct.pack("!I", dst_ip)),
            src_port, dst_port, proto, packets, bytes_transferred, first_seen, last_seen
        )

    flow_sequence = (flow_sequence + 1) & 0xFFFFFFFF
    return header + records

def send_netflow():
    if not flows:
        print("No flows to export.")
        return
    print(f"Exporting {len(flows)} NetFlow records to {COLLECTOR_IP}:{COLLECTOR_PORT}")
    netflow_packet = create_netflow_packet(flows)
    sock.sendto(netflow_packet, (COLLECTOR_IP, COLLECTOR_PORT))
    flows.clear()

def packet_handler(packet):
    global flows
    current_time = int(time.monotonic() * 1000) & 0xFFFFFFFF

    if IP in packet:
        src_ip = struct.unpack("!I", socket.inet_aton(packet[IP].src))[0]
        dst_ip = struct.unpack("!I", socket.inet_aton(packet[IP].dst))[0]
        proto = packet[IP].proto
        src_port = dst_port = 0

        if UDP in packet or TCP in packet:
            src_port = packet.sport
            dst_port = packet.dport

        key = (src_ip, dst_ip, src_port, dst_port, proto)

        if key in flows:
            flows[key][0] += 1
            flows[key][1] += len(packet)
            flows[key][3] = current_time
        else:
            flows[key] = [1, len(packet), current_time, current_time]

    expired_keys = [k for k, v in flows.items() if current_time - v[3] > INACTIVE_TIMEOUT * 1000]
    for key in expired_keys:
        del flows[key]

def main():
    print(f"Starting NetFlow v5 exporter on interface: {INTERFACE}")
    try:
        while True:
            sniff(iface=INTERFACE, filter="ip", prn=packet_handler, store=0, timeout=ACTIVE_TIMEOUT)
            send_netflow()
    except KeyboardInterrupt:
        print("Shutting down...")
        send_netflow()

if __name__ == "__main__":
    main()
