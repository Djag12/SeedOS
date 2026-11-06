#include <stdint.h>
typedef uint64_t u64;
static inline void out(unsigned short p,unsigned char v){__asm__ volatile("outb %0,%1"::"a"(v),"Nd"(p));}
static void puts(const char*s){while(*s){out(0x3f8,*s++);}}
static void number(u64 n){char s[24];int i=0;do{s[i++]='0'+n%10;n/=10;}while(n);while(i)out(0x3f8,s[--i]);}
static void stop(int code){out(0xf4,code);for(;;)__asm__ volatile("hlt");}
struct __attribute__((packed)) TSS {uint32_t reserved;u64 rsp[3];u64 reserved2;u64 ist[7];u64 reserved3;uint16_t reserved4,iomap;};
struct __attribute__((packed)) Gate {uint16_t lo,cs;uint8_t ist,flags;uint16_t mid;uint32_t hi,zero;};
struct __attribute__((packed)) Desc {uint16_t size;u64 ptr;};
static struct TSS tss;static u64 gdt[7];static struct Gate idt[256];
extern void syscall_entry(void);
extern void isr80(void),isr6(void),isr13(void),isr14(void),enter_user(void),load_gdt(void*);
extern unsigned char user_start[],user_end[],driver_start[],driver_end[],rtc_start[],rtc_end[];
static void gate(int n,void(*fn)(void),int flags){u64 a=(u64)fn;idt[n]=(struct Gate){a,8,0,flags,a>>16,a>>32,0};}
struct Frame{u64 r15,r14,r13,r12,r11,r10,r9,r8,rbp,rdi,rsi,rdx,rcx,rbx,rax,vector,error,rip,cs,flags,rsp,ss;};

