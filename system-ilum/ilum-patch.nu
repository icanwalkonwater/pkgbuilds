#!/usr/bin/env -S nu --stdin

def "main diff" [file: string] {
  # pacman -F returns the package prefixed with the repo like core/linux, strip the prefix
  let pkg = ^pacman -Fq $file | split row / | last
  let pkg_version = ^pacman -Qi $pkg | ^jc --pacman | from json | first | format pattern "{version}-{architecture}"
  let original = mktemp
  ^tar -xOf $"/var/cache/pacman/pkg/($pkg)-($pkg_version).pkg.tar.zst" ($file | str substring 1..) o> $original

  # make the diff and replace the first 2 occurences of the temp file
  # also remove the index line
  let diff = ^git diff --patch --unified --no-index $original $file
    | str replace $original $file
    | str replace $original $file
    | str replace --regex --multiline "^index .+\n" ""

  rm $original
  $diff
}

def "main patch" [
  ...targets: string, # The configs to patch, ignored if --stdin is used
  --patches-dir: string = "/usr/share/ilum/patches", # Central patch directory to get patches from
  --stdin, # If set, take the targets from stdin
  --dry-run, # Don't actually patch if provided
] {
  let targets = if $stdin {
    $in | str trim | lines
  } else {
    $targets
  }

  # If no target specified, just run all the patches.
  if ($targets | is-empty) {
    for $stock_patch in (glob $"($patches_dir)/*.patch") {
      do-patch $stock_patch --dry-run=$dry_run
    }
    return
  }

  let patches = $targets | each {str trim --left --char=/ | str replace --all "/" "-" | $"($patches_dir)/($in).patch"}

  for $p in $patches {
    if not ($p | path exists) {
      error make {msg: $"Patch file ($p | boldify) does not exists !"}
    }

    do-patch $p --dry-run=$dry_run
  }
}

def do-patch [patch_file: string, --dry-run] {
  let reverse_patch_res = ^patch --dry-run --reverse --force --directory=/ --unified --reject-file=- --strip=1 --input=($patch_file) | complete
  if $reverse_patch_res.exit_code == 0 {
    print $"Patch already applied: ($patch_file | boldify)"
    return
  }

  if $dry_run {
    print $"Would apply patch ($patch_file | boldify)"
    return
  }

  let patch_res = ^patch --directory=/ --unified --reject-file=- --forward --strip=1 --input=($patch_file) | complete
  if $patch_res.exit_code == 0 {
    print $"Patch applied: ($patch_file | boldify)"
  } else {
    print $"Failed to apply patch: ($patch_file | boldify)"
    if ($patch_res.stdout | str trim | is-not-empty) {
      print ""
      print ($patch_res.stdout | str trim)
      print ""
    }
    print $"(ansi rb)MANUAL INTERVENTION IS REQUIRED(ansi reset)"
  }
  exit 1
}

def main [] {
  print "No subcommand provided, see --help"
  exit 1
}

def boldify [] {
  $"(ansi defb)($in)(ansi reset)"
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
