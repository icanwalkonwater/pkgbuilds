#!/usr/bin/env nu

use system-utils.nu *

def main [] {
  pacman-tracked-configs | where status != unmodified
}
