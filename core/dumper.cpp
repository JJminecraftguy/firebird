#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

#include "dumper.h"
#include "emu.h"
#include "cpu.h"
#include "mem.h"
#include "mmu.h"
#include "flash.h"
#include "os/os.h"

static bool env_flag(const char *name, bool def)
{
    const char *v = getenv(name);
    if(!v || !*v)
        return def;
    return !(v[0] == '0' || v[0] == 'n' || v[0] == 'N' || v[0] == 'f' || v[0] == 'F');
}

static void make_dir(const char *dir)
{
#ifdef _WIN32
    _mkdir(dir);
#else
    mkdir(dir, 0777);
#endif
}

static std::string join(const char *dir, const std::string &name)
{
    std::string d = dir;
    if(!d.empty() && d.back() != '/' && d.back() != '\\')
        d += '/';
    return d + name;
}

static bool write_file(const std::string &path, const void *data, size_t size)
{
    FILE *f = fopen_utf8(path.c_str(), "wb");
    if(!f)
    {
        gui_perror(path.c_str());
        return false;
    }
    bool ok = size == 0 || fwrite(data, size, 1, f) == 1;
    fclose(f);
    if(!ok)
        gui_perror(path.c_str());
    return ok;
}

static std::string hex8(uint32_t v)
{
    char b[16];
    snprintf(b, sizeof(b), "%08x", v);
    return b;
}

/* ---- CPU state ---------------------------------------------------------- */
static void dump_cpu(const char *dir, const std::string &tag)
{
    FILE *f = fopen_utf8(join(dir, tag + "_cpu.txt").c_str(), "wb");
    if(!f)
        return;
    for(int i = 0; i < 16; i++)
        fprintf(f, "r%d=%08x\n", i, arm.reg[i]);
    uint32_t cpsr = arm.cpsr_low28 | (arm.cpsr_n << 31) | (arm.cpsr_z << 30)
                    | (arm.cpsr_c << 29) | (arm.cpsr_v << 28);
    fprintf(f, "cpsr=%08x\n", cpsr);
    fprintf(f, "cp15_control=%08x\n", arm.control);
    fprintf(f, "cp15_ttb=%08x\n", arm.translation_table_base);
    fprintf(f, "cp15_domain=%08x\n", arm.domain_access_control);
    fprintf(f, "fault_address=%08x\n", arm.fault_address);
    fprintf(f, "r13_svc=%08x r14_svc=%08x spsr_svc=%08x\n", arm.r13_svc[0], arm.r13_svc[1], arm.spsr_svc);
    fprintf(f, "r13_irq=%08x r14_irq=%08x spsr_irq=%08x\n", arm.r13_irq[0], arm.r13_irq[1], arm.spsr_irq);
    fprintf(f, "r13_usr=%08x r14_usr=%08x\n", arm.r13_usr[0], arm.r13_usr[1]);
    fclose(f);
}

/* ---- Physical memory ---------------------------------------------------- */
static void dump_phys(const char *dir, const std::string &tag)
{
    FILE *idx = fopen_utf8(join(dir, tag + "_physmap.txt").c_str(), "wb");
    for(unsigned i = 0; i < sizeof(mem_areas) / sizeof(*mem_areas); i++)
    {
        if(!mem_areas[i].ptr || !mem_areas[i].size)
            continue;
        std::string name = tag + "_phys_" + hex8(mem_areas[i].base) + ".bin";
        write_file(join(dir, name), mem_areas[i].ptr, mem_areas[i].size);
        if(idx)
            fprintf(idx, "%s base=%08x size=%08x\n", name.c_str(), mem_areas[i].base, mem_areas[i].size);
    }
    if(idx)
        fclose(idx);
}

/* ---- MMU walk (ARM926 short descriptors) -------------------------------- */
struct mapping { uint32_t virt, phys, size, desc; };

