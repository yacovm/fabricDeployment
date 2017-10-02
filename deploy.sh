#!/bin/bash -e

getIP() {
        ssh $1 "ip addr | grep 'inet .*global' | cut -f 6 -d ' ' | cut -f1 -d '/' | head -n 1"
}

probePeerOrOrderer() {
	echo "" | nc $1 7050 && return 0
	echo "" | nc $1 7051 && return 0
	return 1
}

probeFabric() {
        ssh $1 "ls /opt/gopath/src/github.com/hyperledger/fabric/ &> /dev/null || echo 'not found'" | grep -q "not found"
        if [ $? -eq 0 ];then
                echo "1"
                return
        fi
        echo "0"
}

deployFabric() {
        scp install.sh $1:install.sh
        ssh $1 "bash install.sh"
}

probeKafka() {
        ssh $1 "ls /opt/kafka_2.11-0.9.0.0 &> /dev/null || echo 'not found'" | grep -q "not found"
        if [ $? -eq 0 ];then
                echo "1"
                return
        fi
        echo "0"
}

deployKafka() {
    scp install-kafka.sh $1:install-kafka.sh
    ssh $1 "bash install-kafka.sh"
}

createChannel() {
    CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp CORE_PEER_LOCALMSPID=PeerOrg ./peer channel create $ORDERER_TLS -t 10 -f yacov.tx  -c yacov -o ${orderer}:7050 >&log.txt
    cat log.txt
}

query() {
    CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$1:7051 ./peer chaincode query -c '{"Args":["query","a"]}' -C yacov -n exampleCC -v 1.0  --tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/tls/ca.crt
}

invoke() {
        CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$1:7051 ./peer chaincode invoke -c '{"Args":["invoke","a","b","10"]}' -C yacov -n exampleCC -v 1.0  --tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/tls/ca.crt
}

[[ -z $GOPATH ]] && (echo "Environment variable GOPATH isn't set!"; exit 1)
FABRIC=$GOPATH/src/github.com/hyperledger/fabric
[[ -d "$FABRIC" ]] || (echo "Directory $FABRIC doesn't exist!"; exit 1)
for file in configtxgen peer cryptogen; do
	[[ -f $file ]] && continue
	binary=$FABRIC/build/bin/$file
	[[ ! -f $binary ]] && ( cd $FABRIC ; make $file)
	cp $binary $file && continue
done

for file in configtxgen peer cryptogen; do
	[[ ! -f $file ]] && echo "$file isn't found, aborting!" && exit 1
done

. config.sh

if [ $ordererType = "kafka" ]; then
	echo "Kafka Orderer"
elif [ $ordererType = "solo" ]; then
	echo "Solo Orderer"
else
	echo "Invalid orderer type: available 'kafka' or 'solo'"
	exit 1
fi

for p in $orderer $peers; do
        if [ `probeFabric $p` == "1" ];then
                echo "Didn't detect fabric installation on $p, proceeding to install fabric on it"
                deployFabric $p
        fi
done

for n in $ensamble ; do
    if [ `probeKafka $n` == "1" ]; then
        echo "Didn't detect kafka installation on $n, proceeding to install it."
        deployKafka $n
    fi
    ssh $n "mkdir -p /tmp/$zookeeper"
done

i=0
for b in $brokers ; do
    if [ `probeKafka $b` == "1" ]; then
        echo "Didn't detect kafka installation on $b, proceeding to install it."
        deployKafka $b
    fi
    ssh $b "mkdir -p /tmp/kafka-logs-$1"
    (( i += 1 ))
done

echo "Preparing configuration..."
rm -rf crypto-config
for p in $orderer $peers ; do
	rm -rf $p
done
bootPeer=$(echo ${peers} | awk '{print $1}')

PROPAGATEPEERNUM=${PROPAGATEPEERNUM:-3}
i=0
for p in $orderer $peers ; do
        mkdir -p config-$p/sampleconfig/crypto
        mkdir -p config-$p/sampleconfig/tls
        ip=$(getIP $p)
        echo "${p}'s ip address is ${ip}"
        orgLeader=false
        bootstrap=anchorPeer:7051
        if [[ $i -eq 1 ]];then
                orgLeader=true
        fi
        (( i += 1 ))
        cat core.yaml.template | sed "s/PROPAGATEPEERNUM/${PROPAGATEPEERNUM}/ ; s/PEERID/$p/ ; s/ADDRESS/$p/ ; s/ORGLEADER/$orgLeader/ ; s/BOOTSTRAP/$bootPeer:7051/ ; s/TLS_CERT/$p.hrl.ibm.il-cert.pem/" > config-$p/sampleconfig/core.yaml
