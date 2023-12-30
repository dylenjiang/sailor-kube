#!/usr/bin/env bash
#
# Created by tyvekzhang
#
# NAME:  SailorKube
# VER:   0.0.1
# PLAT:  linux-64


set -eu

if ! echo "$0" | grep '\.sh$' > /dev/null; then
    printf 'Please run using "bash"/"dash"/"sh"/"zsh", but not "." or "source".\n' >&2
    return 1
fi

INSTALLER_NAME=sailor-kube
INSTALLER_VER=0.0.1
BRANCH=master
TARGET=${INSTALLER_NAME}-${BRANCH//\//-}
PREFIX="/usr/share/${INSTALLER_NAME}"

USAGE="
usage: $0 [options]

${INSTALLER_NAME} ${INSTALLER_VER} assistant

-c           clear all downloaded files
-h           print this help message and exit
-p           print all downloaded files path
"

if [ "$(uname -m)" != "x86_64" ]; then
    printf "WARNING:\\n"
    printf "    Your operating system appears not to be 64-bit, but you are trying to\\n"
    printf "    install a 64-bit version of %s.\\n" "${INSTALLER_NAME}"
    printf "    Are sure you want to continue the installation? [yes|no]\\n"
    printf "[no] >>> "
    read -r ans
    ans=$(echo "${ans}" | tr '[:lower:]' '[:upper:]')
    if [ "$ans" != "YES" ] && [ "$ans" != "Y" ]
    then
        printf "Aborting installation\\n"
        exit 2
    fi
fi
if [ "$(uname)" != "Linux" ]; then
    printf "WARNING:\\n"
    printf "    Your operating system does not appear to be Linux, \\n"
    printf "    but you are trying to install a Linux version of %s.\\n" "${INSTALLER_NAME}"
    printf "    Are sure you want to continue the installation? [yes|no]\\n"
    printf "[no] >>> "
    read -r ans
    ans=$(echo "${ans}" | tr '[:lower:]' '[:upper:]')
    if [ "$ans" != "YES" ] && [ "$ans" != "Y" ]
    then
        printf "Aborting installation\\n"
        exit 2
    fi
fi


function cleanup {
    if is_centos; then
        yum clean all
    elif is_ubuntu || is_debian; then
        apt-get clean
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi
}

function ensure_lsb_release {
    if type lsb_release >/dev/null 2>&1; then
        return
    fi

    if type apt-get >/dev/null 2>&1; then
        apt-get -y install lsb-release
    elif type yum >/dev/null 2>&1; then
        yum -y install redhat-lsb-core
    fi

    if type dnf >/dev/null 2>&1; then
        dnf -y install redhat-lsb-core
    fi
}

function _is_distro {
    DISTRO=$(lsb_release -si)
    [[ "$DISTRO" == "$1" ]]
}

function is_ubuntu {
    _is_distro "Ubuntu"
}

function is_debian {
    _is_distro "Debian"
}

function is_centos {
    _is_distro "CentOS"
}

function is_rocky {
    _is_distro "Rocky"
}

function error_msg_print {
     echo "$1" | sed -e 's/.*/\033[31&\033[0m/'
}

function info_msg_print {
     echo "$1" | sed -e 's/.*/\033[32&\033[0m/'
}

function preflight {
    if type python3 >/dev/null 2>&1; then
        return
    else
        msg="Python3 not found and python2 not support any more! Please ensure that the Python version is greater than or equal to 3.7."
        error_msg_print msg
        exit 1
    fi
}

function prepare_work_rocky {
  if [[ "$(systemctl is-enabled firewalld)" == "active" ]]; then
      systemctl disable firewalld
  fi
  if [[ "$(systemctl is-active firewalld)" == "enabled" ]]; then
      systemctl stop firewalld
  fi
  configure_rocky_souces
  dnf -y install epel-release
  dnf -y install git python3-pip unzip
}

function prepare_work_debian_ubuntu {
    if [[ "$(systemctl is-enabled ufw)" == "active" ]]; then
        systemctl disable ufw
    fi
    if [[ "$(systemctl is-active ufw)" == "enabled" ]]; then
        systemctl stop ufw
    fi

    if is_debian; then
        configure_debian_sources
    else
        configure_ubuntu_sources
    fi
    apt-get update
    apt install -y git python3-pip unzip
}

function configure_pip {
    mkdir -p ~/.pip
    cat > ~/.pip/pip.conf << EOF
[global]
trusted-host = mirrors.aliyun.com
index-url = http://mirrors.aliyun.com/pypi/simple/
EOF
}

function configure_centos_sources {
    if [ ! -f "/etc/yum.repos.d/CentOS-Base.repo.backup" ];then
         mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
    fi
    # CentOS 7
    curl http://mirrors.aliyun.com/repo/Centos-7.repo -o /etc/yum.repos.d/CentOS-Base.repo
}

function configure_rocky_souces {
    sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
    -i.bak \
    /etc/yum.repos.d/Rocky-*.repo
}

function configure_debian_sources {
    if [ ! -f "/etc/apt/sources.list.backup" ];then
         mv /etc/apt/sources.list /etc/apt/sources.list.backup
    fi

    UBUNTU_CODENAME=$(cat /etc/os-release |egrep "^VERSION_CODENAME=\"*(\w+)\"*" |awk -F= '{print $2}' |tr -d '\"')
    # debian 11.x+
    cat > /etc/apt/sources.list << EOF
deb https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME} main non-free contrib
deb-src https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME} main non-free contrib
deb https://mirrors.aliyun.com/debian-security/ ${UBUNTU_CODENAME}-security main
deb-src https://mirrors.aliyun.com/debian-security/ ${UBUNTU_CODENAME}-security main
deb https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME}-updates main non-free contrib
deb-src https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME}-updates main non-free contrib
deb https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME}-backports main non-free contrib
deb-src https://mirrors.aliyun.com/debian/ ${UBUNTU_CODENAME}-backports main non-free contrib
EOF
}