enum { CLIENT, SERIAL, CLOCK, TASK_COUNT };
struct Task { struct Frame *saved; u64 cr3, stack_top; } tasks[TASK_COUNT];
u64 active_kernel_stack = 0x90000;
struct Frame *resume_frame;
struct Capability {uint32_t object,rights;};
// Each task has its own handle namespace. Client can call endpoint 1;
// driver can access UART 0 only. No caller can supply a raw port address.
enum { SEND = 1, UART_IO = 2, RTC_IO = 4 };
static const struct Capability caps[TASK_COUNT][3] = {
 [CLIENT] = {{0,0},{SERIAL,SEND},{CLOCK,SEND}},
 [SERIAL] = {{0,0},{0,UART_IO},{0,0}},
 [CLOCK]  = {{0,0},{0,RTC_IO},{0,0}},
};
#ifdef BENCHMARK
#define TARGET_IPC 1000000
#define TARGET_CRASHES 0
#else
#define TARGET_IPC 100002
#define TARGET_CRASHES 1000
#endif
static u64 completed,denied,crashes,pf,ud,serial_writes,clock_reads,payload;
static int current,pending;
static void initial(struct Frame*f){*f=(struct Frame){0};f->rip=0x400000;f->cs=35;f->ss=27;f->rsp=0x402000;f->flags=2;}
static void switch_to(int next, struct Frame *frame) {
 // The complete register frame stays on its owner's supervisor-only stack.
 tasks[current].saved = frame;
 current = next;
 resume_frame = tasks[next].saved;
 active_kernel_stack = tasks[next].stack_top;
 tss.rsp[0] = active_kernel_stack;
 __asm__ volatile("mov %0,%%cr3"::"r"(tasks[next].cr3):"memory");
}
void trap(struct Frame*f){
 if((f->cs&3)!=3){puts("KERNEL PANIC\n");stop(2);}
 if(f->vector==128){
  u64 call=f->rax,handle=f->rdi;
  if(call==1){
   if(handle>=3||!(caps[current][handle].rights&1)||pending){denied++;f->rax=-1;return;}
   int destination = caps[current][handle].object;
   pending=1; payload=f->rdx;
   tasks[destination].saved->rax=payload;
   switch_to(destination,f);return;
  }
  if(call==5&&current!=CLIENT&&pending){f->rax=payload;return;}
  if(call==2&&current!=CLIENT&&pending){pending=0;completed++;tasks[0].saved->rax=f->rdx;switch_to(0,f);return;}
  if((call==6||call==7)&&handle<2&&(caps[current][handle].rights&2)){
   if(call==6){unsigned char value;__asm__ volatile("inb %1,%0":"=a"(value):"Nd"((unsigned short)0x3fd));f->rax=value;}
   else{out(0x3f8,f->rdx);serial_writes++;f->rax=0;}return;
  }
  if(call==8 && handle<3 && (caps[current][handle].rights & RTC_IO)){
   unsigned char status;
   out(0x70,0x0d); // CMOS RTC status D, read-only.
   __asm__ volatile("inb %1,%0":"=a"(status):"Nd"((unsigned short)0x71));
   clock_reads++; f->rax=status; return;
  }
  if(call==3&&current!=CLIENT){f->rax=crashes;return;}
  if(call==9&&current==0&&completed==TARGET_IPC&&crashes==TARGET_CRASHES){
   puts("\nPASS x86_64 processes=3 restarts=");number(crashes);puts(" ipc_round_trips=");number(completed);puts(" denied_caps=");number(denied);puts(" page_faults=");number(pf);puts(" invalid_opcodes=");number(ud);puts(" serial_driver_writes=");number(serial_writes);puts(" clock_driver_reads=");number(clock_reads);puts("\n");stop(0);
  }
  denied++;f->rax=(u64)-1;return; // Invalid calls cannot halt the kernel.
 }
 if(current==CLIENT){puts("CLIENT FAULT\n");stop(6);}
 if(f->vector==6)ud++;
 else if(f->vector==14){u64 fault;__asm__ volatile("mov %%cr2,%0":"=r"(fault));if(fault!=0x8000||(f->error&7)!=7){puts("BAD PAGE FAULT\n");stop(4);}pf++;}
 else{puts("UNEXPECTED EXCEPTION\n");stop(5);}
 crashes++;
 // Pending request survives a driver crash and is delivered after restart.
 for(int i=0;i<4096;i++)((volatile unsigned char*)(0x401000UL+current*0x200000UL))[i]=0;
 initial(f);if(pending)f->rax=payload;
}
static void address_space(int task){
 u64 base=0x10000+task*0x4000;u64*root=(u64*)base,*pdpt=(u64*)(base+4096),*pd=(u64*)(base+8192),*pt=(u64*)(base+12288);
 for(int i=0;i<2048;i++)root[i]=0;
 root[0]=(u64)pdpt|7;pdpt[0]=(u64)pd|7;
 pd[0]=0x83;pd[1]=0x200083;pd[2]=(u64)pt|7;pd[3]=0x600083;pd[4]=0x800083;
 pt[0]=(0x400000+task*0x200000)|5;pt[1]=(0x401000+task*0x200000)|7;
 tasks[task].cr3=base;
 tasks[task].stack_top=0x90000UL-task*0x2000UL;
 tasks[task].saved=(struct Frame*)tasks[task].stack_top-1;
 initial(tasks[task].saved);
}
void kernel_main(void){
 out(0x3f8+1,0);out(0x3f8+3,0x80);out(0x3f8,1);out(0x3f8+1,0);out(0x3f8+3,3);out(0x3f8+2,0xc7);out(0x3f8+4,0x0b);
 puts("SeedOS64 boot\n");
 gdt[1]=0x00af9a000000ffff;gdt[2]=0x00cf92000000ffff;gdt[3]=0x00cff2000000ffff;gdt[4]=0x00affa000000ffff;
 tss.rsp[0]=0x90000;tss.iomap=sizeof(tss);u64 b=(u64)&tss,l=sizeof(tss)-1;gdt[5]=(l&65535)|((b&0xffffff)<<16)|((u64)0x89<<40)|((l&0xf0000)<<32)|((b&0xff000000)<<32);gdt[6]=b>>32;
 struct Desc gd={sizeof(gdt)-1,(u64)gdt};load_gdt(&gd);
 gate(128,isr80,0xee);gate(6,isr6,0x8e);gate(13,isr13,0x8e);gate(14,isr14,0x8e);struct Desc id={sizeof(idt)-1,(u64)idt};__asm__ volatile("lidt %0"::"m"(id));
 for(u64 i=0;i<(u64)(user_end-user_start);i++)((unsigned char*)0x400000)[i]=user_start[i];

 for(u64 i=0;i<(u64)(driver_end-driver_start);i++)((unsigned char*)0x600000)[i]=driver_start[i];
 for(u64 i=0;i<(u64)(rtc_end-rtc_start);i++)((unsigned char*)0x800000)[i]=rtc_start[i];
 for(int i=0;i<TASK_COUNT;i++)address_space(i);
 __asm__ volatile("mov %0,%%cr3"::"r"(tasks[0].cr3):"memory");
 u64 star=((u64)19<<48)|((u64)8<<32),entry=(u64)syscall_entry;
 __asm__ volatile("wrmsr"::"c"(0xc0000081),"a"((uint32_t)star),"d"((uint32_t)(star>>32)));
 __asm__ volatile("wrmsr"::"c"(0xc0000082),"a"((uint32_t)entry),"d"((uint32_t)(entry>>32)));
 __asm__ volatile("wrmsr"::"c"(0xc0000084),"a"(0x600),"d"(0));
 puts("WORKLOAD START\n");
 enter_user();
}
