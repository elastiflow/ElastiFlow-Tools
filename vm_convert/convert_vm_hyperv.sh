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
output_file="${input_base%.vmdk}.vhdx"
temp_file="${input_file}.vhdx.temp"
vm_name="${input_base%.vmdk}"
uuid=$(uuidgen)

# VM Configuration Variables
disk_size_gb=500
memory_gb=32
num_cpus=4
memory_mb=$((memory_gb * 1024))

# Create a conversion in progress indicator
touch "$input_dir/conversion_in_progress"

# Convert the VMDK file to VHDX format
qemu-img convert -cpf vmdk -O vhdx "$input_file" "$temp_file"
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

# Create the VM definition file for Hyper-V
vm_definition="${input_dir}/${vm_name}.xml"

cat <<EOF > "$vm_definition"
<domain type='kvm'>
  <name>${vm_name}</name>
  <uuid>${uuid}</uuid>
  <memory unit='KiB'>${memory_mb}</memory>
  <vcpu placement='static'>${num_cpus}</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-2.9'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='vhdx'/>
      <source file='${input_dir}/${output_file}'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </disk>
    <interface type='network'>
      <mac address='52:54:00:83:8f:20'/>
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
