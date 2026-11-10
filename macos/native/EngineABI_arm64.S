// AAPCS64 indirect result address is x8, unlike Windows x64's first argument.
.text
.p2align 2
.globl _fm_call_sret
_fm_call_sret:
    mov x9, x0
    mov x8, x1
    mov x0, x2
    mov x1, x3
    mov x2, x4
    mov x3, x5
    br x9
