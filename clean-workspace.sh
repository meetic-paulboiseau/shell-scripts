#!/bin/bash
folder=$1
servers=("da2shgh301" "da2shgh302" "da2shgh303" "da2shgh304" "da2shgh305" "da2shgh306" "da2shgh307" "da2shgh308" "da2shgh309" "da2shgh310" "da2shgh311" "da2shgh312" "da2shgh313" "da2shgh314")
for s in "${servers[@]}"; do
  echo "Running on $s"
  ssh paul.boiseau@"$s" "sudo rm -rf /opt/actions-runner/_work/$folder"
done
