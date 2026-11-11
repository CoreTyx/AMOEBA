#!/usr/bin/env bash
# PYNQ's Python with XRT, which the DDR sink's buffers need (forte/device.py
# cma_allocate):  sudo ./pynq_python.sh run_cmd.py ...
source /etc/profile.d/xrt_setup.sh > /dev/null
source /etc/profile.d/pynq_venv.sh > /dev/null
exec python3 "$@"
