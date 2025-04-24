import time
import struct
import socket
from scapy.all import sniff, IP, UDP, TCP, ICMP

# Configurations
COLLECTOR_IP = "10.101.2.148"  # Set your NetFlow collector IP
COLLECTOR_PORT = 2055  # Default NetFlow UDP port
INTERFACE = "Ethernet"  # Change to match your Windows interface name
ACTIVE_TIMEOUT = 60  # Seconds before exporting active flows
INACTIVE_TIMEOUT = 30  # Seconds before exporting idle flows

# NetFlow cache to store active flows
flows = {}
flow_sequence = 1  # Start sequence number at 1

# Create UDP socket to send NetFlow records
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def generate_netflow_v5_record(src_ip, dst_ip, src_port, dst_port, proto, packets, bytes_count, start_time, end_time):
    """
    Generates a single NetFlow v5 flow record (48 bytes) using packet data.
    """
    src_ip_bytes = socket.inet_aton(src_ip)
    dst_ip_bytes = socket.inet_aton(dst_ip)
    next_hop = socket.inet_aton("0.0.0.0")

    tcp_flags = 0
    tos = 0
    src_as = 0
    dst_as = 0
    src_mask = 0
    dst_mask = 0
    input_iface = 0
    output_iface = 0

    return struct.pack(
        "!4s4s4sHHIIIIHHxBBBHHBBxx",
        src_ip_bytes, dst_ip_bytes, next_hop,
        input_iface, output_iface,
        packets, bytes_count, start_time, end_time,
        src_port, dst_port, tcp_flags, proto, tos,
        src_as, dst_as, src_mask, dst_mask
    )

def create_netflow_packet(flows):
    """
    Constructs a NetFlow v5 packet from collected flows.
    """
    global flow_sequence
    # NetFlow v5 Header
    version = 5
    count = len(flows)
    sys_uptime = max(0, int(time.time() * 1000) & 0xFFFFFFFF)  # Ensure 32-bit range
    unix_secs = int(time.time())
    unix_nsecs = max(0, int((time.time() % 1) * 1e9) & 0xFFFFFFFF)  # Convert fraction of second to nanoseconds
    engine_type = 0
    engine_id = 0
    sampling_interval = 0

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

    flow_sequence = (flow_sequence + 1) & 0xFFFFFFFF  # Ensure it stays within 32-bit range
    return header + records

def send_netflow():
    """
    Sends the NetFlow v5 records to the collector.
    """
    if not flows:
        print("No flows to export.")
        return

    print(f"Exporting {len(flows)} NetFlow records to {COLLECTOR_IP}:{COLLECTOR_PORT}")
    netflow_packet = create_netflow_packet(flows)
    sock.sendto(netflow_packet, (COLLECTOR_IP, COLLECTOR_PORT))
    flows.clear()

def packet_handler(packet):
    """
    Processes packets, aggregates flows, and handles timeouts.
    """
    global flows
    current_time = max(0, int(time.time() * 1000) & 0xFFFFFFFF)

    if IP in packet:
        src_ip = struct.unpack("!I", socket.inet_aton(packet[IP].src))[0]
        dst_ip = struct.unpack("!I", socket.inet_aton(packet[IP].dst))[0]
        proto = packet[IP].proto
        src_port = 0
        dst_port = 0

        if UDP in packet or TCP in packet:
            src_port = packet.sport
            dst_port = packet.dport

        key = (src_ip, dst_ip, src_port, dst_port, proto)
        
        if key in flows:
            flows[key][0] += 1  # Increment packet count
            flows[key][1] += len(packet)  # Increment byte count
            flows[key][3] = current_time  # Update last seen timestamp
        else:
            flows[key] = [1, len(packet), current_time, current_time]

    # Check for timeouts
    expired_keys = [k for k, v in flows.items() if current_time - v[3] > INACTIVE_TIMEOUT]
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
