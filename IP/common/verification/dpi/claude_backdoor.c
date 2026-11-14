/* claude_backdoor.c — Backdoor read / deposit of any design variable by path.
 *
 * Shared Claude IP verification component (DPI-C over VPI, like UVM's
 * uvm_hdl_read / uvm_hdl_deposit). Lets a testbench preload, peek and poke
 * memory arrays without being a second procedural driver: $deposit on a
 * variable written in always_ff is a compile error in VCS (ICPD).
 *
 * SV side:
 *   import "DPI-C" function string claude_bd_get(input string path);
 *   import "DPI-C" function int    claude_bd_put(input string path, input string bits);
 *   path: full hierarchical name, e.g. "tb.u_dut.u_mem.mem[12]"
 *   bits: value as a binary string, MSB first ("0101..."); claude_bd_get
 *         returns the same form ("" if the path does not exist), and
 *         claude_bd_put returns 0 if the path does not exist.
 *
 * VHDL objects (a VHDL design under an SV testbench) are reached through
 * VHPI instead: compile with -DCLAUDE_BD_VHPI and call
 *   import "DPI-C" function string claude_bd_vget(input string path);
 *   import "DPI-C" function int    claude_bd_vput(input string path, input string bits);
 *   path: the same dotted name with VHDL index syntax, e.g.
 *         "tb.u_dut.u_mem.mem(12)" (VHPI's ':' form is built from it)
 *   bits: std_logic values as characters, MSB first ('0', '1', 'X', ...)
 *
 * Tools (needs VPI / VHPI read/write access):
 *   VCS      add this file to the vcs command, -debug_access+r+w
 *            (VHDL: -CFLAGS -DCLAUDE_BD_VHPI)
 *   Xcelium  add this file to the xrun command, -access +rw
 *            (VHDL: -ccargs -DCLAUDE_BD_VHPI)
 *   Questa   vlog this file with the sources, vsim +acc (untested)
 *   Verilator add this file to the verilator command with --vpi, and make the
 *            target variables public (public_flat_rw in a .vlt file)
 *   Icarus   no DPI-C support: backdoor tests are skipped
 */
#include <stdlib.h>
#include <string.h>
#include "vpi_user.h"
#ifdef CLAUDE_BD_VHPI
#include "vhpi_user.h"
#endif

/* C linkage when compiled as C++ (Verilator builds .c files with the C++
 * compiler), so the DPI imports resolve. */
