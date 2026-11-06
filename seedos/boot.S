.code16
.section .text
.global _start
_start:
    ljmp $0, $start
start:
    cli
    xorw %ax,%ax
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%ss
    movw $0x7c00,%sp
    sti
    movb %dl,drive
    movw $3,%cx
retry:
    pushw %cx
    xorw %ax,%ax
    movb drive,%dl
    int $0x13
    movw $0x8000,%bx
    movb $2,%ah
    movb $17,%al
    xorw %cx,%cx
    movb $2,%cl
    xorw %dx,%dx
    movb drive,%dl
    int $0x13
    popw %cx
    jnc loaded
    loop retry
    movw $disk_error,%si
print:
    lodsb
    testb %al,%al
    jz stop
    movb $0x0e,%ah
    xorw %bx,%bx
    int $0x10
    jmp print
stop:
    cli
    hlt
    jmp stop
loaded:
    ljmp $0,$0x8000
drive: .byte 0
disk_error: .asciz "SeedOS disk read error"
.org 510
.word 0xaa55
