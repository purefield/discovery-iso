__ "Setup Networking" 2
__ "Usage: ./setup-network.sh primary-nic ip-address/netmask gateway vlan lacp-peer" 5
_? "What is your primary interface? *" nic eno1 $1
_? "What is your primary IP Address cidr? *" address "" $2
_? "What is your primary gateway? *" gateway "" $3
_? "What is your vlan ID? (empty for no vlan)" vlan "" $4
_? "What is your second interface for lacp? (empty for no peer)" peer "" $5

nextHop=$nic
if [ "empty$peer" != "empty" ]; then
__ "Setup Bond" 3
bondName=bond0
_: ip link add $bondName type bond
_: ip link set $bondName type bond miimon 100 mode 802.3ad
_: ip link set $nic down
_: ip link set $nic master $bondName
_: ip link set $peer down
_: ip link set $peer master $bondName
_: ip link set $bondName up
nextHop=$bondName
fi
if [ "empty$vlan" != "empty" ]; then
__ "Setup Vlan" 3
vlanLinkName=$nextHop.$vlan
_: ip link add link $nextHop name $vlanLinkName type vlan id $vlan
_: ip link set $vlanLinkName up
nextHop=$vlanLinkName
fi
if [ "empty$address" != "empty" ]; then
__ "Setup IP Address on $nextHop" 3
_: ip addr add $address dev $nextHop
_: ip route add default via $gateway dev $nextHop
