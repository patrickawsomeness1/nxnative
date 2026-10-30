// AArch64 Pointer Authentication smoke test for the Apple host CPU.
// These functions are part of the signed app image; they do not execute imported code.
.arch armv8.5-a
.arch_extension pauth
.text
.p2align 2
.globl _nx_pac_sign
_nx_pac_sign:
    bti c
    pacia x0, x1
    ret

.p2align 2
.globl _nx_pac_auth
_nx_pac_auth:
    bti c
    autia x0, x1
    ret