done

if [ $ordererType = "kafka" ]; then
    cat configtx-kafka.yaml.template | sed "s/ANCHOR_PEER_IP/anchorpeer/ ; s/ORDERER_IP/$orderer/" > configtx.yaml
    port=9092
    for  b in $brokers; do
        ip=$(getIP $b)
        echo "       - $ip:$port" >> configtx.yaml
        (( port += 1 ))
    done
    echo "    Organizations:"  >> configtx.yaml
    echo "Application: &ApplicationDefaults" >> configtx.yaml
    echo "    Organizations:" >> configtx.yaml
	ip=$(getIP $orderer)
	cat crypto-config-kafka.yml.template | sed "s/ORDERER_IP/$ip/ ; s/ORDERER_HOSTNAME/$orderer/" > crypto-config.yml
	for p in $peers ; do
    	ip=$(getIP $p)
    	echo "        - Hostname: $p" >> crypto-config.yml
    	echo "          SANS:" >> crypto-config.yml
    	echo "            - $ip" >> crypto-config.yml
	done
    echo "    Users:" >> crypto-config.yml
    echo "      Count: 1" >> crypto-config.yml
else
	cat configtx.yaml.template | sed "s/ANCHOR_PEER_IP/anchorpeer/ ; s/ORDERER_IP/$orderer/" > configtx.yaml
    cat crypto-config.yml.template | sed "s/ORDERER_IP/$orderer/" > crypto-config.yml
    for p in $peers ; do
        echo "        - Hostname: $p" >> crypto-config.yml
    done
	echo "    Users:" >> crypto-config.yml
	echo "      Count: 1" >> crypto-config.yml
fi

./cryptogen generate --config crypto-config.yml
./configtxgen -profile Genesis -outputBlock genesis.block  -channelID system
./configtxgen -profile Channels -outputCreateChannelTx yacov.tx -channelID yacov


ORDERER_TLS="--tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/tls/ca.crt"
export CORE_PEER_TLS_ROOTCERT_FILE=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/peers/${bootPeer}.hrl.ibm.il/tls/ca.crt
export CORE_PEER_TLS_ENABLED=true

mv genesis.block config-$orderer/sampleconfig/
cp orderer.yaml config-$orderer/sampleconfig/

