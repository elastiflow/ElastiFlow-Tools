import random
import socket
import struct
import time
import json
import ipaddress


def load_config(config_file):
    """Loads configuration from a JSON file."""
    with open(config_file, "r") as f:
        return json.load(f)


def generate_random_ip(subnet):
    """Generates a random IP address within the given subnet."""
    network = ipaddress.IPv4Network(subnet, strict=False)
    return str(random.choice(list(network.hosts())))


def generate_netflow_v5_record(base_time_ms, src_subnet, dst_subnet):
    """Generates a single NetFlow v5 record with realistic timestamps."""
    src_ip = socket.inet_aton(generate_random_ip(src_subnet))
    dst_ip = socket.inet_aton(generate_random_ip(dst_subnet))
    next_hop = socket.inet_aton("0.0.0.0")

    input_iface = random.randint(0, 65535)
    output_iface = random.randint(0, 65535)
    packets = random.randint(1, 1000)
    bytes_count = random.randint(1, 100000)
    
    # Start time is based on base_time_ms (system uptime in ms)
    start_time = base_time_ms & 0xFFFFFFFF
    # End time is a small increment from start_time
    end_time = (start_time + random.randint(1, 1000)) & 0xFFFFFFFF

    src_port = random.randint(1024, 65535)
    dst_port = random.randint(1024, 65535)
    tcp_flags = random.randint(0, 255)
    protocol = random.choice([6, 17, 1])  # TCP, UDP, or ICMP
    tos = random.randint(0, 255)
    src_as = random.randint(0, 65535)
    dst_as = random.randint(0, 65535)
    src_mask = random.randint(0, 32)
    dst_mask = random.randint(0, 32)

    record = struct.pack(
        "!4s4s4sHHHIIIHHBBBHHBBxxxxx",
        src_ip, dst_ip, next_hop, input_iface, output_iface, packets, bytes_count,
        start_time, end_time, src_port, dst_port, tcp_flags, protocol, tos,
        src_as, dst_as, src_mask, dst_mask
    )
    return record


def generate_netflow_v5_packets(flow_count, src_subnet, dst_subnet):
    """Generates NetFlow v5 packets with realistic timing and record count."""
    max_flows_per_packet = (65535 - 24) // 48  # Maximum flows per packet
    packets = []
    flow_sequence = random.randint(0, 2**32 - 1)
    base_time_ms = int(time.time() * 1000)  # System uptime in milliseconds

    for start in range(0, flow_count, max_flows_per_packet):
        flows_in_packet = flow_count - start
        if flows_in_packet > max_flows_per_packet:
            flows_in_packet = max_flows_per_packet

        sys_uptime = base_time_ms & 0xFFFFFFFF
        unix_secs = int(time.time())
        unix_nsecs = int((time.time() % 1) * 1e9) & 0xFFFFFFFF
        engine_type = 0
        engine_id = 0
        sampling_interval = 0

        header = struct.pack(
            "!HHIIIIBBH",
            5,  # Version
            flows_in_packet,
            sys_uptime,
            unix_secs,
            unix_nsecs,
            flow_sequence,
            engine_type,
            engine_id,
            sampling_interval,
        )
        flow_sequence += flows_in_packet

        records = b"".join(generate_netflow_v5_record(base_time_ms, src_subnet, dst_subnet) for _ in range(flows_in_packet))
        packets.append(header + records)

    return packets


def main():
    config = load_config("config.json")
    flows_per_second = config["flows_per_second"]
    collector_ip = config["collector_ip"]
    collector_port = config["collector_port"]
    export_to_file = config["export_to_file"]
    output_file = config["output_file"]
    source_ip_subnet = config["source_ip_subnet"]
    destination_ip_subnet = config["destination_ip_subnet"]

    if export_to_file:
        with open(output_file, "wb") as f:
            print(f"Writing NetFlow v5 records to {output_file}")
            while True:
                start_time = time.time()
                packets = generate_netflow_v5_packets(flows_per_second, source_ip_subnet, destination_ip_subnet)
                for packet in packets:
                    f.write(packet)
                elapsed_time = time.time() - start_time
                sleep_time = max(0, 1 - elapsed_time)  # Adjust to maintain a steady 1-second interval
                time.sleep(sleep_time)
    else:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        print(f"Sending NetFlow v5 records to {collector_ip}:{collector_port}")
        while True:
            start_time = time.time()
            packets = generate_netflow_v5_packets(flows_per_second, source_ip_subnet, destination_ip_subnet)
            for packet in packets:
                sock.sendto(packet, (collector_ip, collector_port))
            elapsed_time = time.time() - start_time
            sleep_time = max(0, 1 - elapsed_time)  # Adjust to maintain a steady 1-second interval
            time.sleep(sleep_time)


if __name__ == "__main__":
    main()
