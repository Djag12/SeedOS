.code64
.global syscall_entry
.global isr80,isr6,isr13,isr14,enter_user,user_start,user_end,load_gdt
syscall_entry:
 mov %rsp,syscall_user_rsp(%rip)
 mov active_kernel_stack(%rip),%rsp
 pushq $27
 pushq syscall_user_rsp(%rip)
 push %r11
 pushq $35
 push %rcx
 pushq $0
 pushq $128
 jmp common
isr80: pushq $0
 pushq $128
 jmp common
isr6: pushq $0
 pushq $6
 jmp common
isr13: pushq $13
 jmp common
isr14: pushq $14
common:
 cld
 push %rax
 push %rbx
 push %rcx
 push %rdx
 push %rsi
 push %rdi
 push %rbp
 push %r8
 push %r9
 push %r10
 push %r11
 push %r12
 push %r13
 push %r14
 push %r15
 mov %rsp,%rdi
 mov %rsp,resume_frame(%rip)
 and $-16,%rsp
 call trap
 mov resume_frame(%rip),%rsp
 pop %r15
 pop %r14
 pop %r13
 pop %r12
 pop %r11
 pop %r10
 pop %r9
 pop %r8
 pop %rbp
 pop %rdi
 pop %rsi
 pop %rdx
 pop %rcx
 pop %rbx
 pop %rax
 cmpq $128,(%rsp)
 jne 9f
 add $16,%rsp
 mov 0(%rsp),%rcx
 mov 16(%rsp),%r11
 mov 24(%rsp),%rsp
 sysretq
9: add $16,%rsp
 iretq
load_gdt:
 lgdt (%rdi)
 pushq $8
 lea 1f(%rip),%rax
 push %rax
 lretq
1: mov $16,%ax
 mov %ax,%ds
 mov %ax,%es
 mov %ax,%ss
 mov $40,%ax
 ltr %ax
 ret
enter_user:
 pushq $27
 pushq $0x402000
 pushq $2
 pushq $35
 pushq $0x400000
 iretq

// Client and driver occupy distinct physical pages at the same virtual address.
user_start:
 mov $27,%ax
 mov %ax,%ds
 mov %ax,%es
 .ifdef BENCHMARK
 mov $1000000,%r12
 .else
 mov $100002,%r12
 .endif
1:
 .ifndef BENCHMARK
 mov $1,%eax
 mov $3,%edi
 syscall
 cmp $-1,%rax
 jne 3f
 .endif
 mov $1,%eax
 mov $1,%edi
 .ifndef BENCHMARK
 mov %r12,%rdi
 and $1,%edi
 inc %edi
 .endif
 mov %r12,%rdx
 syscall
 cmp %r12,%rax
 jne 3f
 dec %r12
 jnz 1b
 mov $9,%eax
 syscall
3: mov $4,%eax
 syscall
 ud2
user_end:
.global driver_start,driver_end
driver_start:
 mov %rax,%r14
 mov $27,%ax
 mov %ax,%ds
 mov %ax,%es
 mov $100,%r12
 mov %r14,%rax
1: mov %rax,%rdx
 mov $2,%eax
 syscall
 .ifdef BENCHMARK
 jmp 1b
 .else
 dec %r12
 jnz 1b
 // User-mode serial driver: query transmitter-ready then emit via I/O cap.
2: mov $6,%eax
 mov $1,%edi
 syscall
 test $32,%rax
 jz 2b
 mov $7,%eax
 mov $1,%edi
 mov $46,%edx
 syscall
 // The serial driver may not access the clock.
 mov $8,%eax
 syscall
 cmp $-1,%rax
 jne 5f
 ud2
5: jmp 5b
.endif
driver_end:
.global rtc_start,rtc_end
rtc_start:
 mov $100,%r12
1: mov %rax,%rdx
 mov $2,%eax
 syscall
 dec %r12
 jnz 1b
 mov $1,%edi
 mov $8,%eax
 syscall
 // The clock driver may not write the serial port.
 mov $7,%eax
 syscall
 cmp $-1,%rax
 jne 2f
 movq $7,0x8000
2: jmp 2b
rtc_end:
.section .bss
.align 8
syscall_user_rsp: .quad 0
.section .note.GNU-stack,"",@progbits
