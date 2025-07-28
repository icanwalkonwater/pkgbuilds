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

  let targets = if ($targets | is-empty) {
    glob $"($patches_dir)/*.patch" | str substring ..-7
  } else {
    $targets
  }

  let targets = $targets | each {path basename}

  for target in $targets {
    let patch = $"($patches_dir)/($target).patch" | path expand
    if not ($patch | path exists) {
      error make {msg: $"Patch file ($patch | boldify) does not exists !"}
    }

    # If applying the patch in reverse works, it means its already applied
    let reverse_patch_res = ^patch --dry-run --reverse --force --directory=/ --unified --reject-file=- --strip=1 --input=($patch) | complete
    if $reverse_patch_res.exit_code == 0 {
      print $"Patch already applied: ($patch | boldify)"
      continue
    }

    if $dry_run {
      print $"Would apply patch ($patch | boldify)"
      continue
    }

    let patch_res = ^patch --directory=/ --unified --reject-file=- --forward --strip=1 --input=($patch) | complete
    if $patch_res.exit_code == 0 {
      print $"Applied patch: ($patch | boldify)"
    } else {
      print $"Failed to apply patch: ($patch | boldify)"
      if ($patch_res.stdout | str trim | is-not-empty) {
        print ""
        print ($patch_res.stdout | str trim)
        print ""
      }
      print $"(ansi rb)MANUAL INTERVENTION IS REQUIRED(ansi reset)"
    }
  }
}

def main [] {
  print "No subcommand provided, see --help"
  exit 1
}

def boldify [] {
  $"(ansi defb)($in)(ansi reset)"
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
