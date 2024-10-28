#!/bin/bash

set -eo pipefail

# sudo apt-get install lxc-utils

# I like to ssh to these containers, so I bridge networking over ethernet which
# doesn't work over wifi - ymmv.

# /etc/netplan/50-cloud-init.yaml

#network:
#    version: 2
#    ethernets:
#        enp0s31f6:
#            dhcp4: false
#    bridges:
#        br0:
#            interfaces: [enp0s31f6]
#            dhcp4: true
#
# then sudo netplan generate && sudo netplan --debug apply
#
# edit /etc/default/lxc-net and set:
# USE_LXC_BRIDGE="false"
#
# edit /etc/lxc/default.conf and set:
# lxc.net.0.link = br0
#
# and sudo systemctl restart lxc lxc-net

# Sigh, Ubuntu
# xenial  16.04
# bionic  18.04
# focal   20.04
# impish  21.10
# jammy   22.04
# kinetic 22.10
# lunar   23.04
# mantic  23.10
# noble   24.04

USER="$(id -un)"
LXCDIR="/var/lib/lxc"

MARCH="$(uname -m)"
if [ "$MARCH" == "x86_64" ]; then
  MARCH="amd64"
fi

if [ "$1" == "find" ]; then
  shift
  /usr/share/lxc/templates/lxc-download -l | grep $MARCH
elif [ "$1" == "list" ]; then
  shift
  sudo lxc-ls --fancy
elif [ "$1" == "create" ]; then
  shift
  NAME=$1
  DIST=$2
  if [ "$DIST" == "" ]; then
    DIST="ubuntu"
  fi
  REL=$3
  if [ "$REL" == "" ]; then
    REL="jammy"
  fi
  sudo lxc-create -t download -n $NAME -- --dist $DIST --release $REL --arch $MARCH

  VMDIR="$LXCDIR/$NAME"
  ROOTFS="$VMDIR/rootfs"

  if [ "$DIST" == "ubuntu" ]; then
    if [ "$REL" == "noble" ]; then
      # fix apparmor problems with noble...  2024-10-20
      printf "\nlxc.apparmor.profile = unconfined\n" | sudo tee -a /var/lib/lxc/$NAME/config
    fi

    # prefer ipv4
    echo 'precedence ::ffff:0:0/96  100' | sudo tee -a $ROOTFS/etc/gai.conf

    # bah, systemd-resolved doesn't handle local dns, but only do this on
    # bridged networks...
    if grep -q 'lxc.net.0.link = br0' /etc/lxc/default.conf; then
      sudo rm $ROOTFS/etc/resolv.conf
      sudo cp /etc/resolv.conf $ROOTFS/etc/
    fi
  fi

  sudo lxc-start -n $NAME
  sudo lxc-attach -n $NAME <<EOF
while ! ping -q -c 1 -W 1 google.com; do
  sleep 1
done
if [ "\$(which apt-get)" != "" ]; then
  adduser --disabled-password --gecos "" $USER
  apt-get -y update
  apt-get -y install curl openssh-server git rsync tmux vim
elif [ "\$(which apk)" != "" ]; then
  apk update
  apk add bash
  apk add git
  apk add openssh-client
  apk add openssh-server
  apk add rsync
  apk add sudo
  apk add tmux
  apk add vim

  rc-update add sshd default
  rc-service sshd start

  adduser -D -g "" -s /bin/bash $USER
  passwd -u $USER
  echo 'source ~/.bashrc' > /home/$USER/.bash_profile

  mkdir /dev/shm
  echo 'tmpfs /dev/shm tmpfs defaults,noexec,nodev,nosuid,size=128M 0 0' >> /etc/fstab
  mount /dev/shm
else
  echo 'Unknown platform'
fi
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$USER
EOF

  # install my dotfiles, this is kinda barf
  sudo mkdir -p $ROOTFS/home/$USER/src/$USER
  sudo cp -a $HOME/src/$USER/dotfiles $ROOTFS/home/$USER/src/$USER/
  sudo chmod 755 $ROOTFS/home/$USER/src/$USER/dotfiles
  sudo chown -R $(sudo grep $USER $ROOTFS/etc/passwd | awk -F : '{printf "%s:%s\n", $3, $4}') $ROOTFS/home/$USER
  sudo lxc-attach -n $NAME -- sudo -u $USER bash -c 'cd ~/src/$USER/dotfiles; ./install.sh;ip addr show dev eth0 | grep "inet "'
elif [ "$1" == "destroy" ]; then
  shift
  sudo lxc-stop -n $1 &>/dev/null || true
  sudo lxc-destroy -n $1
elif [ "$1" == "start" ]; then
  shift
  sudo lxc-start -n $1
elif [ "$1" == "stop" ]; then
  shift
  sudo lxc-stop -n $1
elif [ "$1" == "shell" ]; then
  shift
  sudo lxc-attach -n $1 -- /bin/bash
elif [ "$1" == "cpuset" ]; then
  shift
  sudo lxc-cgroup -n $1 cpuset.cpus $2   # 0-3 for 4 cpus
else
  echo "$ ./lxc.sh find"
  echo "$ ./lxc.sh list"
  echo "$ ./lxc.sh create <name> [ubuntu jammy]"
  echo "$ ./lxc.sh destroy <name>"
  echo "$ ./lxc.sh start <name>"
  echo "$ ./lxc.sh stop <name>"
  echo "$ ./lxc.sh shell <name>"
  echo "$ ./lxc.sh cpuset <name> <cpus>"
  echo
  sudo lxc-ls --fancy
fi
