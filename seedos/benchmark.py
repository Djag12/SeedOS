"""Measure actual cross-address-space IPC. Never substitute TCG for KVM."""
import json,os,platform,selectors,statistics,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
accel=os.environ.get('ACCEL','tcg')
if accel not in ('tcg','kvm'):raise SystemExit('Exact benchmark supports only tcg or kvm; WHPX is not KVM')
if accel=='kvm':
 try:
  import fcntl
  fd=os.open('/dev/kvm',os.O_RDWR)
  try:
   if fcntl.ioctl(fd,0xAE00,0)!=12:raise OSError('Unsupported KVM API')
  finally:os.close(fd)
 except OSError as exc:raise SystemExit(f'KVM unavailable: {exc}')
qemu=os.environ.get('QEMU','qemu-system-x86_64')
extra=['-bios',os.environ['QEMU_BIOS']] if os.environ.get('QEMU_BIOS') else []
if accel=='kvm':extra+=['-cpu','host']
count=int(os.environ.get('BENCH_RUNS','5' if accel=='kvm' else '1'))
if count<1:raise SystemExit('BENCH_RUNS must be positive')
version=subprocess.check_output([qemu,'--version'],text=True).splitlines()[0]
samples=[];logs=[]
for run in range(count):
 p=subprocess.Popen([qemu,*extra,'-accel',accel,'-smp','1','-m','16','-nodefaults','-drive',f'file={root}/seedos/build-bench/seedos64.img,format=raw,if=floppy','-display','none','-serial','stdio','-monitor','none','-no-reboot','-device','isa-debug-exit,iobase=0xf4,iosize=0x04'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
 log=b'';started=None;ended=None;deadline=time.monotonic()+300
 try:
  while time.monotonic()<deadline:
   for key,_ in selector.select(1):
    data=os.read(key.fd,4096);log+=data
    if started is None and b'WORKLOAD START\n' in log:started=time.perf_counter()
    if b'PASS x86_64' in log and ended is None:ended=time.perf_counter()
   if p.poll() is not None:
    # Drain final pipe bytes after exit before checking the complete serial record.
    log+=p.stdout.read()
    if ended is None and b'PASS x86_64' in log:ended=time.perf_counter()
    break
  else:raise TimeoutError('IPC benchmark exceeded 300s')
  p.wait(timeout=5)
  assert p.returncode==1 and b'ipc_round_trips=1000000' in log and b'restarts=0' in log,(p.returncode,log,p.stderr.read())
  assert started and ended and ended>started,'Workload markers were not separately observed'
  samples.append(ended-started);logs.append(log)
 finally:
  if p.poll() is None:p.kill();p.wait()
  selector.close()
  p.stdout.close();p.stderr.close()
elapsed=statistics.median(samples);rate=1000000/elapsed
(root/'results/seedos_benchmark.log').write_bytes(b'\n--- RUN ---\n'.join(logs))
report={'accelerator':accel,'qemu_version':version,'host':platform.platform(),'runs':count,'processes':3,'timed_ipc_participants':2,'round_trips':1000000,'elapsed_seconds':elapsed,'elapsed_seconds_samples':samples,'ipc_round_trips_per_second':rate,'includes_driver_receive_syscall':False,'entry_exit':'SYSCALL/SYSRET','kernel_address_space_switch_per_direction':True,'timing':'median host serial workload markers; includes marker overhead','target_500k_met':rate>=500000,'exact_kvm_target_verified':accel=='kvm' and rate>=500000}
print(json.dumps(report,indent=2))