static void add_mapping(std::vector<mapping> &v, uint32_t virt, uint32_t phys, uint32_t size, uint32_t desc)
{
    /* Merge with previous mapping when both virtual and physical are contiguous
     * and the access permissions (bits 4..11 are AP/domain, kept in desc) match. */
    if(!v.empty())
    {
        mapping &m = v.back();
        if(m.virt + m.size == virt && m.phys + m.size == phys && (m.desc & 0xFF0) == (desc & 0xFF0))
        {
            m.size += size;
            return;
        }
    }
    v.push_back({virt, phys, size, desc});
}

static std::vector<mapping> walk_mmu()
{
    std::vector<mapping> res;
    if(!(arm.control & 1))
    {
        /* MMU off: identity mapping of all RAM areas */
        for(unsigned i = 0; i < sizeof(mem_areas) / sizeof(*mem_areas); i++)
            if(mem_areas[i].ptr && mem_areas[i].size)
                res.push_back({mem_areas[i].base, mem_areas[i].base, mem_areas[i].size, 0});
        return res;
    }

    uint32_t *tt = (uint32_t *)phys_mem_ptr(arm.translation_table_base & ~0x3FFFu, 0x4000);
    if(!tt)
        return res;

    for(uint32_t i = 0; i < 0x1000; i++)
    {
        uint32_t e = tt[i];
        uint32_t vbase = i << 20;
        switch(e & 3)
        {
        case 2: /* section */
            add_mapping(res, vbase, e & 0xFFF00000, 0x100000, e);
            break;
        case 1: /* coarse page table */
        {
            uint32_t *l2 = (uint32_t *)phys_mem_ptr(e & 0xFFFFFC00, 0x400);
            if(!l2)
                break;
            for(uint32_t j = 0; j < 256; j++)
            {
                uint32_t p = l2[j];
                uint32_t v = vbase + (j << 12);
                if((p & 3) == 1) /* large page: replicated 16 times, handle at first slot */
                {
                    if((j & 15) == 0)
                        add_mapping(res, v, p & 0xFFFF0000, 0x10000, p);
                }
                else if((p & 3) == 2) /* small page */
                    add_mapping(res, v, p & 0xFFFFF000, 0x1000, p);
            }
            break;
        }
        case 3: /* fine page table (tiny pages), rarely used */
        {
            uint32_t *l2 = (uint32_t *)phys_mem_ptr(e & 0xFFFFF000, 0x1000);
            if(!l2)
                break;
            for(uint32_t j = 0; j < 1024; j++)
            {
                uint32_t p = l2[j];
                uint32_t v = vbase + (j << 10);
                if((p & 3) == 3)
                    add_mapping(res, v, p & 0xFFFFFC00, 0x400, p);
            }
            break;
        }
        }
    }
    return res;
}

static void dump_virt(const char *dir, const std::string &tag)
{
    std::vector<mapping> maps = walk_mmu();
    FILE *idx = fopen_utf8(join(dir, tag + "_vmap.txt").c_str(), "wb");
    for(const mapping &m : maps)
    {
        void *p = phys_mem_ptr(m.phys, m.size);
        std::string name;
        if(p)
        {
            name = tag + "_virt_" + hex8(m.virt) + "_" + hex8(m.size) + ".bin";
            write_file(join(dir, name), p, m.size);
        }
        if(idx)
            fprintf(idx, "virt=%08x phys=%08x size=%08x desc=%08x %s\n", m.virt, m.phys, m.size, m.desc,
                    p ? name.c_str() : "(not RAM backed, e.g. MMIO)");
    }
    if(idx)
        fclose(idx);
}

