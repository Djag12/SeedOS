.code16
.section .text
.global _start
_start:
 cli
 xor %ax,%ax
 mov %ax,%ds
 inb $0x92,%al
 or $2,%al
 outb %al,$0x92
 lgdt gdtr
 mov %cr0,%eax
 or $1,%eax
 mov %eax,%cr0
 ljmp $8,$protected
.code32
protected:
 mov $16,%ax
 mov %ax,%ds
 mov %ax,%es
 mov %ax,%ss
 mov $0x90000,%esp
 cld
 mov $0x1000,%edi
 xor %eax,%eax
 mov $4096,%ecx
 rep stosl
 movl $0x2007,0x1000
 movl $0x3007,0x2000
 movl $0x83,0x3000
 movl $0x600083,0x3018
 movl $0x800083,0x3020
 movl $0x4007,0x3010
 movl $0x400007,0x4000
 movl $0x401007,0x4008
 mov $0x1000,%eax
 mov %eax,%cr3
 mov %cr4,%eax
 or $0x20,%eax
 mov %eax,%cr4
 mov $0xc0000080,%ecx
 rdmsr
 or $0x101,%eax
 wrmsr
 mov %cr0,%eax
 or $0x80000000,%eax
 mov %eax,%cr0
 ljmp $0x18,$longmode
.code64
longmode:
 mov $16,%ax
 mov %ax,%ds
 mov %ax,%es
 mov %ax,%ss
 mov $0x90000,%rsp
 mov $bss_start,%rdi
 mov $bss_end,%rcx
 sub %rdi,%rcx
 xor %eax,%eax
 rep stosb
 call kernel_main
1: hlt
 jmp 1b
.align 8
gdt:
 .quad 0,0x00cf9a000000ffff,0x00cf92000000ffff,0x00af9a000000ffff
gdtr: .word 31
 .long gdt
.section .note.GNU-stack,"",@progbits
