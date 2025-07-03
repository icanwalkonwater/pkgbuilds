# ilum-part status
## ilum-boot => fat32 OK
## ilum-
# ilum-part repair

def lsdisks [] {
  ls /dev/disk/by-diskseq
  | get name
  | filter { ($in | path basename) =~ ^\d+$ }
  | path expand
  | each { {dev: $in} }
  | upsert size {|row| ^lsblk -J --bytes -o name,size $row.dev | from json | get blockdevices.0.size | into filesize }
  | upsert partitioned {|row| ^lsblk -J -o name $row.dev | from json | get blockdevices.0 | get -i children | is-not-empty }
}

def lsparts [] {
  ls /dev/disk/by-diskseq | get name | filter { ($in | path basename) =~ ^\d+-part\d+$ } | path expand
}
