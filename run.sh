cd /home/yacovm/smartBFT
rm -rf ledger
FABRIC_CFG_PATH=`pwd` ./orderer &> out.log &
