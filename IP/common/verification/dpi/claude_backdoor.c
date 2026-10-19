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
 * Tools (needs VPI read/write access):
 *   VCS      add this file to the vcs command, -debug_access+r+w
 *   Xcelium  add this file to the xrun command, -access +rw
 *   Questa   vlog this file with the sources, vsim +acc (untested)
 *   Icarus   no DPI-C support: backdoor tests are skipped
 */
#include <string.h>
#include "vpi_user.h"

static char claude_bd_buf[8192];

const char *claude_bd_get(const char *path)
{
  vpiHandle   h = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
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
  vpiHandle   h = vpi_handle_by_name((PLI_BYTE8 *)path, NULL);
  s_vpi_value v;
  if (h == NULL) {
    return 0;
  }
  v.format    = vpiBinStrVal;
  v.value.str = (PLI_BYTE8 *)bits;
  vpi_put_value(h, &v, NULL, vpiNoDelay);
  return 1;
}
