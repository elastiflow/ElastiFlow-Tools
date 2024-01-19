#!/bin/bash

touch ~/elastiflow_va_install_log.txt
./install2.sh 2>&1 | sudo tee ~/elastiflow_va_install_log.txt
