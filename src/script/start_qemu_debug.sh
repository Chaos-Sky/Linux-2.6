qemu-system-x86_64 \
    -m 1024 \
    -nographic \
    -kernel ./bzImage \
    -initrd ./initrd.img \
    -virtfs local,path=/home/,mount_tag=hostshare,security_model=none \
    -net nic -net user \
    -append "root=/dev/ram rw init=/bin/bash console=ttyS0" -s -S
