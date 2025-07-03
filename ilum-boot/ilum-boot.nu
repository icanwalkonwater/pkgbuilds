#!/usr/bin/env nu

def main []: nothing -> nothing {
  print -e "No subcommand given, try --help."
}

# Install grub at ESP
def "main grub-install" [esp: string = "/boot"]: nothing -> nothing {
  if not (is-admin) {
    print -e "Not a superuser, aborting"
    return
  }

  ^grub-install --target=x86_64-efi --efi-directory=$esp --bootloader-id=GRUB --removable
}

# Regenerate the grub config at ESP/grub/grub.cfg
def "main grub-mkconfig" [esp: string = "/boot"]: nothing -> nothing {
  if not (is-admin) {
    print -e "Not a superuser, aborting"
    return
  }

  print "Updating grub config..."
  ^grub-mkconfig -o $"($esp)/grub/grub.cfg"
}
