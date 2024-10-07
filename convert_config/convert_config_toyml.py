def convert_env_to_yaml(input_file, output_file):
    # Open and read the input file
    with open(input_file, 'r') as file:
        lines = file.readlines()

    # Write the output to the YAML file
    with open(output_file, 'w') as yaml_file:
        for line in lines:
            # Remove newline characters and skip empty lines
            line = line.strip()
            if not line:
                continue
            
            # Handle commented environment lines
            if line.startswith('#Environment="') and line.endswith('"'):
                clean_var = line[len('#Environment="'):-1]
                if '=' in clean_var:
                    key = clean_var.split('=', 1)[0]
                    # Write the commented-out YAML format
                    yaml_file.write(f'#{key}: ""\n')
                else:
                    # Skip lines that don't match the expected format
                    continue
            
            # Handle environment lines
            elif line.startswith('Environment="') and line.endswith('"'):
                clean_var = line[len('Environment="'):-1]
                if '=' in clean_var:
                    key, value = clean_var.split('=', 1)
                    # Add quotes around the value if it's not a number
                    if not value.isdigit():
                        value = f'"{value}"'
                    yaml_file.write(f'{key}: {value}\n')
                else:
                    # Skip lines that don't match the expected format
                    continue
            
            # Handle other commented lines
            elif line.startswith('#'):
                yaml_file.write(f'{line}\n')
                continue

# Specify the input and output file paths
input_file = 'flowcoll.conf'  # Replace with your actual input file name
output_file = 'flowcoll.yml'

# Call the function to perform the conversion
convert_env_to_yaml(input_file, output_file)
