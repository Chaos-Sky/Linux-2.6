# docker下搭建内核调试体系

## 第一步 安装docker desktop
    - 自行网络搜索docker安装视频
    - 将dockers镜像路径更改(强烈建议，防止C盘塞满)

## 使用docker 安装ubuntu系统
```shell
    #打开powershell或者cmd命令行,拉取对应系统
    docker pull ubuntu:14.04
    #查看对应的images
    docker images
    #创建容器
    docker run --privileged -it [docker的image ID] /bin/bash
```
## 更新linux 系统源
```shell
    #更新
    apt update
    #安装安装包
    apt install gcc gdb make qemu qemu-system-x86 libncurses5-dev libncurses5-dev build-essential -y
```
## 下载busybox和linux kernel

    - busybox [busybox-1.20.1]
    - linux kernel [linux-2.6.34.1.tar]

## 编译busybox
    - 将编译busybox设置成静态编译
```shell
    #执行下面操作
    make defconfig
    make menuconfig

    make -j4


```
    -指定跟文件系统
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
mount -o remount rw /
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
## 编译 linux Kernel
    -设置添加调试信息
```shell

    #执行下面操作
    make defconfig
    make menuconfig
    make -j4

```
## 使用qemu 启动linux kernel

```shell
    qemu-system-x86_64 \
    -nographic \
    -kernel ./bzImage \
    -initrd ./initrd.img \
    -append "root=/dev/ram init=/bin/bash console=ttyS0"
```

## 挂载GDB 远程调试
```shell

    qemu-system-x86_64 \
    -nographic \
    -kernel ./bzImage \
    -initrd ./initrd.img \
    -append "root=/dev/ram init=/bin/bash console=ttyS0" -S -s

```
    - GDB方面进入内核编译目录
```shell

    gdb vmlinux

    target remote:1234

```

## 错误处理 linux-2.6.34.1.tar  busybox-1.20.1.tar

修改busybox 下include/libbb.h
添加 #include "sys/resource.h"
