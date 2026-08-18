import subprocess, os
xs = subprocess.check_output(["ps", "-axo", "pid,command"], text=True)
for line in xs.splitlines():
    if "Contents/MacOS/bns" in line and "Debug/bns.app" not in line:
        pid = int(line.split()[0])
        os.kill(pid, 15)
        print("killed", pid, line.strip()[:160])
print("LEFT")
xs = subprocess.check_output(["ps", "-axo", "pid,command"], text=True)
print("\n".join([l for l in xs.splitlines() if "Contents/MacOS/bns" in l]))
