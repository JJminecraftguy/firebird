/* Dumper: export RAM, NAND, CPU/MMU state and carved zip archives
 * from the running emulation, for reverse engineering.
 *
 * Environment variables (all optional, dumper is inactive without FB_DUMP_DIR
 * unless the debugger command "dump <dir>" is used):
 *   FB_DUMP_DIR       output directory (created if missing)
 *   FB_DUMP_INTERVAL  seconds between automatic dumps (0/unset = off)
 *   FB_DUMP_ON_EXIT   1 (default when FB_DUMP_DIR set) / 0: dump at shutdown
 *   FB_DUMP_NAND      1 (default) / 0: include the raw NAND image
 *   FB_DUMP_VIRT      1 (default) / 0: include MMU-mapped virtual regions
 *   FB_DUMP_CARVE     1 (default) / 0: carve embedded ZIP files out of RAM
 *   Creating the file <FB_DUMP_DIR>/DUMP_NOW triggers a dump (file is removed). */
#ifndef _H_DUMPER
#define _H_DUMPER

#ifdef __cplusplus
extern "C" {
#endif

/* Perform a full dump into dir, files are prefixed with tag. Returns 0 on success. */
int dumper_dump_all(const char *dir, const char *tag);
/* Cheap; call regularly from the emulation loop. */
void dumper_poll(void);
/* Call when the emulation ends. */
void dumper_on_exit(void);

#ifdef __cplusplus
}
#endif

#endif