#ifdef __cplusplus
extern "C" {
#endif

static char claude_bd_buf[8192];

/* VPI handle of a dotted path, element selects included. When the simulator
 * cannot resolve a trailing array element by name ("...mem[5]": Verilator
 * 5.x), the array is looked up without it and the element taken with
 * vpi_handle_by_index. */
static vpiHandle claude_bd_lookup(const char *path)
{
  static char base[4096];
  vpiHandle   h = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
  size_t      n = strlen(path);
  const char *lb;
  char       *end;
  long        idx;
  if (h != NULL || n == 0 || n >= sizeof(base) || path[n - 1] != ']') {
    return h;
  }
  lb = strrchr(path, '[');
  if (lb == NULL || lb == path) {
    return NULL;
  }
  idx = strtol(lb + 1, &end, 10);
  if (end == lb + 1 || *end != ']') {
    return NULL;
  }
  memcpy(base, path, (size_t)(lb - path));
  base[lb - path] = '\0';
  h = vpi_handle_by_name((PLI_BYTE8 *)base, NULL);
  return (h == NULL) ? NULL : vpi_handle_by_index(h, (PLI_INT32)idx);
}

/* As given, then under "TOP." (Verilator roots the design hierarchy in a
 * scope named TOP: tb.u_dut is TOP.tb.u_dut). */
static vpiHandle claude_bd_handle(const char *path)
{
  static char top[4096];
  vpiHandle   h = claude_bd_lookup(path);
  if (h != NULL || strlen(path) + 5 > sizeof(top)) {
    return h;
  }
  strcpy(top, "TOP.");
  strcat(top, path);
  return claude_bd_lookup(top);
}

const char *claude_bd_get(const char *path)
{
  vpiHandle   h = claude_bd_handle(path);
  s_vpi_value v;
  if (h == NULL) {
    return "";
  }
  v.format = vpiBinStrVal;
  vpi_get_value(h, &v);
  strncpy(claude_bd_buf, v.value.str, sizeof(claude_bd_buf) - 1);
  claude_bd_buf[sizeof(claude_bd_buf) - 1] = '\0';
  return claude_bd_buf;
}

int claude_bd_put(const char *path, const char *bits)
{
  vpiHandle   h = claude_bd_handle(path);
  s_vpi_value v;
  if (h == NULL) {
    return 0;
  }
  v.format    = vpiBinStrVal;
  v.value.str = (PLI_BYTE8 *)bits;
  vpi_put_value(h, &v, NULL, vpiNoDelay);
  return 1;
}

#ifdef CLAUDE_BD_VHPI
/* Dotted path -> VHPI ':' form (":a:b:c(1)") in out. */
static void claude_bd_colons(const char *path, char *out, size_t size)
{
  size_t i;
  out[0] = ':';
  for (i = 0; path[i] != '\0' && i < size - 2; i++) {
    out[i + 1] = (path[i] == '.') ? ':' : path[i];
  }
  out[i + 1] = '\0';
}

/* VHPI handle of a dotted path: tried as given, then in VHPI's ':' form, then
 * relative to the VHDL root instance it starts with (VCS, -DCLAUDE_BD_VHPI_ROOTS:
 * VCS names each VHDL instance under a Verilog / SV parent as a root instance
 * with an extended identifier holding its path, e.g. \/tb/u_dut\ for
 * tb.u_dut; its pre-IEEE vhpi_user.h has the vhpiRootInsts iterator). */
static vhpiHandleT claude_bd_vhandle(const char *path)
{
  static char vp[4096];
  static char rp[4096];
  vhpiHandleT h = vhpi_handle_by_name((char *)path, NULL);
#ifdef CLAUDE_BD_VHPI_ROOTS
  vhpiHandleT it, r;
  size_t      i, n;
  const char *name;
#endif
  if (h != NULL) {
    return h;
  }
  claude_bd_colons(path, vp, sizeof(vp));
  h = vhpi_handle_by_name(vp, NULL);
  if (h != NULL) {
    return h;
  }
#ifdef CLAUDE_BD_VHPI_ROOTS
  it = vhpi_iterator(vhpiRootInsts, NULL);
  while (it != NULL && (r = vhpi_scan(it)) != NULL) {
    name = vhpi_get_str(vhpiNameP, r);
    if (name == NULL) {
      continue;
    }
    /* \/tb/u_dut\ -> tb.u_dut */
    n = 0;
    for (i = 0; name[i] != '\0' && n < sizeof(rp) - 1; i++) {
      if (name[i] == '\\' || (name[i] == '/' && n == 0)) {
        continue;
      }
      rp[n++] = (name[i] == '/') ? '.' : name[i];
    }
    rp[n] = '\0';
    if (n > 0 && strncmp(path, rp, n) == 0 && path[n] == '.') {
      claude_bd_colons(path + n + 1, vp, sizeof(vp));
      h = vhpi_handle_by_name(vp + 1, r);
      if (h == NULL) {
        h = vhpi_handle_by_name((char *)(path + n + 1), r);
      }
      if (h != NULL) {
        vhpi_release_handle(it);
        return h;
      }
    }
  }
#endif
  return NULL;
}

/* std_logic values as vhpiLogicVecVal enumeration positions, 'U' .. '-'. */
static const char claude_bd_sl[] = "UX01ZWLH-";

/* VCS ships a pre-IEEE vhpi_user.h (numscalars, enums, char *str) and Xcelium
 * the IEEE 1076 one (numElems, enumvs, vhpiCharT *str); the layouts are the
 * same, so the element count is the int after bufSize and the value pointer
 * goes through str, which both have. */
#define CLAUDE_BD_NUM(v) (((vhpiIntT *)&(v).bufSize)[1])

static vhpiEnumT claude_bd_enums[8192];

const char *claude_bd_vget(const char *path)
{
  vhpiHandleT h = claude_bd_vhandle(path);
  vhpiValueT  v;
  int         n, i;
  if (h == NULL) {
    return "";
  }
  n = vhpi_get(vhpiSizeP, h);
  if (n <= 0 || n >= (int)(sizeof(claude_bd_buf) - 1)) {
    return "";
  }
  memset(&v, 0, sizeof(v));
  v.format         = vhpiLogicVecVal;
  v.bufSize        = n * sizeof(vhpiEnumT);
  CLAUDE_BD_NUM(v) = n;
  v.value.str      = (void *)claude_bd_enums;
  if (vhpi_get_value(h, &v) != 0) {
    return "";
  }
  for (i = 0; i < n; i++) {
    claude_bd_buf[i] = claude_bd_enums[i] < 9 ? claude_bd_sl[claude_bd_enums[i]] : '?';
  }
  claude_bd_buf[n] = '\0';
  return claude_bd_buf;
}

int claude_bd_vput(const char *path, const char *bits)
{
  vhpiHandleT h = claude_bd_vhandle(path);
  vhpiValueT  v;
  int         n = (int)strlen(bits), i;
  const char *p;
  if (h == NULL || n == 0 || n > (int)(sizeof(claude_bd_enums) / sizeof(vhpiEnumT))) {
    return 0;
  }
  for (i = 0; i < n; i++) {
    p = strchr(claude_bd_sl, bits[i] == 'x' ? 'X' : bits[i] == 'z' ? 'Z' : bits[i]);
    claude_bd_enums[i] = (p != NULL && *p != '\0') ? (vhpiEnumT)(p - claude_bd_sl) : 1;
  }
  memset(&v, 0, sizeof(v));
  v.format         = vhpiLogicVecVal;
  v.bufSize        = n * sizeof(vhpiEnumT);
  CLAUDE_BD_NUM(v) = n;
  v.value.str      = (void *)claude_bd_enums;
  return vhpi_put_value(h, &v, vhpiDepositPropagate) == 0;
}
#endif

#ifdef __cplusplus
}
#endif
