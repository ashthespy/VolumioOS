#!/usr/bin/env bash
# shellcheck disable=SC2034

### Setup for x86_i386 devices
# Import the x86 base family configuration
# shellcheck source=./recipes/devices/families/x86.sh
source "${SRC}"/recipes/devices/families/x86.sh

# And only adjust the bits that are different
ARCH="i386"
BUILD="x86"
DEVICENAME="x86"
