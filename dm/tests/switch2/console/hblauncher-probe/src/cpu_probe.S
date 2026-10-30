.arch armv8.5-a
.text
.p2align 2

.global nx_probe_pac_keys
.type nx_probe_pac_keys, %function
nx_probe_pac_keys:
    bti c
    movz x1, #0x5678
    movk x1, #0x1234, lsl #16
    mov x2, #0x42

    mov x3, x1
    pacia x3, x2
    autia x3, x2
    cmp x3, x1
    b.ne .Lpac_fail

    mov x3, x1
    pacib x3, x2
    autib x3, x2
    cmp x3, x1
    b.ne .Lpac_fail

    mov x3, x1
    pacda x3, x2
    autda x3, x2
    cmp x3, x1
    b.ne .Lpac_fail

    mov x3, x1
    pacdb x3, x2
    autdb x3, x2
    cmp x3, x1
    b.ne .Lpac_fail

    mov w0, #1
    ret
.Lpac_fail:
    mov w0, #0
    ret
.size nx_probe_pac_keys, .-nx_probe_pac_keys

.p2align 2
.global nx_probe_pac_branch
.type nx_probe_pac_branch, %function
nx_probe_pac_branch:
    bti c
    adr x0, .Lpac_branch_target
    mov x1, #0x42
    pacia x0, x1
    braa x0, x1
.Lpac_branch_target:
    bti j
    mov w0, #42
    ret
.size nx_probe_pac_branch, .-nx_probe_pac_branch

.p2align 2
.global nx_probe_lse_add
.type nx_probe_lse_add, %function
nx_probe_lse_add:
    bti c
    ldaddal x1, x2, [x0]
    mov x0, x2
    ret
.size nx_probe_lse_add, .-nx_probe_lse_add

.p2align 2
.global nx_probe_cntfrq
.type nx_probe_cntfrq, %function
nx_probe_cntfrq:
    mrs x0, cntfrq_el0
    ret
.size nx_probe_cntfrq, .-nx_probe_cntfrq
