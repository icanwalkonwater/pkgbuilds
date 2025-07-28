#!/usr/bin/env nu

def main [--with-patched] {
  ^pacreport --backups --missing-files --unowned-files
  report-modified-backup-files --with-patched=$with_patched
}

def report-modified-backup-files [--with-patched] {
  let patched = glob "/usr/share/ilum/patches/*.patch" | path basename | str substring ..-7

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
        if ($f.file | path basename) in $patched {
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

# vim: set tabstop=2 shiftwidth=2 expandtab :
