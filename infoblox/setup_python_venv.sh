#!/bin/bash

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null
then
    echo "Python3 is not installed. Please install Python3."
    exit 1
fi

# Check if pip is installed
if ! command -v pip &> /dev/null
then
    echo "pip is not installed. Installing pip..."
    sudo apt update
    sudo apt install -y python3-pip
fi

# Check if python3.10-venv is installed
if ! deactivate &> /dev/null
then
    echo "python3.10-venv is not installed. Installing python3.10-venv..."
    sudo apt update
    sudo apt install -y python3.10-venv
fi

# Create a virtual environment
echo "Creating python3 virtual environment"
python3 -m venv .venv

# Activate the virtual environment
echo "Installing python libraries: ibx-sdk pyyaml"
source .venv/bin/activate

# Install the required packages

pip install git+https://github.com/Infoblox-PS/ibx-sdk
pip install ruamel.yaml

deactivate

echo "Setup complete."
