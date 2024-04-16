printf "\n\n\n*********Configuring JVM memory usage...\n\n"
# Get the total installed memory from /proc/meminfo in kB
total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
# Convert the memory from kB to GB and divide by 2 to get 1/2, using bc for floating point support
one_half_mem_gb=$(echo "$total_mem_kb / 1024 / 1024 / 2" | bc -l)
# Use printf to round the floating point number to an integer
rounded_mem_gb=$(printf "%.0f" $one_half_mem_gb)
# Ensure the value does not exceed 31GB
if [ $rounded_mem_gb -gt 31 ]; then
    jvm_mem_gb=31
else
    jvm_mem_gb=$rounded_mem_gb
fi
# Prepare the JVM options string with the calculated memory size
jvm_options="-Xms${jvm_mem_gb}g\n-Xmx${jvm_mem_gb}g"
# Echo the options and use tee to write to the file
#comment out all current instances of -Xms in the jvm.options file
sudo sed -i '/^-Xm/s/^/#/' /etc/opensearch/jvm.options
echo -e $jvm_options | tee /etc/opensearch/jvm.options > /dev/null
echo "OpenSearch JVM options set to use $jvm_mem_gb GB for both -Xms and -Xmx."
