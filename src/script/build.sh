
cd _install
mkdir etc proc sys mnt dev tmp root
touch proc/filesystems
touch proc/partitions
mkdir -p etc/init.d
cat >> etc/fstab<<EOF
proc    /proc   proc    defaults        0       0
tmpfs   /tmp    tmpfs   defaults        0       0
sysfs   /sys    sysfs   defaults        0       0
EOF
cat>>root/bashrc<<EOF
mount -o remount rw /
mkdir -p /home/share_dir
mount -t 9p -o trans=virtio hostshare /home/share_dir
EOF
cat>>etc/init.d/rcS<<EOF
/bin/sh root/bashrc
echo "Welcome to linux version:2.6.34.1"
EOF
chmod 755 etc/init.d/rcS 
chmod 755 root/bashrc
cat>>etc/inittab<<EOF
::sysinit:/etc/init.d/rcS
::respawn:-/bin/sh
::askfirst:-/bin/sh
::ctrlaltdel:/bin/umount -a -r
EOF
chmod 755 etc/inittab
cd dev
sudo mknod console c 5 1
sudo mknod null c 1 3
sudo mknod tty1 c 4 1

cd ../..

dd if=/dev/zero of=initrd.img bs=4096 count=1024
mkfs.ext3 initrd.img
mkdir rootfs
sudo mount -o loop initrd.img rootfs
sudo cp -rf ./_install/* ./rootfs
sudo umount ./rootfs   