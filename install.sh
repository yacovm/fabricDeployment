#!/bin/bash

sudo apt-get update
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main'
sudo apt-get update
apt-cache policy docker-engine
sudo apt-get install -y docker-engine
sudo apt-get install -y libltdl3-dev
sudo apt-get install -y build-essential
sudo usermod -aG docker $(whoami)
sudo curl -o /usr/local/bin/docker-compose -L "https://github.com/docker/compose/releases/download/1.11.2/docker-compose-$(uname -s)-$(uname -m)"
sudo chmod +x /usr/local/bin/docker-compose
wget https://storage.googleapis.com/golang/go1.7.3.linux-amd64.tar.gz
tar xpzf go1.7.3.linux-amd64.tar.gz

cat << EOF >> ~/.profile
export PATH=$PATH:~/go/bin/
export GOPATH=/opt/gopath
export GOROOT=~/go
EOF


sudo su - $(whoami) - << EOF
sudo mkdir -p /var/hyperledger
sudo chown $(whoami):$(whoami) /var/hyperledger
sudo mkdir -p /opt/gopath/src/github.com/hyperledger/fabric
sudo chown -R $(whoami):$(whoami)  /opt/gopath/
git clone https://github.com/hyperledger/fabric /opt/gopath/src/github.com/hyperledger/fabric
cd /opt/gopath/src/github.com/hyperledger/fabric
make gotools
make peer orderer peer-docker orderer-docker
EOF

