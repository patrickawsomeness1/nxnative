// A single page of signed app code, deliberately isolated for the execute-only remap probe.
.section __TEXT,__nx_xom,regular,pure_instructions
.p2align 14
.globl _nx_xom_probe_page_start
.globl _nx_xom_probe_page_end
_nx_xom_probe_page_start:
    bti c
    mov x0, #0x2a
    ret
.p2align 14
_nx_xom_probe_page_end:

.arch_extension lse
.p2align 2
.globl _nx_lse_add
_nx_lse_add:
    bti c
    ldaddal x1, x2, [x0]
    mov x0, x2
    ret
