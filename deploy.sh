#!/bin/bash -e



function getIP() {
        ssh $1 "ip addr | grep 'inet .*global' | cut -f 6 -d ' ' | cut -f1 -d '/' | head -n 1"
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


function invoke() {
        CORE_PEER_TLS_ROOTCERT_FILE=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/peers/peer0.hrl.ibm.il/tls/ca.crt CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$1:7051 ./peer chaincode invoke -c '{"Args": ["invoke", "100", "10"]}' -C YACOV -n metrics -v 1.0  --tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${ordererIP}.hrl.ibm.il/tls/ca.crt
}

peers="peer0 peer1 peer2 peer3 peer4 peer5 peer6 peer7"
for p in orderer $peers; do
        if [ `probeFabric $p` == "1" ];then
                echo "Didn't detect fabric installation on $p, proceeding to install fabric on it"
                deployFabric $p
        fi
done

echo "Preparing configuration..."
rm -rf crypto-config
ordererIP=`getIP orderer`
anchorPeerIP=`getIP peer0`


PROPAGATEPEERNUM=${PROPAGATEPEERNUM:-3}
for p in orderer $peers ; do
        mkdir -p $p/sampleconfig/crypto
        mkdir -p $p/sampleconfig/tls
        ip=$(getIP $p)
        echo "${p}'s ip address is ${ip}"
        orgLeader=false
        bootstrap=peer0:7051
        if [[ $p == "peer0" ]];then
                orgLeader=true
                bootstrap=""
        fi
        cat core.yaml.template | sed "s/PROPAGATEPEERNUM/${PROPAGATEPEERNUM}/ ; s/PEERID/$p/ ; s/ADDRESS/$p/ ; s/ORGLEADER/$orgLeader/ ; s/BOOTSTRAP/$bootstrap/ ; s/TLS_CERT/$p.hrl.ibm.il-cert.pem/" > $p/sampleconfig/core.yaml
done

cat configtx.yaml.template | sed "s/ANCHOR_PEER_IP/anchorpeer/ ; s/ORDERER_IP/${ordererIP}/" > configtx.yaml

./cryptogen generate --config crypto-config.yml
./configtxgen -profile Genesis -outputBlock genesis.block  -channelID SYSTEM
./configtxgen -profile Channels -outputCreateChannelTx YACOV.tx -channelID YACOV


ORDERER_TLS="--tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${ordererIP}.hrl.ibm.il/tls/ca.crt"
export CORE_PEER_TLS_ROOTCERT_FILE=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/peers/peer0.hrl.ibm.il/tls/ca.crt


mv genesis.block orderer/sampleconfig/
cp orderer.yaml orderer/sampleconfig/

cp -r crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${ordererIP}.hrl.ibm.il/msp/* orderer/sampleconfig/crypto
i=0
for p in $peers ; do
        cp -r crypto-config/peerOrganizations/hrl.ibm.il/peers/peer${i}.hrl.ibm.il/msp/* $p/sampleconfig/crypto
        cp -r crypto-config/peerOrganizations/hrl.ibm.il/peers/peer${i}.hrl.ibm.il/tls/* $p/sampleconfig/tls/
        (( i += 1 ))
done

cp -r crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${ordererIP}.hrl.ibm.il/tls/* orderer/sampleconfig/tls

echo "Deploying configuration"

for p in orderer $peers ; do
        ssh $p "pkill orderer; pkill peer" || echo ""
        ssh $p "rm -rf /var/hyperledger/production/*"
        #ssh $p "cd /opt/gopath/src/github.com/hyperledger/fabric ; git reset HEAD --hard && git pull -f git@github.ibm.com:YACOVM/metricsIntegration.git metricsIntegration2"
        ssh $p "cd /opt/gopath/src/github.com/hyperledger/fabric ; git reset HEAD --hard && git pull /opt/gopath/src/github.com/hyperledger/fabric"
        scp -r $p/sampleconfig/* $p:/opt/gopath/src/github.com/hyperledger/fabric/sampleconfig/
done


echo "killing docker containers"
for p in $peers ; do
        ssh $p "docker ps -aq | xargs docker kill &> /dev/null " || echo -n "."
        ssh $p "docker ps -aq | xargs docker rm &> /dev/null " || echo -n "."
        ssh $p "docker images | grep dev-peer | awk '{print $3}' | xargs docker rmi &> /dev/null " || echo -n "."
done

echo "Starting orderer"
ssh -n -f orderer "bash -c '. ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ; make orderer && make peer && nohup ./build/bin/orderer &> orderer.out & '"
echo "Starting peers"
for p in $peers ; do
        ssh -n -f $p "bash -c '. ~/.profile; cd /opt/gopath/src/github.com/hyperledger/fabric ; make peer && nohup ./build/bin/peer node start --peer-defaultchain=false &> $p.out & '"
done

sleep 20
echo "Creating channel"
CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp CORE_PEER_LOCALMSPID=PeerOrg ./peer channel create $ORDERER_TLS -f YACOV.tx  -c YACOV -o ${ordererIP}:7050
echo "Joining peers to channel"
for p in $peers ; do
CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$p:7051 ./peer channel join --tls true -b YACOV.block
done


echo "Installing chaincode..."
for p in $peers ; do
        CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=$p:7051 ./peer chaincode install -p github.com/hyperledger/fabric/examples/chaincode/go/metrics/ -n metrics -v 1.0
done


echo "Instantiating chaincode..."
CORE_PEER_TLS_ROOTCERT_FILE=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/peers/peer0.hrl.ibm.il/tls/ca.crt CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_MSPCONFIGPATH=`pwd`/crypto-config/peerOrganizations/hrl.ibm.il/users/Admin@hrl.ibm.il/msp/ CORE_PEER_ADDRESS=peer0:7051 ./peer chaincode instantiate -n metrics -v 1.0 -C YACOV -c '{"Args": ["init"]}' -o ${ordererIP}:7050 --tls true --cafile `pwd`/crypto-config/ordererOrganizations/hrl.ibm.il/orderers/${ordererIP}.hrl.ibm.il/tls/ca.crt

sleep 10

echo "Invoking chaincode..."
for i in `seq 50`; do
        invoke peer0

done

exit 0

echo "Listening to events..."
/opt/gopath/src/github.com/hyperledger/fabric/gossip/metrics/listener/listener both > TEST.${PROPAGATEPEERNUM}.log

