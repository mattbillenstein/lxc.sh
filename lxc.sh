#!/bin/bash

set -eo pipefail

# to use this, we setup a network bridge
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
# ?       24.04

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
#  sudo lxc-create -t download -n name -- --dist ubuntu --release DISTRO-SHORT-CODENAME --arch amd64
  sudo lxc-create -t download -n $NAME -- --dist $DIST --release $REL --arch $MARCH

  VMDIR="$LXCDIR/$NAME"
  ROOTFS="$VMDIR/rootfs"

  if [ "$DIST" == "ubuntu" ]; then
    # prefer ipv4
    echo 'precedence ::ffff:0:0/96  100' | sudo tee -a $ROOTFS/etc/gai.conf

    # bah, systemd-resolved doesn't handle local dns
    sudo rm $ROOTFS/etc/resolv.conf
    sudo cp /etc/resolv.conf $ROOTFS/etc/
  fi

  sudo lxc-start -n $NAME
  sudo lxc-attach -n $NAME <<EOF
while ! ping -q -c 1 -W 1 vazor.com; do
  sleep 1
done
if [ "\$(which apt)" != "" ]; then
  adduser --disabled-password --gecos "" mattb
  apt -y update
  apt -y install openssh-server git rsync tmux vim
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

  adduser -D -g "" -s /bin/bash mattb
  passwd -u mattb
  echo 'source ~/.bashrc' > /home/mattb/.bash_profile

  mkdir /dev/shm
  echo 'tmpfs /dev/shm tmpfs defaults,noexec,nodev,nosuid,size=128M 0 0' >> /etc/fstab
  mount /dev/shm
fi
echo "mattb ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-mattb
EOF

  # install my dotfiles, this is kinda barf
  sudo mkdir -p $ROOTFS/home/mattb/src/mattb
  sudo cp -a $HOME/src/mattb/dotfiles $ROOTFS/home/mattb/src/mattb/
  sudo chmod 755 $ROOTFS/home/mattb/src/mattb/dotfiles
  sudo chown -R $(sudo grep mattb $ROOTFS/etc/passwd | awk -F : '{printf "%s:%s\n", $3, $4}') $ROOTFS/home/mattb
  sudo lxc-attach -n $NAME -- sudo -u mattb bash -c 'cd ~/src/mattb/dotfiles; ./install.sh;ip addr show dev eth0 | grep "inet "'
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
else
  echo "$ ./lxc.sh find"
  echo "$ ./lxc.sh list"
  echo "$ ./lxc.sh create <name> [ubuntu jammy]"
  echo "$ ./lxc.sh destroy <name>"
  echo "$ ./lxc.sh start <name>"
  echo "$ ./lxc.sh stop <name>"
  echo "$ ./lxc.sh shell <name>"
fi
