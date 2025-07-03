#!/usr/bin/env nu

use std/log
use std/assert

def main []: nothing -> nothing {
  ^$env.CURRENT_FILE --help
}

# == status

def "main status" [
  --partlabel-boot: string = "ilum-boot",
  --partlabel-root: string = "ilum-root",
  --label-boot: string = "ilum-bootfs",
  --label-root: string = "ilum-rootfs",
]: nothing -> nothing {
  assert-command-supported lsblk;

  print $"(ansi green)Boot setup status(ansi reset)"

  print [
    {
      description: "Boot partition exists",
      status: ($"/dev/disk/by-partlabel/($partlabel_boot)" | path exists),
    },
    {
      description: "Boot filesystem exists",
      status: ($"/dev/disk/by-label/($label_boot)" | path exists),
    },


    {
      description: "Root partition exists",
      status: ($"/dev/disk/by-partlabel/($partlabel_root)" | path exists),
    },
    {
      description: "Root filesystem exists",
      status: ($"/dev/disk/by-label/($label_root)" | path exists),
    },
  ];
}

# == mkparts

def "main mkparts" [
  disk: path,                         # Disk to format
  --label-boot: string = "ilum-boot", # Partition label for boot partition
  --label-root: string = "ilum-root", # Partition label for root partition
  --dry-run,                          # Don't actually do any writes
  --overwrite,                        # Overwrite any existing partition table
]: nothing -> nothing {
  assert-command-supported lsblk;
  assert-command-supported sfdisk;
  assert-command-supported partprobe;
  set-dry-run $dry_run;
  assert-superuser;

  if not (is-real-disk $disk) {
    error make { msg: "Not a valid disk", label: { text: "Not a valid disk", span: (metadata $disk).span } };
  }

  if not ((is-disk-empty $disk) or $overwrite) {
    print -e $"(ansi red)ERROR: Disk is already partitionned, use --overwrite if this is what you want(ansi reset)";
    exit 1;
  }

  if ($"/dev/disk/by-partlabel/($label_boot)" | path exists) {
    if ($overwrite) {
      print -e $"(ansi yellow)WARNING: There is another partition labelled ($label_boot), ignored because of --overwrite(ansi reset)";
    } else {
      error make { msg: "There is another partition with that label", label: { text: "This label", span: (metadata $label_boot).span } };
    }
  }
  if ($"/dev/disk/by-partlabel/($label_root)" | path exists) {
    if ($overwrite) {
      print -e $"(ansi yellow)WARNING: There is another partition labelled ($label_root), ignored because of --overwrite(ansi reset)";
    } else {
      error make { msg: "There is another partition with that label", label: { text: "This label", span: (metadata $label_root).span } };
    }
  }

  # Start doing stuff

  if ($overwrite) {
    disk-wipe $disk;
  }
  disk-mkpart $disk --label-boot=$label_boot --label-root=$label_root;

  # Sanity checks
  if not (is-dry-run) {
    safe-run [partprobe $disk];
    sleep 1sec;
    assert ($"/dev/disk/by-partlabel/($label_boot)" | path exists);
    assert ($"/dev/disk/by-partlabel/($label_root)" | path exists);
  }

  print ''
  print $"(ansi green)Partitionning OK !(ansi reset)"
}

def disk-wipe [disk: path]: nothing -> nothing {
  safe-run [sfdisk --delete $disk] | assert equal $in.exit_code 0;
}

def disk-mkpart [disk: path, --label-boot: string, --label-root: string]: nothing -> nothing {
  let headers = {label: gpt};
  let partitions = [
    {size: '256MiB', type: uefi, name: $label_boot},
    {size: +, type: linux, name: $label_root},
  ];

  print $"(ansi default_underline)Sfdisk script(ansi reset):";
  {Headers: $headers, Partitions: $partitions} | table --expand --theme light | print;
  print '';

  let script = [
    $"label: ($headers.label)",
    ...($partitions | each { $"size=($in.size), type=($in.type), name=($in.name)" }),
  ] | str join "\n";

  $script | safe-run [sfdisk --quiet $disk] | assert equal $in.exit_code 0;
}

# == mkfs

def "main mkfs" [
  --boot: path = /dev/disk/by-partlabel/ilum-boot, # Partition to use as boot filesystem
  --root: path = /dev/disk/by-partlabel/ilum-root, # Partition to use as root filesystem
  --label-bootfs: string = "ilum-bootfs",          # Label for the boot filesystem
  --label-rootfs: string = "ilum-rootfs",          # Label for the root filesystem
  --dry-run,
]: nothing -> nothing {
  assert-command-supported lsblk;
  assert-command-supported mkfs.vfat;
  assert-command-supported mkfs.btrfs;
  set-dry-run $dry_run;
  assert-superuser;

  if not (is-real-part $boot) {
    error make { msg: "Not a valid partition", label: { text: "Not a valid partition", span: (metadata $boot).span } };
  }
  if not (is-real-part $root) {
    error make { msg: "Not a valid partition", label: { text: "Not a valid partition", span: (metadata $root).span } };
  }
}

# == Utils

def --env set-dry-run [dry_run: bool]: nothing -> nothing {
  $env.DRYRUN = $dry_run;
}

def is-dry-run []: nothing -> bool {
  $env.DRYRUN == true
}

def assert-command-supported [cmd: string]: nothing -> nothing {
  if (which $cmd | is-empty) {
    print -e $"(ansi red)ERROR: Couldn't find `($cmd)` command, aborting(ansi reset)";
    exit 1;
  }
}

def assert-superuser []: nothing -> nothing {
  if not ((is-admin) or (is-dry-run)) {
    print -e $"(ansi red)ERROR: Not a superuser, aborting(ansi reset)";
    exit 1;
  }
}

def is-real-disk [disk: path]: nothing -> bool {
  try { (^lsblk -J -o type $disk e> /dev/null | from json | get blockdevices.0.type) == "disk" } catch { false }
}

def is-real-part [part: path]: nothing -> bool {
  try { (^lsblk -J -o type $part e> /dev/null | from json | get blockdevices.0.type) == "part" } catch { false }
}

def is-disk-empty [disk: path]: nothing -> bool {
  (^lsblk -J -o name $disk | from json | get blockdevices.0 | default [] children | get children | is-empty)
}

def safe-run [command: list<string>]: any -> record<stdout: string, stderr: string, exit_code: int> {
  if (is-dry-run) {
    print $"(ansi default_underline)Dry-running(ansi reset): ($command | str join ' ')";
    {stdout: "", stderr: "", exit_code: 0}
  } else {
    print $"(ansi default_underline)Running(ansi reset): ($command | str join ' ')";
    $in | run-external ...$command | complete
  }
}
