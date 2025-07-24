#!/usr/bin/env nu

use std/assert

def "main export-db" [dest: path, --overwrite] {
  let db = collect-problematic-db --all
  print $"Writing to ($dest | boldify) ..."
  $db | to msgpackz | save --progress --force=$overwrite $dest
}

def "main explore" [db: path, --quiet (-q)] {
  print "Reading problematic files database..."
  let db = open $db | from msgpackz
  print $"Found ($db | length | boldify) problematic entries"

  let missing_package_files = $db | where package != null and exists == false
  print $"Found ($missing_package_files | length | boldify) missing package files"
  maybe-explore $missing_package_files $quiet

  let modified_package_configs = $db | where package != null and modified == true
  print $"Found ($modified_package_configs | length | boldify) modified config files"
  maybe-explore $modified_package_configs $quiet

  let unowned_dirs = $db | where package == null and exists == true and type == "dir"
  print $"Found ($unowned_dirs | length | boldify) unowned dirs"
  maybe-explore $unowned_dirs $quiet

  let unowned_files = $db | where package == null and exists == true and type != "dir"
  print $"Found ($unowned_files | length | boldify) unowned files"
  maybe-explore $unowned_files $quiet
}

def "main choose" [db: path] {
  # Step 1: Open previously built database of potentially problematic files
  let db_raw = open $db | from msgpackz
  print $"Loaded ($db_raw | length | boldify) problematic entries"

  # Step 2: Filter them successively
  print $"Filtering expected entries:"
  let db = $db_raw
    | db-adopt-ca-certificates
    | db-adopt-pacman-keys
    | db-adopt-mime
    | db-adopt-root-user-files
    | db-adopt-mkinitcpio
    | db-adopt-linux-modules
    | db-adopt-systemd-wants
    | db-adopt-nvidia-persistance
    | db-adopt-icon-themes-cache
    | keep-problematic
  print $"Filtered (($db_raw | length) - ($db | length) | boldify) false positives, there remains ($db | length | boldify) problematic entries"

  # Step 3: Categorize the rest with a diagnostic column
  # Possible diagnostics are:
  # - homeless: meaning it doesn't belong to any package, bad
  # - edited: meaning it is a package file that has changed and was not accounted for
  # - missing: package file that is not on the system, somehow it got deleted
  let db = $db | insert diagnostic {|r|
    if ($r.package == null) {
      "homeless"
    } else if ($r.package != null and $r.modified) {
      "edited"
    } else if ($r.package != null and not $r.present) {
      "missing"
    } else { null }
  }
  # Keep a boolean to know if the entry has been presented to the user
  mut db = $db | insert treated false

  # Step 4: Treat fully homeless dirs
  let fully_homeless_dirs = $db | where dir_fully_homeless == true
  let parent_fully_homeless_dirs = $fully_homeless_dirs
    | insert parent_homeless {|r| ($r.path | path dirname) in $fully_homeless_dirs.path}
    | where parent_homeless == false
    | drop column

  print $"Found ($parent_fully_homeless_dirs | length | boldify) completely homeless directories:"
  for $p in $parent_fully_homeless_dirs.path {
    $db = $db | update treated {|r|
      if ($r.path | str starts-with $p) {
        assert (not $r.treated)
        assert ($r.diagnostic == "homeless")
        true
      } else { $r.treated }
    }
    print $"  ($p | boldify)"
  }

  # Step 5: Treat leftover homeless files/symlinks/...
  let homeless_files = $db | where treated == false and diagnostic == "homeless" and type != "dir"
  print $"Found ($homeless_files | length | boldify) homeless files"
  for $p in $homeless_files.path {
    $db = $db | update treated {|r| $r.treated or $r.path == $p}
    print $"  ($p | boldify)"
  }

  let untreated = $db | where treated == false
  if ($untreated | is-not-empty) {
    print $"(ansi red)ERROR: There remains (ansi rb)($untreated | length)(ansi reset)(ansi red) untreated files(ansi reset)"
  }
  $untreated | explore
}

def main [] {
  print --stderr "No subcommand passed, see --help"
  exit 1
}

