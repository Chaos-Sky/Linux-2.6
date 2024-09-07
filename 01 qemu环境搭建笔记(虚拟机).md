#### 第一步：安装基本工具

```shell
apt install gcc gdb make git gcc-4.4 qemu -y
```

gcc-4.4需要添加额外源

```shell
deb http://dk.archive.ubuntu.com/ubuntu/ trusty main universe
```

如果qemu 安装后，没有qemu-system-x86_64，那么安装

```shell
apt install qemu-system-x86
```

#### 第二步：下载busybox 1.35和linux 2.6.30并解压

```shell
tar -xvf linux-2.6.30.4.tar.gz
tar jxvf busybox-1.35.0.tar.bz2
```

#### 第三步 编译busybox

```shell
make defconfig

make menuconfig
```

如果报错：

```shell
<command-line>: fatal error: curses.h: No such file or directory
```

安装 sudo apt-get install libncurses5-dev

在执行make menuconfig操作后，我们选择Setting --> Build static binary

编译 make -j4

#### 第四步 编译内核

```shell
make x86_64_defconfig


make menuconfig

mak
```

出现错误：cc1: error: code model kernel does not support PIC mode

修改Makefile 

出现错误：include/linux/compiler-gcc.h:86:1: fatal error: linux/compiler-gcc9.h: No such file or directory

指定编译器gcc-4.4

出现错误：Can't use 'defined(@array)' (Maybe you should just omit the defined()?) at kernel/timeconst.pl line 373.

修改：去除define

```shell
cd _install
mkdir etc proc sys mnt dev tmp
mkdir -p etc/init.d
cat >> etc/fstab<<EOF
proc    /proc   proc    defaults        0       0
tmpfs   /tmp    tmpfs   defaults        0       0
sysfs   /sys    sysfs   defaults        0       0
EOF
cat>>etc/init.d/rcS<<EOF
echo "Welcome to linux..."
EOF
chmod 755 etc/init.d/rcS 
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
```

```shell
vi arch/x86/include/asm/ptrace.h
```

130行 添加 #include <linux/linkage.h>

142 143行 修改代码

```shell
extern asmregparm long syscall_trace_enter(struct pt_regs *); 
extern asmregparm void syscall_trace_leave(struct pt_regs *);
```

```shell
apt-get install -y lib32readline-gplv2-dev # 编译32位系统

apt-get install -y libncurses5-dev build-essential
```

```shell
qemu-system-i386 \
-nographic \
-kernel ./bzImage \
-initrd ./initrd.img \
-append "root=/dev/ram init=/bin/bash console=ttyS0"
```

```shell
mount -o remount rw /
```

程序运行不了：内核版本低。没有运行库，静态编译
