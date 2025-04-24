import random
import socket
import struct
import time
import json
import ipaddress
import multiprocessing
import signal
import sys

FLOWS_PER_PROCESS = 4000  
processes = []  

def load_config(config_file):
    """Loads configuration from a JSON file."""
    with open(config_file, "r") as f:
        return json.load(f)

def generate_random_ip_from_subnet(subnet):
    """Generates a random IP address from a given subnet as a string."""
    network = ipaddress.IPv4Network(subnet, strict=False)
    return str(random.choice(list(network.hosts())))  # ✅ Convert to string

def parse_port_config(port_config):
    """Parses port configuration from config.json."""
    if port_config.lower() == "random":
        return lambda: random.randint(1024, 65535)  # Random ephemeral port
    elif "-" in port_config:  
        start, end = map(int, port_config.split("-"))
        return lambda: random.randint(start, end)
    elif "," in port_config:  
        ports = list(map(int, port_config.split(",")))
        return lambda: random.choice(ports)
    else:  
        try:
            single_port = int(port_config)
            return lambda: single_port
        except ValueError:
            raise ValueError(f"Invalid port configuration: {port_config}")

def generate_netflow_v5_packet(src_ip, dst_ip, flow_sequence):
    """Generates a valid NetFlow v5 packet with multiple records."""
    flow_count = 10  
    netflow_header = struct.pack(
        "!HHIIIIBBH",
        5,  
        flow_count,  
        int(time.time() * 1000) & 0xFFFFFFFF,  
        int(time.time()),  
        int((time.time() % 1) * 1e9) & 0xFFFFFFFF,  
        flow_sequence,
        0,  
        0,  
        0   
    )

    flow_records = b""
    for _ in range(flow_count):
        new_record = generate_netflow_v5_record()
        flow_records += new_record

    udp_payload = netflow_header + flow_records  
    udp_header = struct.pack("!HHHH", 2055, 2055, 8 + len(udp_payload), 0)  
    ip_header = struct.pack("!BBHHHBBH4s4s",
                            0x45, 0, 20 + len(udp_header) + len(udp_payload), 0,
                            0, 64, socket.IPPROTO_UDP, 0,
                            socket.inet_aton(src_ip), socket.inet_aton(dst_ip))

    return ip_header + udp_header + udp_payload

def worker(config, flows_per_process, ip_list):
    """Worker function to generate and send NetFlow packets."""
    collector_ip = config["collector_ip"]
    collector_port = config["collector_port"]
    sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    flow_sequence = random.randint(0, 2**32 - 1)

    try:
        while True:
            for _ in range(flows_per_process):
                src_ip = str(random.choice(ip_list))  # ✅ Convert to string!
                try:
                    packet = generate_netflow_v5_packet(src_ip, collector_ip, flow_sequence)
                    sock.sendto(packet, (collector_ip, collector_port))
                    flow_sequence += 1
                except Exception as e:
                    if "test a child process" not in str(e):  
                        print(f"Error sending packet from {src_ip}: {e}")
            time.sleep(1)
    except KeyboardInterrupt:
        print(f"\n[Worker] Process {multiprocessing.current_process().pid} exiting...")
    finally:
        sock.close()  
        sys.exit(0)

def signal_handler(sig, frame):
    """Handle Ctrl+C (SIGINT) and cleanly terminate all processes."""
    global processes
    print("\n[INFO] Stopping NetFlow generator...")

    if processes:
        for p in processes:
            if p and p.is_alive():  
                p.terminate()
        for p in processes:
            p.join()

    sys.exit(0)

def generate_netflow_v5_record():
    """Generates a single NetFlow v5 flow record (48 bytes) with configurable ports."""
    config = load_config("config.json")

    source_subnet = config["source_ip_subnet"]
    destination_subnet = config["destination_ip_subnet"]

    # ✅ Define port selection functions inside this function
    get_src_port = parse_port_config(config.get("source_ports", "random"))
    get_dst_port = parse_port_config(config.get("destination_ports", "random"))

    src_ip = generate_random_ip_from_subnet(source_subnet)
    dst_ip = generate_random_ip_from_subnet(destination_subnet)

    src_ip_bytes = socket.inet_aton(src_ip)
    dst_ip_bytes = socket.inet_aton(dst_ip)
    next_hop = socket.inet_aton("0.0.0.0")

    packets = random.randint(1, 1000)
    bytes_count = random.randint(1, 100000)

    start_time = int(time.time() * 1000) & 0xFFFFFFFF
    end_time = (start_time + random.randint(1, 1000)) & 0xFFFFFFFF

    src_port = get_src_port()  # ✅ Call function to get port
    dst_port = get_dst_port()  # ✅ Call function to get port
    tcp_flags = random.randint(0, 255)
    protocol = random.choice([6, 17])  
    tos = random.randint(0, 255)
    src_as = random.randint(0, 65535)
    dst_as = random.randint(0, 65535)
    src_mask = random.randint(0, 32)
    dst_mask = random.randint(0, 32)

    input_iface = random.randint(17000, 17100)
    output_iface = random.randint(17000, 17100)

    while output_iface == input_iface:
        output_iface = random.randint(17000, 17100)

    return struct.pack(
        "!4s4s4sHHIIIIHHxBBBHHBBxx",
        src_ip_bytes, dst_ip_bytes, next_hop, 
        input_iface, output_iface,
        packets, bytes_count, start_time, end_time,
        src_port, dst_port, tcp_flags, protocol, tos,  
        src_as, dst_as, src_mask, dst_mask
    )

def main():
    global processes  

    config = load_config("config.json")
    flows_per_second = config["flows_per_second"]
    number_of_exporters = config.get("number_of_exporters", 10000)
    source_packet_subnet = config["source_packet_subnet"]

    num_processes = max(1, (flows_per_second + FLOWS_PER_PROCESS - 1) // FLOWS_PER_PROCESS)

    base_network = ipaddress.IPv4Network(source_packet_subnet)
    ip_list = list(base_network.hosts())[:number_of_exporters]

    print(f"Spawning {num_processes} processes to handle {flows_per_second} flows per second.")
    print(f"Using {number_of_exporters} source IPs from {source_packet_subnet} for NetFlow packets.")

    signal.signal(signal.SIGINT, signal_handler)  

    try:
        for i in range(num_processes):
            flows_for_this_process = min(FLOWS_PER_PROCESS, flows_per_second - i * FLOWS_PER_PROCESS)
            p = multiprocessing.Process(target=worker, args=(config, flows_for_this_process, ip_list))
            processes.append(p)
            p.start()

        for p in processes:
            p.join()

    except KeyboardInterrupt:
        signal_handler(None, None)  

if __name__ == "__main__":
    main()%  