# Dumper patch

Exports emulator state for reverse engineering. Set environment variables before starting Firebird (GUI or headless):

    FB_DUMP_DIR=/path/to/out      # enables the dumper
    FB_DUMP_INTERVAL=60           # optional: auto dump every 60 s
    # touch /path/to/out/DUMP_NOW  -> dump immediately (file is deleted afterwards)
    # a dump is also written on exit, and with the debugger command: dump <dir> [tag]

Each dump writes (prefix = tag, e.g. exit_, manual000_, auto000_):
 * `_phys_<base>.bin`  every physical RAM area (SDRAM is at 10000000, boot ROM at 0, SRAM etc.), `_physmap.txt` indexes them
 * `_virt_<va>_<size>.bin` + `_vmap.txt`  RAM-backed regions as the OS maps them via the MMU
 * `_cpu.txt`  registers, CP15 control/TTB/domain
 * `_carved_<addr>.zip`  ZIP archives found in RAM (a decrypted OS image is a zip containing the OS binary)
 * `_nand.bin`  raw NAND incl. OOB (2112-byte pages on CX II), current state, including unsaved changes
Toggle parts with FB_DUMP_VIRT / FB_DUMP_CARVE / FB_DUMP_NAND = 0.