def collect-problematic-db [--limit: int, --all]: nothing -> table<path: string, package: string, modified: bool, exists: bool, type: string, dir_fully_homeless: bool> {
  print "Building problematic files database..."

  # Ask pacman for all the files owned by a package
  let package_files = ^pacman -Ql
    | lines
    | parse '{package} {path}'
    | update path {|| trim-path}
  print $"  Found ($package_files | length | boldify) package files"

  # Ask pacman for all (important) files that have changed
  let modified_package_files = ^pacman -Qii
    | ^jc --pacman
    | from json
    | select -i backup_files
    | flatten -a | where backup_files != null
    | update backup_files {|p| $p.backup_files | parse '{path} [{status}]'}
    | flatten -a
    | where status == "modified"
    | select path
    | insert modified true
  print $"  Found ($modified_package_files | length | boldify) modified package files"

  # List all files on the root filesystem
  let system_files = ^find -P / -xdev
    | lines
    | trim-path
    | uniq
    | where {|| ($in | str length) > 0}
    | wrap path
  print $"  Found ($system_files | length | boldify) files on this system"

  # Join all that ...
  let all = $package_files
    | join --outer $modified_package_files path
    | join --outer $system_files path
    | insert exists {|| $in.path | path exists}
    | insert type {|| $in.path | path type}
    | default false modified
  # ... and get the problematic entries
  let problematic = $all
    | keep-problematic
    | move --first path

  let with_homeless = $problematic
      | insert dir_fully_homeless {|r|
        if $r.package == null and $r.exists == true and $r.type == "dir" {
          ls $r.path | get name | all {|f| $f in $problematic.path}
        } else { false }
      }

  print $"Categorized ($with_homeless | length | boldify) out of ($all | length | boldify) files as problematic"

  $with_homeless
}

def keep-problematic [] {
  $in | where {|r| $r.path == null or $r.package == null or (not $r.exists) or $r.modified}
}

def db-adopt-ca-certificates [] {
  make-db-adopter "ca-certificates" "ca-certificates" --dirs [
    "/etc/ca-certificates/extracted/cadir",
  ] --files [
    "/etc/ca-certificates/extracted/tls-ca-bundle.pem",
    "/etc/ca-certificates/extracted/email-ca-bundle.pem",
    "/etc/ca-certificates/extracted/objsign-ca-bundle.pem",
    "/etc/ca-certificates/extracted/ca-bundle.trust.crt",
    "/etc/ca-certificates/extracted/edk2-cacerts.bin",
    "/etc/ca-certificates/extracted/java-cacerts.jks",
    "/etc/ssl/certs/java/cacerts",
  ] --patterns [
    "^/etc/ssl/certs/[a-z0-9]{8}\\.0$",
    "^/etc/ssl/certs/[a-zA-Z0-9_.-]+\\.pem$",
  ]
}

def db-adopt-pacman-keys [] {
  make-db-adopter "pacman-keys" "archlinux-keyring" --dirs ["/etc/pacman.d/gnupg"]
}

def db-adopt-mime [] {
  make-db-adopter "mime-info" "shared-mime-info" --dirs [
    "/usr/share/mime/inode",
    "/usr/share/mime/text",
    "/usr/share/mime/application",
    "/usr/share/mime/model",
    "/usr/share/mime/video",
    "/usr/share/mime/font",
    "/usr/share/mime/image",
    "/usr/share/mime/audio",
    "/usr/share/mime/multipart",
    "/usr/share/mime/x-content",
    "/usr/share/mime/message",
    "/usr/share/mime/chemical",
    "/usr/share/mime/x-epoc",
  ] --files [
    "/usr/share/mime/globs",
    "/usr/share/mime/globs2",
    "/usr/share/mime/magic",
    "/usr/share/mime/XMLnamespaces",
    "/usr/share/mime/subclasses",
    "/usr/share/mime/aliases",
    "/usr/share/mime/types",
    "/usr/share/mime/generic-icons",
    "/usr/share/mime/icons",
    "/usr/share/mime/treemagic",
    "/usr/share/mime/mime.cache",
    "/usr/share/mime/version",
    "/usr/share/applications/mimeinfo.cache",
  ]
}

def db-adopt-root-user-files [] {
  make-db-adopter "root-user-files" "system-ilum-skeleton" --dirs [
    "/root/.gnupg",
    "/root/.ssh",
    "/root/.local",
    "/root/.cache",
    "/root/.config",
  ]
}

