#!/bin/bash

# Check if the input file is provided
if [ -z "$1" ]; then
  echo "No input file provided"
  exit 1
fi

# Variables
input_file="$1"
input_dir=$(dirname "$input_file")
input_base=$(basename "$input_file")
output_file="${input_base%.vmdk}.qcow2"
temp_file="${input_file}.qcow2.temp"
vm_name="${input_base%.vmdk}"
uuid=$(uuidgen)

# VM Configuration Variables
disk_size_gb=500
memory_gb=32
num_cpus=4
memory_kib=$((memory_gb * 1024 * 1024))

# Generate a random MAC address
hexchars="0123456789ABCDEF"
mac="52:54:00"
for i in {1..3}; do
  mac="$mac:${hexchars:$(( $RANDOM % 16 )):1}${hexchars:$(( $RANDOM % 16 )):1}"
done

# Create a conversion in progress indicator
touch "$input_dir/conversion_in_progress"

# Convert the VMDK file to QCOW2 format
qemu-img convert -cpf vmdk -O qcow2 "$input_file" "$temp_file"
if [ $? -ne 0 ]; then
  echo "Conversion failed"
  rm -f "$input_dir/conversion_in_progress"
  exit 1
fi

# Rename the temporary file to the final output file
mv "$temp_file" "$input_dir/$output_file"
if [ $? -ne 0 ]; then
  echo "Renaming temp file failed"
  rm -f "$input_dir/conversion_in_progress"
  exit 1
fi

# Mark the conversion as done
mv "$input_dir/conversion_in_progress" "$input_dir/conversion_done"

# Create the VM definition file
vm_definition="${input_dir}/${vm_name}.xml"

cat <<EOF > "$vm_definition"
<!--
WARNING: THIS IS AN AUTO-GENERATED FILE. CHANGES TO IT ARE LIKELY TO BE
OVERWRITTEN AND LOST. Changes to this xml configuration should be made using:
  virsh edit ${vm_name}
or other application using the libvirt API.
-->

<domain type='kvm'>
  <name>${vm_name}</name>
  <uuid>${uuid}</uuid>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://ubuntu.com/ubuntu/24.04"/>
    </libosinfo:libosinfo>
  </metadata>
  <memory unit='KiB'>${memory_kib}</memory>
  <currentMemory unit='KiB'>${memory_kib}</currentMemory>
  <vcpu placement='static'>${num_cpus}</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-8.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <vmport state='off'/>
  </features>
  <cpu mode='host-passthrough' check='none' migratable='on'/>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${input_dir}/${output_file}'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </disk>
    <interface type='network'>
      <mac address='${mac}'/>
      <source network='default'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <graphics type='spice' autoport='yes'>
      <listen type='none'/>
    </graphics>
    <video>
      <model type='qxl' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
    </video>
  </devices>
</domain>
EOF

if [ ! -f "$vm_definition" ]; then
  echo "Failed to create VM definition file"
  exit 1
fi

# Define the VM using virsh
sudo virsh define "$vm_definition"
if [ $? -ne 0 ]; then
  echo "Failed to define VM"
  exit 1
fi

echo "Conversion and VM definition complete. VM is defined as '${vm_name}' with configuration file '${vm_definition}'."
