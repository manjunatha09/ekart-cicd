#!/bin/bash
# Prints your current public IP in CIDR form, ready to paste into
# terraform.tfvars as `admin_cidr`.
set -euo pipefail

IP=$(curl -fsSL https://checkip.amazonaws.com)
echo "${IP}/32"
