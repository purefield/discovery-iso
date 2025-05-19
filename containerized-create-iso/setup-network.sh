__ "Setup Networking" 2
__ "Usage: ./setup-network.sh primary-nic ip-address/netmask gateway vlan lacp-peer" 5
foundNic1=$(nmcli -t device | grep ethernet | cut -d\: -f1 | head -n 1)
foundNic2=$(nmcli -t device | grep ethernet | cut -d\: -f1 | head -n 2 | tail -n 1)
_? "What is your primary interface? *" nic "$foundNic1" $1
_? "What is your primary IP Address cidr? *" address "" $2
gatewayGuess=$(echo $address | cut -d'/' -f1 | sed 's/\.[0-9]*$/.1/')
_? "What is your primary gateway? *" gateway "$gatewayGuess" $3
_? "What is your vlan ID? (empty for no vlan)" vlan "" $4
_? "What is your second interface for lacp? (empty for no peer)" peer "$foundNic2" $5

nextHop=$nic
if [ "empty$peer" != "empty" ]; then
__ "Setup Bond" 3
bondName=bond0
_: nmcli con add type bond ifname $bondName con-name $bondName \
   mode 802.3ad miimon 100 downdelay 0 updelay 0 connection.autoconnect yes \
   ipv4.method disabled ipv6.method ignore
_: nmcli con add type bond-slave ifname $nic  con-name $nic  master $bondName
_: nmcli con add type bond-slave ifname $peer con-name $peer master $bondName
_: nmcli con up $bondName
_: nmcli con show
# _: ip link add $bondName type bond
# _: ip link set $bondName type bond miimon 100 mode 802.3ad
# _: ip link set $nic down
# _: ip link set $nic master $bondName
# _: ip link set $peer down
# _: ip link set $peer master $bondName
# _: ip link set $bondName up
nextHop=$bondName
fi
if [ "empty$vlan" != "empty" ]; then
__ "Setup Vlan" 3
vlanLinkName=$nextHop.$vlan
_: nmcli con add type vlan ifname $vlanLinkName \
   con-name $vlanLinkName id $vlan dev $nextHop \
   connection.autoconnect yes 
_: nmcli con up $vlanLinkName
# _: ip link set $nextHop down
# _: ip link add link $nextHop name $vlanLinkName type vlan id $vlan
# _: ip link set $nextHop up
# _: ip link set $vlanLinkName up
nextHop=$vlanLinkName
fi
if [ "empty$address" != "empty" ]; then
__ "Setup IP Address on $nextHop" 3
_: nmcli con mod $nextHop ip4 $address gw4 $gateway
# _: ip addr add $address dev $nextHop
# _: ip link set $nextHop up
# _: ip route add default via $gateway dev $nextHop
fi
nmcli
