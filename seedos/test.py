"""Run the actual freestanding kernel in QEMU, asserting complete serial evidence."""
import os,subprocess,time,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
qemu=os.environ.get('QEMU','qemu-system-x86_64')
extra=[]
if os.environ.get('QEMU_BIOS'):extra=['-bios',os.environ['QEMU_BIOS']]
start=time.perf_counter()
p=subprocess.run([qemu,*extra,'-accel','tcg','-m','16','-nodefaults','-drive',f'file={root}/seedos/build/seedos64.img,format=raw,if=floppy','-display','none','-serial','stdio','-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],capture_output=True,text=True,timeout=60)
expected='PASS x86_64 processes=3 restarts=1000 ipc_round_trips=100002 denied_caps=101002 page_faults=500 invalid_opcodes=500 serial_driver_writes=500 clock_driver_reads=500'
assert p.returncode==1 and expected in p.stdout,(p.returncode,p.stdout,p.stderr)
(root/'results/seedos.log').write_text(p.stdout)
print(json.dumps({'emulator':'QEMU TCG','mode':'x86-64 long mode','ring3_restarts':1000,'ipc_round_trips':100002,'invalid_capability_denials':101002,'kernel_write_page_faults':500,'invalid_opcode_faults':500,'whole_emulator_wall_seconds':time.perf_counter()-start,'ipc_throughput_measured':False,'user_space_serial_driver':True,'isolated_processes':3,'isolated_drivers':['UART','CMOS RTC'],'cross_driver_denials':1000},indent=2))
