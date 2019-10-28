#!/usr/bin/env bash
orderers="vm1 vm2 vm3 vm4"
#peers="vm2 vm3"
datadir="/home/yacovm/smartBFT"

declare -A hostIPs=( ["vm1"]="192.168.56.2" ["vm2"]="192.168.56.3" ["vm3"]="192.168.56.4" ["vm4"]="192.168.56.5" )
