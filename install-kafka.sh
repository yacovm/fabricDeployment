#!/bin/bash

sudo apt-get update
echo "Installing Java"
sudo apt-get -y install unzip
sudo apt-get install -y openjdk-8-jdk maven
wget https://services.gradle.org/distributions/gradle-2.12-bin.zip -P /tmp --quiet
sudo unzip -q /tmp/gradle-2.12-bin.zip -d /opt && rm /tmp/gradle-2.12-bin.zip
sudo ln -s /opt/gradle-2.12/bin/gradle /usr/bin
echo "Installing Kafka"
wget mirror.switch.ch/mirror/apache/dist/kafka/0.9.0.0/kafka_2.11-0.9.0.0.tgz -P /tmp --quiet
sudo tar xpzf /tmp/kafka_2.11-0.9.0.0.tgz -C /opt && rm /tmp/kafka_2.11-0.9.0.0.tgz

sudo su - $(whoami) - << EOF
sudo chown -R $(whoami):$(whoami)  /opt/kafka_2.11-0.9.0.0/
EOF

