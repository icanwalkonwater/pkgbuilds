# Installation guide for Ilum

Derived from the archlinux installation guide.

A few sanity checks:
```sh
cat /sys/firmware/efi/fw_platform_size # should be 64
ping ping.archlinux.org # should work
timedatectl # should be correct
```

## Disk partitionning

Recommanded disk layout:
- GPT partition table
- Boot partition:
  - Size: 1G
  - Type: EFI System (`uefi`)
  - Label: `ilum-boot`
- Root partition:
  - Size: rest
  - Type: Linux filesystem (`linux`)
  - Label: `ilum-root`

Use `fdisk` to achive this layout.

Recommanded filesystem layout:
```sh
mkfs.vfat -F 32 -n ilum-bootfs /dev/disk/by-partlabel/ilum-boot

mkfs.btrfs \
  --data single \
  --metadata dup \
  --label ilum-rootfs \
  /dev/disk/by-partlabel/ilum-root
# Temp mount to create subvolumes
mount --mkdir -t btrfs /dev/disk/by-label/ilum-rootfs /mnt
btrfs subvolume create \
  /mnt/@ \
  /mnt/@home \
  /mnt/@home-lucas \
  /mnt/@var \
  /mnt/@swap \
  /mnt/@nix
btrfs subvolume sync /mnt
umount /mnt
```

And mount layout:
```sh
mount --mkdir -t btrfs -o subvol=@ /dev/disk/by-label/ilum-rootfs /mnt
mount --mkdir -t btrfs -o subvol=@home /dev/disk/by-label/ilum-rootfs /mnt/home
mount --mkdir -t btrfs -o subvol=@home-lucas /dev/disk/by-label/ilum-rootfs /mnt/home/lucas
mount --mkdir -t btrfs -o subvol=@var /dev/disk/by-label/ilum-rootfs /mnt/var
mount --mkdir -t btrfs -o subvol=@swap /dev/disk/by-label/ilum-rootfs /mnt/swap
mount --mkdir -t btrfs -o subvol=@nix /dev/disk/by-label/ilum-rootfs /mnt/nix
mount --mkdir -t btrfs /dev/disk/by-label/ilum-rootfs /mnt/mnt/rootfs
mount --mkdir -t vfat /dev/disk/by-label/ilum-bootfs /mnt/boot
```

And swap:
```sh
btrfs filesystem mkswapfile --size 17G /mnt/swap/swapfile
swapon /mnt/swap/swapfile
```

Consider mounting any other auxiliary filesystem at this point

## Installation

The goal is to add AUR support as quickly as possible and use the `system-ilum-*` packages for the rest.

First install some base packages, enough to have at least something explicitely installed and enough to bootstrap the AUR and stuff:
```sh
pacstrap -K /mnt base linux base-devel stow efibootmgr grub neovim
```

Build and install paru:
```sh
git clone https://aur.archlinux.org/paru.git /tmp/paru
pushd /tmp/paru
makepkg -sfcC
pacman --root /mnt -U ./paru-*.pkg.*
popd
rm -r /tmp/paru
```

Change a few things about the filesystem:
```sh
genfstab -U /mnt >> /mnt/etc/fstab
```

Then create the `lucas` user and get the dotfiles:
```sh
arch-chroot /mnt
useradd --user-group --home-dir /home/lucas lucas
passwd lucas
groupadd sudo
usermod -aG sudo lucas
chown -R lucas:lucas /home/lucas
su lucas
git clone --recursive https://github.com/icanwalkonwater/dotfiles.git /home/lucas/dotfiles
pushd /home/lucas/dotfiles
stow paru fish
popd
exit
exit
```

Now we can start installing our config:
```sh
pacman --root /mnt -U system-ilum-skeleton-*.pkg.* system-ilum-base-*.pkg.*
# we can now use sudo as the normal user

arch-chroot /mnt
su lucas
paru -Syu system-ilum-base
ilum-patch patch # needed to add some stuff to the pacman.conf
paru -Syu system-ilum-full
chsh -s /usr/bin/fish # use fish
exit

locale-gen
ilum-grub install
passwd # root password
exit
```

Should be ok now:
```sh
umount -R /mnt
reboot
```
