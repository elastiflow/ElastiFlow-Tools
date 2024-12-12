## Author
[O.J. Wolanyk]


Purpose:
==========================
This script allows you to easily convert a virtual appliance from VMWare format (vmdk) to KVM / Proxmox (qcow2) format. It accepts either a vmdk file or a zipped vmdk file.

Upon convertion completion, you will see a 0 length file called "conversion_done" which indicates the conversion is complete. 
You will also see the resulting qcow2 and xml file along with an archive of the two files "file.tar.gz".

Basic usage:
==========================
./convert_vm_qcow2.sh /path/to/virtual_appliance/vmdk_file.vmdk OR /path/to/virtual_appliance.zip

After a few minutes, you will see a you will see a 0 length file called "conversion_done" which indicates the conversion is complete. 
You will also see the resulting qcow2 and xml file along with an archive of the two files "file.tar.gz".


Gnome shell integration:
==========================
Put convert_to_qcow2.desktop file in: /usr/share/kio/servicemenus
Put convert_vm_qcow2.sh in: /home/user/scripts/

Then, right click on your vmdk file, actions, convert vmdk to qcow2.
