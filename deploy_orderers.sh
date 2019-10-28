#!/usr/bin/env bash

set -e

. config.sh

cp orderer.yaml.template orderer.yaml 
sed -i "s|DATA_DIR|${datadir}|g" orderer.yaml

echo -n "Checking binaries (orderer, cryptogen, configtxgen) exist in path... "
for binary in orderer cryptogen configtxgen; do
    which $binary &> /dev/null

    if [[ $? -ne 0 ]]; then
        echo "No $binary in PATH"
        exit 1
    fi
done

echo "OK"


echo "Checking ssh connectivity..."

for orderer in $orderers; do
	ip="${hostIPs[$orderer]}"
	echo -n "	Probing $orderer with ip of $ip... "
	ssh $ip "ls" > /dev/null
	if [ $? -ne 0 ];then
		echo "Failed"
	else 
		echo "OK"
	fi
done


bash create-crypto-config.sh


configtxgen -profile SampleMultiNodeSmartBFT -outputBlock genesis.block  -channelID systemchannel

for orderer in $orderers; do
        ip="${hostIPs[$orderer]}"
	echo "	Killing orderer $orderer... "
	ssh $ip "pkill orderer || true" 
        echo -n "       Creating directory for WAL in $orderer at $datadir/wal... "
        ssh $ip "mkdir -p $datadir/wal" || exit 2
        echo "OK"
        echo -n "       Sending orderer binary to $orderer... "
        scp `which orderer` $ip:$datadir/ &> /dev/null
        if [ $? -ne 0 ];then
                echo "Failed"
                exit 3
        else
                echo "OK"
        fi

        echo -n "       Sending orderer.yaml to $orderer... "
        scp orderer.yaml $ip:$datadir/ &> /dev/null
        if [ $? -ne 0 ];then
                echo "Failed"
                exit 4
        else
                echo "OK"
        fi

	echo -n "	Sending genesis.block to $orderer... "
        scp genesis.block $ip:$datadir/ &> /dev/null
        if [ $? -ne 0 ];then
                echo "Failed"
                exit 5
        else
                echo "OK"
        fi

	echo -n "	Sending keys to $orderer... "
	scp -r crypto-config/ordererOrganizations/example.com/orderers/${orderer}.example.com/* $ip:$datadir/ &> /dev/null
        if [ $? -ne 0 ];then
                echo "Failed"
                exit 6
        else
                echo "OK"
        fi

cat << EOF > run.sh
cd $datadir
rm -rf ledger
FABRIC_CFG_PATH=\`pwd\` ./orderer &> out.log &
EOF

	echo -n "Copying orderer startup script... "
	scp run.sh $ip:$datadir/ &> /dev/null
        if [ $? -ne 0 ];then
                echo "Failed"
                exit 7
        else
                echo "OK"
        fi
done

echo "Starting orderers"

for orderer in $orderers; do
        ip="${hostIPs[$orderer]}"
	
	echo "Starting orderer at $orderer... "
	ssh $ip "bash $datadir/run.sh"
	
done


