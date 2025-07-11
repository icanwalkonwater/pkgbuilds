#!/usr/bin/env nu

let all_package_owned_files = ^pacman -Ql
  | lines
  | parse '{package} {file}'
  | update file {|| str trim --right --char '/'} # Remove trailling slash

let missing_package_files = $all_package_owned_files
  | where not ($it.file | path exists)

let all_system_files = ^find -P / -xdev
  | lines
  | where {($in | str length) > 0} # Edge case where the path is empty
  | str trim --right --char '/' # Remove trailling slash
  | uniq
  | wrap file
  | insert present true

let unowned_files = $all_package_owned_files | join --right $all_system_files file | where package == null

let all_package_owned_dirs = $all_package_owned_files
  | where ($it.file | path type) == 'dir'

let all_system_dirs = $all_system_files
  | where ($it.file | path type) == 'dir'

let unowned_dirs = $all_package_owned_dirs | join --right $all_system_dirs file | where package == null

def main [] {
  print $"Found (ansi defb)($missing_package_files | length)(ansi reset) missing package files"
  print $"Found (ansi defb)($unowned_files | length)(ansi reset) unowned files"
  print $"Found (ansi defb)($unowned_dirs | length)(ansi reset) unowned dirs"

  $unowned_dirs | explore
}


