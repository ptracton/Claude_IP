// claude_fv_defines.svh — Shared macros for Claude IP formal checkers.
//
// The bus-protocol checkers in this directory (claude_<proto>_fv.sv) describe
// each protocol rule exactly once. Whether a master-side rule is an
// assumption (checker attached to a slave: the solver plays a legal master)
// or an assertion (checker attached to a master: the master must obey) is
// selected by the checker's MASTER_IS_ENV parameter, via these macros.
//
// The macros expand to a named generate block so the property keeps a
// stable, readable hierarchical name in the tool report, e.g.
//   u_fv.u_bus.g_m_setup_to_access.m_setup_to_access

`ifndef CLAUDE_FV_DEFINES_SVH
`define CLAUDE_FV_DEFINES_SVH

// Rule obeyed by the master (the environment when MASTER_IS_ENV=1).
`define CLAUDE_FV_MASTER(NAME, PROP)                                   \
  if (MASTER_IS_ENV) begin : g_``NAME                                  \
    NAME : assume property (PROP);                                     \
  end else begin : g_``NAME                                            \
    NAME : assert property (PROP);                                     \
  end

// Rule obeyed by the slave (the design when MASTER_IS_ENV=1).
`define CLAUDE_FV_SLAVE(NAME, PROP)                                    \
  if (MASTER_IS_ENV) begin : g_``NAME                                  \
    NAME : assert property (PROP);                                     \
  end else begin : g_``NAME                                            \
    NAME : assume property (PROP);                                     \
  end

`endif // CLAUDE_FV_DEFINES_SVH
