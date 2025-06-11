import socket
import struct
import time
import json
from scapy.all import sniff, IP, TCP, UDP, Raw

# Load configuration from external file
with open("config.json", "r") as config_file:
    config = json.load(config_file)

COLLECTOR_IP = config.get("COLLECTOR_IP", "127.0.0.1")
COLLECTOR_PORT = config.get("COLLECTOR_PORT", 2055)
TEMPLATE_ID = config.get("TEMPLATE_ID", 256)
DOMAIN_ID = config.get("DOMAIN_ID", 1234)
INTERFACE = config.get("INTERFACE", "eth0")
ACTIVE_TIMEOUT = config.get("ACTIVE_TIMEOUT", 60)
INACTIVE_TIMEOUT = config.get("INACTIVE_TIMEOUT", 30)
EXPORTER_PORT = config.get("EXPORTER_PORT", 4739)
TEMPLATE_INTERVAL = config.get("TEMPLATE_INTERVAL", 300)

ENTERPRISE_FIELDS_CFG = config.get("ENTERPRISE_FIELDS", {})
PEN = ENTERPRISE_FIELDS_CFG.get("PEN", 35632)
FIELD_CONFIG = {
    "http_url": ENTERPRISE_FIELDS_CFG.get("http_url", {"id": 100, "length": 128}),
    "http_ua": ENTERPRISE_FIELDS_CFG.get("http_ua", {"id": 101, "length": 128}),
    "http_site": ENTERPRISE_FIELDS_CFG.get("http_site", {"id": 102, "length": 64})
}

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", EXPORTER_PORT))

TEMPLATE_FIELDS = [
    (8, 4),    # sourceIPv4Address
    (12, 4),   # destinationIPv4Address
    (7, 2),    # sourceTransportPort
    (11, 2),   # destinationTransportPort
    (4, 1),    # protocolIdentifier
    (6, 1),    # tcpControlBits
    (2, 8),    # packetDeltaCount
    (1, 8),    # octetDeltaCount
    ((FIELD_CONFIG['http_url']['id'] | 0x8000), FIELD_CONFIG['http_url']['length'], PEN),
    ((FIELD_CONFIG['http_ua']['id'] | 0x8000), FIELD_CONFIG['http_ua']['length'], PEN),
    ((FIELD_CONFIG['http_site']['id'] | 0x8000), FIELD_CONFIG['http_site']['length'], PEN)
]

flows = {}
flow_sequence = 1
last_template_time = 0

MAX_IPFIX_PAYLOAD_SIZE = 65400
MAX_RECORDS_PER_PACKET = 10

def ipfix_header(length, export_time, seq):
    return struct.pack("!HHIII", 10, length, export_time, seq, DOMAIN_ID)

def create_template_record():
    header = struct.pack("!HH", TEMPLATE_ID, len(TEMPLATE_FIELDS))
    fields = b""
    for field in TEMPLATE_FIELDS:
        if isinstance(field, tuple) and len(field) == 3:
            fields += struct.pack("!HHI", field[0], field[1], field[2])
        else:
            fields += struct.pack("!HH", field[0], field[1])
    return header + fields

def send_template(sequence_number):
    global last_template_time
    export_time = int(time.time())
    template_record = create_template_record()
    template_set_header = struct.pack("!HH", 2, len(template_record) + 4)
    payload = template_set_header + template_record
    ipfix_msg = ipfix_header(len(payload) + 16, export_time, sequence_number) + payload
    sock.sendto(ipfix_msg, (COLLECTOR_IP, COLLECTOR_PORT))
    last_template_time = time.time()
    print(f"[+] Template sent, sequence={sequence_number} at {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_template_time))}")

def pack_http_field(text, length):
    b = text.encode(errors='ignore')[:length]
    return b + b'\x00' * (length - len(b))

def create_data_record(flow):
    src_ip = socket.inet_aton(flow['src_ip'])
    dst_ip = socket.inet_aton(flow['dst_ip'])
    src_port = struct.pack("!H", flow['src_port'])
    dst_port = struct.pack("!H", flow['dst_port'])
    proto = struct.pack("!B", flow['proto'])
    tcp_flags = struct.pack("!B", int(flow['tcp_flags']))
    packets = struct.pack("!Q", flow['packets'])
    bytes_sent = struct.pack("!Q", flow['bytes'])
    http_url = pack_http_field(flow.get('http_url', ''), FIELD_CONFIG['http_url']['length'])
    http_ua = pack_http_field(flow.get('http_ua', ''), FIELD_CONFIG['http_ua']['length'])
    http_site = pack_http_field(flow.get('http_site', ''), FIELD_CONFIG['http_site']['length'])
    return src_ip + dst_ip + src_port + dst_port + proto + tcp_flags + packets + bytes_sent + http_url + http_ua + http_site