def db-adopt-mkinitcpio [] {
  make-db-adopter "mkinitcpio-generated" "mkinitcpio" --files ["/etc/mkinitcpio.d/linux.preset"]
}

def db-adopt-linux-modules [] {
  let linux_v = uname | get kernel-release
  $in | make-db-adopter "kernel-modules-cache" "linux" --files [
    $"/usr/lib/modules/($linux_v)/modules.dep",
    $"/usr/lib/modules/($linux_v)/modules.dep.bin",
    $"/usr/lib/modules/($linux_v)/modules.alias",
    $"/usr/lib/modules/($linux_v)/modules.alias.bin",
    $"/usr/lib/modules/($linux_v)/modules.softdep",
    $"/usr/lib/modules/($linux_v)/modules.weakdep",
    $"/usr/lib/modules/($linux_v)/modules.symbols",
    $"/usr/lib/modules/($linux_v)/modules.symbols.bin",
    $"/usr/lib/modules/($linux_v)/modules.builtin.bin",
    $"/usr/lib/modules/($linux_v)/modules.builtin.alias.bin",
    $"/usr/lib/modules/($linux_v)/modules.devname",
  ]
}

def db-adopt-systemd-wants [] {
  make-db-adopter "systemd-wants-folders" "systemd" --patterns ["^/etc/systemd/system/[a-z0-9.-]+\\.wants$"]
}

def db-adopt-nvidia-persistance [] {
  make-db-adopter "nvidia-persistance-services" "nvida-utils" --files [
    "/etc/systemd/system/systemd-hibernate.service.wants/nvidia-hibernate.service",
    "/etc/systemd/system/systemd-hibernate.service.wants/nvidia-resume.service",
    "/etc/systemd/system/systemd-suspend.service.wants/nvidia-resume.service",
    "/etc/systemd/system/systemd-suspend.service.wants/nvidia-suspend.service",
    "/etc/systemd/system/systemd-suspend-then-hibernate.service.wants/nvidia-resume.service",
  ]
}

def db-adopt-icon-themes-cache [] {
  make-db-adopter "icon-theme-caches" "icon-themes" --patterns ["^/usr/share/icons/[a-zA-Z0-9_.-]+/icon-theme\\.cache$"]
}

def make-db-adopter [name: string, package: string, --dirs: list<string> = [], --files: list<string> = [], --patterns: list<string> = []] {
  let db = $in
  let pkg_files_before = $db | where package == $package | length

  mut db_out = $db
  for $d in $dirs {
    $db_out = $db_out | check-adopt-homeless-dir $package $d
  }
  for $f in $files {
    $db_out = $db_out | check-adopt-homeless-file $package $f
  }
  for $pattern in $patterns {
    for $f in ($db_out | where package == null | get path | find --no-highlight --regex $pattern) {
      $db_out = $db_out | check-adopt-homeless-file $package $f
    }
  }

  let pkg_files_after = $db_out | where package == $package | length
  # print $"  ($name | boldify) made ($package | boldify) adopt ($pkg_files_after - $pkg_files_before | boldify) entries"
  print $"  ($pkg_files_after - $pkg_files_before | boldify) entries adopted by ($package | boldify) \(via ($name | boldify)\)"
  $db_out
}

def check-adopt-homeless-dir [package: string, dir: string] {
  let db = $in
  if ($db | where path == $dir and type == "dir" and dir_fully_homeless == true | is-empty) {
    error make {msg: $"Known homeless dir isn't actually fully homeless: ($dir | boldify)"}
  }
  
  $db 
    | update package {|r| if ($r.path | str starts-with $dir) { $package } else { $r.package }}
    | update dir_fully_homeless {|r| if ($r.path | str starts-with $dir) { false } else { $r.dir_fully_homeless }}
}

def check-adopt-homeless-file [package: string, file: string] {
  let db = $in

  if ($db | where path == $file and package == null | is-empty) {
    error make {msg: $"Known homeless file isn't actually homeless: ($file | boldify)"}
  }

  $db | update package {|r| if ($r.path == $file) { $package } else { $r.package }}
}

def boldify []: any -> string {
  $"(ansi defb)($in)(ansi reset)"
}

def maybe-explore [data, quiet: bool] {
  if not $quiet and ($data | length) > 0 {
    $data | explore
  }
}

def trim-path [] {
  str trim --right --char '/'
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