function configure_ubuntu_sources() {
    if [ ! -f "/etc/apt/sources.list.backup" ];then
        mv /etc/apt/sources.list /etc/apt/sources.list.backup
    fi

    UBUNTU_CODENAME=$(cat /etc/os-release |egrep "^VERSION_CODENAME=\"*(\w+)\"*" |awk -F= '{print $2}' |tr -d '\"')
    cat > /etc/apt/sources.list << EOF
deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
EOF
}

function install_ansible {
    if is_centos; then
        yum -y install ansible
    elif is_ubuntu || is_debian; then
        apt-get -y install ansible
    elif is_rocky; then
        dnf -y install ansible
    else
        echo "Unsupported Distro: $DISTRO" 1>&2
        exit 1
    fi
}

function prepare_works {
    configure_pip
    ensure_lsb_release
    if is_rocky; then
        prepare_work_rocky

    elif is_ubuntu || is_debian; then
        prepare_work_debian_ubuntu
    else
        msg="Unsupported Distro: $DISTRO"
        error_msg_print msg
        exit 1
    fi
    install_ansible
}

function install_sailor_kube {
    echo "downloaded sailor_kube success"
}

while getopts "bifhkp:sut" x; do
    case "$x" in
        h)
            printf "%s\\n" "$USAGE"
            exit 2
        ;;
        c)
            cleanup
            ;;
        p)
            prefix="PREFIX: ${PREFIX}"
            info_msg_print prefix
            ;;
        ?)
            printf "ERROR: did not recognize option '%s', please try -h\\n" "$x"
            exit 1
            ;;
    esac
done

printf "\\n"
printf "Welcome to %s %s\\n" "${INSTALLER_NAME}" "${INSTALLER_VER}"
printf "\\n"
printf "In order to continue the installation process, please review the license\\n"
printf "agreement.\\n"
printf "Please, press ENTER to continue\\n"
printf ">>> "
read -r dummy
pager="cat"
if command -v "more" > /dev/null 2>&1; then
  pager="more"
fi
"$pager" <<'EOF'
======================================
End User License Agreement - SailorKube
======================================
Apache License 2.0
For more details: https://www.apache.org/licenses/LICENSE-2.0

SCRIPTS WILL DO:
===================
1.Disable the firewall
2.Configure the download source
3.Download SailorKube source code
===================
EOF
printf "\\n"
printf "Do you accept the license terms? [yes|no]\\n"
printf ">>> "
read -r ans
ans=$(echo "${ans}" | tr '[:lower:]' '[:upper:]')
while [ "$ans" != "YES" ] && [ "$ans" != "NO" ]
do
    printf "Please answer 'yes' or 'no':'\\n"
    printf ">>> "
    read -r ans
    ans=$(echo "${ans}" | tr '[:lower:]' '[:upper:]')
done
if [ "$ans" != "YES" ]; then
  printf "The license agreement wasn't approved, aborting installation.\\n"
  exit 2
fi

preflight
prepare_works
install_sailor_kube
