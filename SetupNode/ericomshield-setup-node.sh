#!/bin/bash
############################################
#####   Ericom Shield Installer        #####
#######################################BH###

###------------------Remove it --------------------
## docker swarm init --advertise-addr 10.0.0.1
###------------------------------------------------

MACHINE_USER=
MACHINE_IPS=
MACHINES=
SWARM_TOKEN=
LEADER_IP=
CERTIFICATE_FILE=./shield_crt
DOCKER_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/EricomSoftwareLtd/Shield/jenkins/SetupNode/install-docker.sh"
ALLOW_BROWSERS=
ALLOW_SHIELD_CORE=
ALLOW_MANAGEMENT=
NAME_PREFIX="WORKER"

command_exists() {
	command -v "$@" > /dev/null 2>&1
}


print_usage() {
    echo "Usage: ericomshield-setup-node.sh
        -u|--user ssl usename
        [-t|--token] Token to join to swarm deafult will be provide from current cluster
        -l|--leader leader ip
        [-m|--mode] Mode to join should be worker|manager default worker
        -ips|--machines-ip IPs of machines to append separated by ','"
}


create_generic_machines() {
    counter=0
    for ip in $MACHINE_IPS; do
        MACHINE_NAME="$NAME_PREFIX$counter"
        docker-machine create \
            -d "generic" --generic-ip-address $ip \
            --generic-ssh-key $CERTIFICATE_FILE \
            --generic-ssh-user $MACHINE_USER \
            --engine-install-url $DOCKER_INSTALL_SCRIPT_URL  $MACHINE_NAME
        counter=$(($counter + 1))
        if [ -z "$MACHINES" ]; then
           MACHINES=$MACHINE_NAME
        else
           MACHINES="$MACHINES $MACHINE_NAME"
        fi
    done
}

apply-node-labels() {
    NODE_NAME="$1"
    LABELS=
    if [ -n "$ALLOW_BROWSERS" ]; then
        LABELS="--label-add browser=yes"
    fi

    if [ -n "$ALLOW_SHIELD_CORE" ]; then
        LABELS="$LABELS --label-add shield_core=yes"
    fi

    if [ -n "$ALLOW_MANAGEMENT" ]; then
        LABELS="$LABELS --label-add management=yes"
    fi

    docker node update $LABELS $NODE_NAME
}

make_tmpfs_mount() {
    docker-machine ssh $name "sudo mkdir -p /media/containershm"
    docker-machine ssh $name "sudo mount -t tmpfs -o size=2G tmpfs /media/containershm"
    docker-machine ssh $name <<- EOF
        sudo su
        echo 'tmpfs   /media/containershm     tmpfs   rw,size=2G      0       0' >> /etc/fstab
EOF
}

join_machines_to_swarm() {
    for name in $MACHINES; do
        eval $(docker-machine env $name)
        docker swarm join --token $SWARM_TOKEN $LEADER_IP
    done

    eval $(docker-machine env -u)

    #should change to FS table mount
    for name in $MACHINES; do
        ssh -i $CERTIFICATE_FILE -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $MACHINE_USER@$(docker-machine ip $name) [ ! -d /media/containershm ] &&  make_tmpfs_mount $name;
    done

    for name in $MACHINES; do
        apply-node-labels $name
    done
}

fetch_join_token() {

    TOKEN_MODE=$MODE

    if [ -z "$TOKEN_MODE" ]; then
        TOKEN_MODE=worker
    fi

    echo $(docker swarm join-token -q $TOKEN_MODE)

}

print-final-report() {
    echo "########################################################### Final Report ##################################################"
    for name in $MACHINES; do
        machine=$(docker-machine ls | grep $name | awk '{print $5}')
        swarm=$(docker node ls | grep $name | awk '{print $1}')
        echo "Machine $name added to cluster at $machine and to swarm $swarm"
    done
}


test-leader-port() {
    if [[ "$1" =~ .*:.*  ]]; then
        LEADER_IP="$1"
    else
        LEADER_IP="$1:2377"
    fi
}

make-leader-ip() {
    if [ -z "$1" ]; then
        tmp=$( docker swarm join-token worker | grep docker | awk '{ print $6}' )
        test-leader-port "$tmp"
    else
        test-leader-port "$1"
    fi
}


make_machines_ready() {

    for ip in $MACHINE_IPS; do

    done
}

if ! command_exists docker-machine; then
    echo "###################################### Install docker machine ################################"
    sudo curl -L https://github.com/docker/machine/releases/download/v0.12.2/docker-machine-`uname -s`-`uname -m` > /usr/local/bin/docker-machine && \
    sudo chmod +x /usr/local/bin/docker-machine
fi


while [ $# -ne 0 ]; do
    arg="$1"
    case "$arg" in
    -u|--user)
        MACHINE_USER="$2"
        shift
        ;;
    -t|--token)
        SWARM_TOKEN="$2"
        shift
        ;;
    -l|--leader)
        make-leader-ip "$2"
        shift
        ;;
    -m|--mode)
        MODE="$2"
        shift
        ;;
    -ips|--machines-ip)
          IFS=',' read -r -a array <<< "$2"
          MACHINE_IPS="${array[@]}"
          shift
        ;;
    -n|--name)
        NAME_PREFIX=$( echo "$2" | sed -r s/[^a-zA-Z0-9]+/r/g)
        shift
        ;;
    -c|--certificate)
        CERTIFICATE_FILE="$2"
        shift
        ;;
    -b|--browsers)
        ALLOW_BROWSERS=yes
        ;;
    -sc|--shield-core)
        ALLOW_SHIELD_CORE=yes
        ;;
    -mng|--management)
        ALLOW_MANAGEMENT=yes
        ;;
    esac
    shift
done

if [ -z "$MACHINE_USER" ]; then
    echo "ssh user is empty"
    print_usage
    exit 1
fi

if [ -z "$SWARM_TOKEN" ]; then
    SWARM_TOKEN=$(fetch_join_token)
fi

if [ -z "$LEADER_IP" ]; then
    make-leader-ip
fi

if [ -z "$MACHINE_IPS" ]; then
    echo "IPs of nodes required at least one"
    print_usage
    exit 1
fi

echo "Machine IPS: $MACHINE_IPS"

set -e
make_machines_ready
create_generic_machines
set +e
join_machines_to_swarm

print-final-report


