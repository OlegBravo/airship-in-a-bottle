#!/bin/bash -e

mkdir -p /root/deploy && cd /root/deploy
git clone https://github.com/progmaticlab/airship-in-a-bottle
git clone https://git.openstack.org/openstack/airship-pegleg.git
git clone https://git.openstack.org/openstack/airship-shipyard.git
sed -i 's/-it/-i/g' airship-pegleg/tools/pegleg.sh

cd ./airship-in-a-bottle/manifests/dev_single_node

apt-get install -y python-setuptools
easy_install pip
pip install ipaddress
export TARGET_SITE="demo"
export NODE_NET_IFACE=$(ip route get 1 | grep -o "dev.*" | awk '{print $2}')
export NODE_NET_IFACE_GATEWAY_IP="$(ip route get 1 | awk '/1.0.0.0/{print $3}')"
if_cidr=`ip addr | grep -A 3 $NODE_NET_IFACE | awk '/inet /{print $2}'`
export NODE_SUBNETS=`python -c "import ipaddress; print str(ipaddress.ip_network(u'$if_cidr', strict=False))"`
export DNS_SERVER="$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')"

export HOSTIP=`ip addr show ${NODE_NET_IFACE} | awk '/inet /{print $2}' | cut -d '/' -f 1`
# x/32 will work for CEPH in a single node deploy.
export HOSTCIDR=$HOSTIP/32
export SHORT_HOSTNAME=`getent hosts $HOSTIP | head -1 | awk '{print $2}' | cut -d '.' -f 1`
hostname $SHORT_HOSTNAME
echo $SHORT_HOSTNAME > /etc/hostname

# Updates the /etc/hosts file
HOSTS="${HOSTIP} ${SHORT_HOSTNAME}"
HOSTS_REGEX="${HOSTIP}.*${SHORT_HOSTNAME}"
if grep -q "$HOSTS_REGEX" "/etc/hosts"; then
  echo "INFO: Not updating /etc/hosts, entry ${HOSTS} already exists."
else
  echo "INFO: Updating /etc/hosts with: ${HOSTS}"
  cat << EOF | tee -a /etc/hosts
$HOSTS
EOF
fi

COMMON_CONFIG_FILE="../../deployment_files/site/$TARGET_SITE/networks/common-addresses.yaml"
if grep -q "10.96.0.10" "/etc/resolv.conf"; then
  echo "INFO: Not changing DNS servers, /etc/resolv.conf already updated."
else
  sed -i "s/8.8.4.4/$DNS_SERVER/" $COMMON_CONFIG_FILE
fi
../common/deploy-airship.sh demo

cid=$(docker ps | awk '/k8s_contrail-webui_contrail-webui/{print $1}')
docker exec -it $cid bash -c "printf \"\nconfig.staticAuth = [];\nconfig.staticAuth[0] = {};\nconfig.staticAuth[0].username = 'admin';\nconfig.staticAuth[0].password = 'contrail123';\nconfig.staticAuth[0].roles = ['cloudAdmin'];\n\" >> /etc/contrail/config.global.js"
docker exec -it $cid tail -6 /etc/contrail/config.global.js
