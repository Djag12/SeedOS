# SeedOS

**First published on my previous account (from memory):** March 2026  
**Republished under Djag12:** November 6, 2026

SeedOS boots from a BIOS disk image and runs a client, a serial driver and a clock driver in separate address spaces. The client holds a capability for each endpoint. A call enters the kernel, switches to the receiving driver and returns a reply to the client.

## Boot and test

Use x86 Linux or Ubuntu in WSL on an x86 Windows machine. Install GCC, GNU binutils, Make, Python 3, QEMU for x86 and SeaBIOS. Run `make test` to build the image, boot it and check the serial output.

The recovery test deliberately crashes each driver 500 times. The kernel restarts the driver and preserves the pending request. The saved log in `results/seedos.log` records 1,000 recoveries and 100,002 completed client round trips.

## Measure IPC

Run `make benchmark` for the emulator timing. The saved software emulation run completed one million verified round trips at 37,034 per second. To test the 500,000 target on hardware, run `make hardware` on a Linux host with access to /dev/kvm. That target still needs a verified hardware result.

Developed with AI assistance.
