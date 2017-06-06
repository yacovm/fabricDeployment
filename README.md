# Hyperledger Fabric deployment script


### Introduction:
This tool was created to help quickly set up an environment of Hyperledger Fabric

### Prerequisites:

- Empty physical servers/virtual machines to be used as a solo ordering service and peers
- Tested with Ubuntu 16.04.2 LTS, other distributions might also work
- git client installed on the servers
- Ability to do "sudo" without having to enter a password on the servers
- Ability to ssh without having to enter a password from the machine that runs this script
- Ability of peers to resolve each other's DNS names and the orderer's DNS name

#### How to use
- Edit `config.sh` with the hostnames of the servers that are to be used as an orderer and peers
- Run the `deploy.sh` script