cp -r crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/msp/* config-$orderer/sampleconfig/crypto
for p in $peers ; do
        cp -r crypto-config/peerOrganizations/hrl.ibm.il/peers/$p.hrl.ibm.il/msp/* config-$p/sampleconfig/crypto
        cp -r crypto-config/peerOrganizations/hrl.ibm.il/peers/$p.hrl.ibm.il/tls/* config-$p/sampleconfig/tls/
done
cp -r crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/tls/* config-$orderer/sampleconfig/tls
if [ $ordererType = "kafka" ]; then
	connect=""
	for n in $ensamble; do
    	    connect="$n:2181, $connect"
	done
	i=0
	port=9092
	for b in $brokers; do
    	cat server.properties.template | sed "s/BROKER_ID/$i/ ; s/LOGS_DIR/kafka-logs-$i/ ; s/ZOOKEEPER_CONNECT/$connect/ ; s/BROKER_PORT/$port/" > server.properties
    	scp server.properties $b:/opt/kafka_2.11-0.9.0.0/config/server-$i.properties
    	rm server.properties
    	(( i += 1 ))
    	(( port += 1 ))
	done
fi

echo "Deploying configuration"
for p in $orderer $peers ; do
        ssh $p "pkill orderer; pkill peer" || echo ""
        ssh $p "rm -rf /var/hyperledger/production/*"
        ssh $p "rm -rf /opt/gopath/src/github.com/hyperledger/fabric/sampleconfig/*"
        ssh $p "cd /opt/gopath/src/github.com/hyperledger/fabric ; git reset HEAD --hard && git pull"
        scp -r config-$p/sampleconfig/* $p:/opt/gopath/src/github.com/hyperledger/fabric/sampleconfig/
done


echo "killing docker containers"
for p in $peers ; do
        ssh $p "docker ps -aq | xargs docker kill &> /dev/null " || echo -n "."
        ssh $p "docker ps -aq | xargs docker rm &> /dev/null " || echo -n "."
        ssh $p "docker images | grep 'dev-' | awk '{print $3}' | xargs docker rmi &> /dev/null " || echo -n "."
done

if [ $ordererType = "kafka" ]; then
	echo "Bringing down zookeeper"
	for n in $ensamble ; do
    	ssh $n "pkill java" || echo -n "."
    	ssh $n "rm -rf /opt/kafka_2.11-0.9.0.0/logs/*"
    	ssh $n "rm -rf /tmp/zookeeper/*"
	done

	sleep 10

	echo "Bringing down brokers"
	i=0
	for b in $brokers ; do
    	ssh $b "pkill -9 java" || echo -n "."
    	ssh $b "rm -rf /opt/kafka_2.11-0.9.0.0/logs/*"
    	ssh $b "rm -rf /tmp/kafka-logs-$i/*"
   		(( i += 1 ))
	done

	echo "Starting zookeeper"
	for n in $ensamble ; do
    	ssh $n "/opt/kafka_2.11-0.9.0.0/bin/zookeeper-server-start.sh /opt/kafka_2.11-0.9.0.0/config/zookeeper.properties > zookeeper.out &"
	done

	sleep 10

	echo "Starting kafka"
	i=0
	for b in $brokers ; do
    	ssh $b "/opt/kafka_2.11-0.9.0.0/bin/kafka-server-start.sh /opt/kafka_2.11-0.9.0.0/config/server-$i.properties > broker-$i.out &"
    	(( i += 1 ))
	done

	sleep 10
fi

echo "Installing orderer"
ssh $orderer "bash -c '. ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ; make orderer && make peer'"
echo "Installing peers"
for p in $peers ; do
	echo "Installing peer $p"
        ssh $p "bash -c '. ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ; make peer' " 
done

echo "Starting orderer"
ssh $orderer " . ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ;  echo './build/bin/orderer &> orderer.out &' > start.sh; bash start.sh "
for p in $peers ; do
        echo "Starting peer $p"
	ssh $p " . ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ;  echo './build/bin/peer node start &> $p.out &' > start.sh; bash start.sh "
done

echo "waiting for orderer and peers to be online"
while :; do
	allOnline=true
	for p in $orderer $peers; do
		if [[ `probePeerOrOrderer $p` -ne 0 ]];then
			echo "$p isn't online yet"
			allOnline=false
			break;
		fi
	done
	if [ "${allOnline}" == "true" ];then
		break;
	fi
	sleep 5
done

sleep 20
echo "Creating channel"
createChannel

echo "Joining peers to channel"
for p in $peers ; do
    CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$p:7051 ./peer channel join -b yacov.block
done


for p in $peers ; do
	echo -n "Installing chaincode on $p..."
    CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$p:7051 ./peer chaincode install -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 -n exampleCC -v 1.0
	echo ""
done


echo "Instantiating chaincode..."
CORE_PEER_TLS_ROOTCERT_FILE=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/peers/${bootPeer}.hrl.ibm.il/tls/ca.crt CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=${bootPeer}:7051 ./peer chaincode instantiate -n exampleCC -v 1.0 -C yacov -c '{"Args":["init","a","100","b","200"]}' -o ${orderer}:7050 --tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${orderer}.hrl.ibm.il/tls/ca.crt

sleep 10

echo "Invoking chaincode..."
for p in $peers ; do
	query $p
done

for i in `seq 5`; do
        invoke ${bootPeer}
done

echo "Waiting for peers $peers to sync..."
t1=`date +%s`
while :; do
	allInSync=true
	for p in $peers ; do
	    echo "Querying $p..."
	    query $p | grep -q 'Query Result: 50'
	    if [[ $? -ne 0 ]];then
		    allInSync=false
	    fi
	done
	if [ "${allInSync}" == "true" ];then
		echo Sync took $(( $(date +%s) - $t1 ))s
		break
	fi
done
