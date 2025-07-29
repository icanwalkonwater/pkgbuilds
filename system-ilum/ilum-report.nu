#!/usr/bin/env nu

def main [--with-patched] {
  if not (is-admin) {
    print $"(ansi rb)ERROR:(ansi reset) Rerun as superuser"
    exit 1
  }

  ^pacreport --backups --missing-files --unowned-files
  report-modified-backup-files --with-patched=$with_patched
}

def report-modified-backup-files [--with-patched] {
  let modified = ^pacman -Qii
    | ^jc --pacman
    | from json
    | select -o backup_files
    | flatten -a
    | where backup_files != null
    | update backup_files {|p| $p.backup_files | parse '{file} [{status}]'}
    | flatten -a
    | where status == "modified"
    | update status {|f|
        if ($f.file | as-patch-name | path exists) {
          "patched"
        } else {
          $f.status
        }
      }

  print "Modified Backup Files:"
  for $f in $modified {
    if $f.status == "patched" {
      print $"  ($f.file)\t\(patched\)"
    } else {
      print $"  ($f.file)"
    }
  }
}

def as-patch-name []: string -> string {
  str trim --left --char="/" | str replace --all "/" "-" | $"/usr/share/ilum/patches/($in).patch"
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
