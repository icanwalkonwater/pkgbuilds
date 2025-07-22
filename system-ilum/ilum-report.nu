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
    | db-filter-ca-certificates
    | db-filter-pacman-keys
    | db-filter-mime
    | db-filter-root-user-files
    | db-filter-mkinitcpio
    | db-filter-linux-modules
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

  # Step 5: Treat leftover homeless files
  let homeless_files = $db | where treated == false and diagnostic == "homeless" and type == "file"
  print $"Found ($homeless_files | length | boldify) homeless files"
  for $p in $homeless_files.path {
    $db = $db | update treated {|r| $r.treated or $r.path == $p}
    print $"  ($p | boldify)"
  }

  let untreated = $db | where treated == false
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

def db-filter-ca-certificates [] {
  make-db-filter "ca-certificates" [
    "/etc/ca-certificates/extracted/cadir",
  ] [
    "/etc/ca-certificates/extracted/tls-ca-bundle.pem",
    "/etc/ca-certificates/extracted/email-ca-bundle.pem",
    "/etc/ca-certificates/extracted/objsign-ca-bundle.pem",
    "/etc/ca-certificates/extracted/ca-bundle.trust.crt",
    "/etc/ca-certificates/extracted/edk2-cacerts.bin",
    "/etc/ca-certificates/extracted/java-cacerts.jks",
  ]
}

def db-filter-pacman-keys [] {
  make-db-filter "pacman-keys" ["/etc/pacman.d/gnupg"]
}

def db-filter-mime [] {
  make-db-filter "mime-info" [
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
  ] [
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

def db-filter-root-user-files [] {
  make-db-filter "root-user-files" [
    "/root/.gnupg",
    "/root/.ssh",
    "/root/.local",
    "/root/.cache",
    "/root/.config",
  ]
}

def db-filter-mkinitcpio [] {
  make-db-filter "mkinitcpio-generated" [] ["/etc/mkinitcpio.d/linux.preset"]
}

def db-filter-linux-modules [] {
  let linux_v = uname | get kernel-release
  $in | make-db-filter "linux-modules-deps" [] [
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

def make-db-filter [name: string, known_homeless_dirs: list<string> = [], known_homeless_files: list<string> = []] {
  let db = $in
  let db_len_before = $db | length
  mut db_out = $db
  for $d in $known_homeless_dirs {
    $db_out = $db_out | check-ignore-known-homeless-dir $d
  }
  for $f in $known_homeless_files {
    $db_out = $db_out | check-ignore-known-homeless-file $f
  }
  let db_len_after = $db_out | length

  print $"  ($name | boldify) filtered ($db_len_before - $db_len_after | boldify) entries"
  $db_out
}

def check-ignore-known-homeless-dir [dir: string] {
  let db = $in
  if ($db.path | find -r $"^($dir)$" | is-empty) {
    error make {msg: $"Known homeless dir isn't fully homeless: ($dir)"}
  }

  $db | where {|r| not ($r.path | str starts-with $dir)}
}

def check-ignore-known-homeless-file [file: string] {
  let db = $in
  if ($db | where {|r| $r.path == $file} | is-empty) {
    error make {msg: $"Known homeless file couldn't be found: ($file)"}
  }

  $db | where {|r| $r.path != $file}
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
