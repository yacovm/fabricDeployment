# Hyperledger Fabric deployment script

What does it do?
- Deploys on remote linux servers a network that consists of:
    - An Ordering service (solo)
    - Peers, as many as needed, in the same organization
- "detects" if Fabric is already installed, and if not - installs it
- Sets up everything to run with TLS
- Creates a single channel, installs and instantiates example02 as a sanity test

### Introduction:
This tool was created to help quickly set up an environment of Hyperledger Fabric

### Disclaimer/Warning :
 The script would wipe everything in `/var/hyerledger/production` and delete some of the docker images, direct this script only to empty VMs / servers created solely for Fabric deployment.

### Prerequisites:

- Local git repo of Hyperledger Fabric in `$GOPATH/src/github.com/hyperledger/fabric`
- Empty physical servers/virtual machines to be used as a solo ordering service and peers
- Tested with Ubuntu 16.04.2 LTS, other distributions might also work
- git client installed on the servers
- Ability to do "sudo" without having to enter a password on the servers
- Ability to ssh without having to enter a password from the machine that runs this script
- Ability of peers to resolve each other's DNS names and the orderer's DNS name

#### How to use
- Edit `config.sh` with the hostnames of the servers that are to be used as an orderer and peers
- Run the `deploy.sh` script



