#!/usr/bin/env nu

def "main install" [
  --efi-directory: string = "/boot",
  --theme: string = "minegrub-world-selection",
  --root: string = "/"
] {
  if not (is-admin) {
    print "ERROR: This commands need superuser privileges"
    exit 1
  }

  let theme_path = $"($root)/usr/share/grub/themes/($theme)"

  if not ($theme_path | path exists) {
    print "ERROR: Theme does not exists"
    exit 1
  }

  print "INFO: Running grub-install..."
  ^grub-install --target=x86_64-efi --efi-directory=($efi_directory) --bootloader-id=GRUB --removable

  print "INFO: Installing theme..."
  let theme_target_path = $"($efi_directory)/grub/themes/($theme)"
  mkdir $theme_target_path
  cp --recursive --progress $theme_path $theme_target_path

  print "INFO: Generating config..."
  ^grub-mkconfig -o $"($efi_directory)/grub/grub.cfg"
}

def main [] {
  print "Usage: install"
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
