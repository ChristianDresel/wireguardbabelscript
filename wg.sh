#!/bin/bash


if [ $# != 2 ]; then
	echo "Use ./wg.sh remotepublickey ifname"
	exit
fi 


#Diese Daten bitte anpassen:
ipv6ll="fe80::22:33:44:11"
ipv6ula="fd43:5602:29bd:ffff::19"
ipv4="10.83.252.2"
portbase=31337

port=$portbase
while grep $port /etc/wireguard/*.conf &>/dev/null ; do ((port+=1)); done


echo "Generiere Keys:"
privkey=$(wg genkey); pubkey=$(echo $privkey | wg pubkey)
echo "Privater Key:" 
echo "$privkey"
echo "Public Key:" 
echo "$pubkey"

echo "Lege wireguard config an:"
echo "[Interface] 
PrivateKey = "$privkey"
ListenPort = $port

[Peer]
PublicKey = $1
AllowedIPs = 0.0.0.0/0, ::/0
" | tee /etc/wireguard/$2.conf


echo "Lege Interface an:"
echo "
auto $2
iface $2 inet static
       address $ipv4
        # initialize wireguard
       pre-up ip link add $2 type wireguard
       pre-up wg setconf $2 /etc/wireguard/$2.conf
        # babeld
       pre-up ip link set dev $2 multicast on
       pre-up ip -6 addr add $ipv6ll dev $2
       pre-up ip -6 addr add $ipv6ula dev $2

        # freifunk rule
       pre-up ip rule add from all iif $2 lookup fff
       pre-up ip -6 rule add from all iif $2 lookup fff
       post-down ip rule del iif $2 table fff
       post-down ip -6 rule del from all iif $2 lookup fff

        # Clamping
       post-up iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o $2 -j TCPMSS --clamp-mss-to-pmtu
       post-down iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o $2 -j TCPMSS --clamp-mss-to-pmtu	
       # kill Interface
       post-down ip link del $2
" | tee /etc/network/interfaces.d/$2

echo "Starte Interface:"
ifup $2 

echo "Schreibe Babel config:"
sed -i 's/INTERFACES="/INTERFACES="'$2' /' /etc/default/babeld

#ACHTUNG! Im sed u.U. die Zeilennummer anpassen!
sed -i '4i interface '$2' type tunnel max-rtt-penalty 128' /etc/babeld.conf 

echo "Starte babeld neu"
/etc/init.d/babeld restart

echo "Publickey, IP und Port weitergeben an Peeringpartner:"
echo "$pubkey 81.95.4.186 $port" 
