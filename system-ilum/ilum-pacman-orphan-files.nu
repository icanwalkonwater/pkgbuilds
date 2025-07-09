#!/usr/bin/env nu

use system-utils.nu *

def main [] {
  pacman-not-owned-files | get file | each {ls $in} | flatten
}