/* ---- ZIP carving -------------------------------------------------------- */
static void carve_zips(const char *dir, const std::string &tag)
{
    int count = 0;
    for(unsigned i = 0; i < sizeof(mem_areas) / sizeof(*mem_areas); i++)
    {
        const uint8_t *base = mem_areas[i].ptr;
        size_t size = mem_areas[i].size;
        if(!base || size < 0x10000)
            continue;

        size_t pos = 0;
        while(pos + 30 < size && count < 64)
        {
            const uint8_t *hit = (const uint8_t *)memchr(base + pos, 'P', size - pos - 30);
            if(!hit)
                break;
            size_t off = hit - base;
            pos = off + 1;
            if(memcmp(hit, "PK\x03\x04", 4) != 0)
                continue;

            /* Find the end of central directory record */
            size_t limit = std::min<size_t>(size, off + 64 * 1024 * 1024);
            size_t eocd = 0;
            for(size_t k = off + 30; k + 22 <= limit; k++)
            {
                if(base[k] == 'P' && !memcmp(base + k, "PK\x05\x06", 4))
                {
                    eocd = k;
                    /* keep first EOCD whose comment length fits */
                    uint16_t clen = base[k + 20] | (base[k + 21] << 8);
                    if(k + 22 + clen <= size)
                        break;
                    eocd = 0;
                }
            }
            if(!eocd)
                continue;
            uint16_t clen = base[eocd + 20] | (base[eocd + 21] << 8);
            size_t end = eocd + 22 + clen;
            if(end - off < 4096)
                continue;

            std::string name = tag + "_carved_" + hex8(mem_areas[i].base + (uint32_t)off) + ".zip";
            if(write_file(join(dir, name), base + off, end - off))
            {
                emuprintf("Dumper: carved %s (%zu bytes)\n", name.c_str(), end - off);
                count++;
            }
            pos = end;
        }
    }
}

/* ---- Main entry --------------------------------------------------------- */
int dumper_dump_all(const char *dir, const char *tag_c)
{
    std::string tag = tag_c ? tag_c : "dump";
    make_dir(dir);
    emuprintf("Dumper: writing '%s' to %s ...\n", tag.c_str(), dir);

    dump_cpu(dir, tag);
    dump_phys(dir, tag);
    if(env_flag("FB_DUMP_VIRT", true))
        dump_virt(dir, tag);
    if(env_flag("FB_DUMP_CARVE", true))
        carve_zips(dir, tag);
    if(env_flag("FB_DUMP_NAND", true))
        flash_dump_raw(join(dir, tag + "_nand.bin").c_str());

    emuprintf("Dumper: done.\n");
    return 0;
}

static std::chrono::steady_clock::time_point last_dump = std::chrono::steady_clock::now();
static std::chrono::steady_clock::time_point last_poll = std::chrono::steady_clock::now();
static unsigned poll_ctr = 0;
static unsigned dump_seq = 0;

void dumper_poll(void)
{
    if((++poll_ctr & 0x3FF) != 0)
        return;

    const char *dir = getenv("FB_DUMP_DIR");
    if(!dir || !*dir)
        return;

    auto now = std::chrono::steady_clock::now();
    if(now - last_poll < std::chrono::seconds(1))
        return;
    last_poll = now;

    /* Trigger file */
    std::string trig = join(dir, "DUMP_NOW");
    if(FILE *f = fopen_utf8(trig.c_str(), "rb"))
    {
        fclose(f);
        remove(trig.c_str());
        char tag[32];
        snprintf(tag, sizeof(tag), "manual%03u", dump_seq++);
        dumper_dump_all(dir, tag);
        last_dump = std::chrono::steady_clock::now();
        return;
    }

    const char *iv = getenv("FB_DUMP_INTERVAL");
    long secs = iv ? atol(iv) : 0;
    if(secs > 0 && now - last_dump >= std::chrono::seconds(secs))
    {
        char tag[32];
        snprintf(tag, sizeof(tag), "auto%03u", dump_seq++);
        dumper_dump_all(dir, tag);
        last_dump = std::chrono::steady_clock::now();
    }
}

void dumper_on_exit(void)
{
    const char *dir = getenv("FB_DUMP_DIR");
    if(!dir || !*dir || !env_flag("FB_DUMP_ON_EXIT", true))
        return;
    dumper_dump_all(dir, "exit");
}