def send_data_records(sequence_number):
    if not flows:
        return

    export_time = int(time.time())
    current_payload = b""
    record_count = 0

    for key, flow in flows.items():
        record = create_data_record(flow)
        if (len(current_payload) + len(record) > MAX_IPFIX_PAYLOAD_SIZE) or (record_count >= MAX_RECORDS_PER_PACKET):
            set_header = struct.pack("!HH", TEMPLATE_ID, len(current_payload) + 4)
            payload = set_header + current_payload
            ipfix_msg = ipfix_header(len(payload) + 16, export_time, sequence_number) + payload
            sock.sendto(ipfix_msg, (COLLECTOR_IP, COLLECTOR_PORT))
            print(f"[+] Exported batch of IPFIX records, sequence={sequence_number}, records={record_count}")
            sequence_number += 1
            current_payload = b""
            record_count = 0

        current_payload += record
        record_count += 1

    if current_payload:
        set_header = struct.pack("!HH", TEMPLATE_ID, len(current_payload) + 4)
        payload = set_header + current_payload
        ipfix_msg = ipfix_header(len(payload) + 16, export_time, sequence_number) + payload
        sock.sendto(ipfix_msg, (COLLECTOR_IP, COLLECTOR_PORT))
        print(f"[+] Exported final batch of {record_count} IPFIX records, sequence={sequence_number}")
    print(f"[i] Template last sent at {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_template_time))}")

    flows.clear()

def extract_http_headers(payload):
    try:
        text = payload.decode(errors='ignore')
        lines = text.split("\r\n")
        url = ua = host = ""
        for line in lines:
            if line.startswith("GET") or line.startswith("POST"):
                parts = line.split()
                if len(parts) > 1:
                    url = parts[1]
            elif line.lower().startswith("host:"):
                host = line.split(":", 1)[1].strip()
            elif line.lower().startswith("user-agent:"):
                ua = line.split(":", 1)[1].strip()
        return url, ua, host
    except Exception:
        return "", "", ""

def packet_handler(packet):
    global flows
    current_time = int(time.monotonic() * 1000) & 0xFFFFFFFF

    if IP in packet:
        src_ip = packet[IP].src
        dst_ip = packet[IP].dst
        proto = packet[IP].proto
        src_port = dst_port = 0
        tcp_flags = 0
        http_url = http_ua = http_site = ""

        if TCP in packet:
            src_port = packet[TCP].sport
            dst_port = packet[TCP].dport
            tcp_flags = int(packet[TCP].flags)
            if dst_port == 80 and packet.haslayer(Raw):
                http_url, http_ua, http_site = extract_http_headers(bytes(packet[Raw].load))
        elif UDP in packet:
            src_port = packet[UDP].sport
            dst_port = packet[UDP].dport

        key = (src_ip, dst_ip, src_port, dst_port, proto)

        if key in flows:
            flows[key]['packets'] += 1
            flows[key]['bytes'] += len(packet)
        else:
            flows[key] = {
                'src_ip': src_ip,
                'dst_ip': dst_ip,
                'src_port': src_port,
                'dst_port': dst_port,
                'proto': proto,
                'tcp_flags': tcp_flags,
                'packets': 1,
                'bytes': len(packet),
                'http_url': http_url,
                'http_ua': http_ua,
                'http_site': http_site
            }

def main():
    global flow_sequence
    print(f"[+] Starting IPFIX exporter on interface: {INTERFACE} from source port {EXPORTER_PORT}")
    send_template(flow_sequence)
    flow_sequence += 1
    try:
        while True:
            sniff(iface=INTERFACE, filter="ip", prn=packet_handler, store=0, timeout=ACTIVE_TIMEOUT)
            if time.time() - last_template_time > TEMPLATE_INTERVAL:
                send_template(flow_sequence)
                flow_sequence += 1
            flow_sequence += 1
            send_data_records(flow_sequence)
    except KeyboardInterrupt:
        print("[!] Interrupted. Sending remaining flows.")
        send_data_records(flow_sequence)

if __name__ == "__main__":
    main()
