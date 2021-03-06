#!/bin/sh

. /lib/functions/weimarnetz/ipsystem.sh

uci_add_list() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} add_list "$PACKAGE.$CONFIG.$OPTION=$VALUE"
}

log_dhcp() {
	logger -s -t apply_profile_dhcp $@
}

setup_dhcp() {
	local cfg_dhcp="$1"
	local ipaddr="$2"
	local ipv6="$3"

	if uci_get dhcp $cfg_dhcp >/dev/null ; then
		uci_remove dhcp $cfg_dhcp
	fi
	uci_add dhcp dhcp $cfg_dhcp
	uci_set dhcp $cfg_dhcp interface "$cfg_dhcp"
	uci_set dhcp $cfg_dhcp ignore "0"
	if [ -n "$ipaddr" ] ; then
		eval "$(ipcalc.sh $ipaddr)"
		OCTET_4="${NETWORK##*.}"
		OCTET_1_3="${NETWORK%.*}"
		OCTET_4="$((OCTET_4 + 2))"
		#start_ipaddr="$OCTET_4"
		start_ipaddr=1
		uci_set dhcp $cfg_dhcp start "$start_ipaddr"
		limit=$(($((2**$((32-$PREFIX))))-2))
		uci_set dhcp $cfg_dhcp limit "$limit"
	fi
	uci_set dhcp $cfg_dhcp leasetime "15m"
	uci_add_list dhcp $cfg_dhcp dhcp_option "119,olsr,lan,p2p"
	uci_add_list dhcp $cfg_dhcp domain "olsr"
	uci_add_list dhcp $cfg_dhcp domain "lan"
	uci_add_list dhcp $cfg_dhcp domain "p2p"
	[ "$ipv6" -eq "1" ] && {
		uci_set dhcp $cfg_dhcp dhcpv6 "server"
		uci_set dhcp $cfg_dhcp ra "server"
		uci_set dhcp $cfg_dhcp ra_preference "low"
		uci_set dhcp $cfg_dhcp ra_default "1"
	}
}

setup_roaming_dhcp() {
	local cfg_dhcp="$1"
	local nodenumber="$2"
	local ipv6="$3"

	json_load "$nodedata"
	json_get_var offset roaming_dhcp_offset

	if uci_get dhcp $cfg_dhcp >/dev/null ; then				  
				uci_remove dhcp $cfg_dhcp						  
	fi														  
	uci_add dhcp dhcp $cfg_dhcp								  
	uci_set dhcp $cfg_dhcp interface "$cfg_dhcp"			  
	uci_set dhcp $cfg_dhcp ignore "0"						  
	uci_set dhcp $cfg_dhcp start "$offset"		
	uci_set dhcp $cfg_dhcp limit "254"			   
	uci_set dhcp $cfg_dhcp leasetime "12h"					  
	uci_add_list dhcp $cfg_dhcp dhcp_option "119,olsr,lan,p2p"
	uci_add_list dhcp $cfg_dhcp domain "olsr"				  
	uci_add_list dhcp $cfg_dhcp domain "lan"				  
	uci_add_list dhcp $cfg_dhcp domain "p2p"				  
	if [ "$ipv6" -eq "1" ]; then
		uci_set dhcp $cfg_dhcp dhcpv6 "server"					  
		uci_set dhcp $cfg_dhcp ra "server"				
		uci_set dhcp $cfg_dhcp ra_preference "low"		
		uci_set dhcp $cfg_dhcp ra_default "1"
	fi	
}

setup_ether() {
	local cfg="$1"
	local nodenumber="$2"

	config_get enabled $cfg enabled "0"
	[ "$enabled" == "0" ] && return
	json_init
	json_load "$nodedata"
	json_get_var ipaddr "$cfg"
	json_cleanup
	config_get ipv6 settings ipv6 "0"
	cfg_dhcp=$cfg""
	uci_remove dhcp $cfg_dhcp 2>/dev/null
	setup_dhcp $cfg_dhcp "$ipaddr" "$ipv6"
}

setup_wifi() {
	local cfg="$1"
	local nodenumber="$2"

	config_get enabled $cfg enabled "0"
	[ "$enabled" -eq "0" ] && return
	config_get roaming settings roaming "0"
	config_get ipv6 settings ipv6 "0"
	if [ "$roaming" -eq "1" ]; then 
		setup_roaming_dhcp "$br_name" "$nodenumber"
	else 
		local nodedata=$(node2nets_json $nodenumber)
		json_init
		json_load "$nodedata"
		json_get_var dhcp_ip wifi
		cfg_dhcp="$br_name"
		uci_remove dhcp $cfg_dhcp 2>/dev/null
		if [ "$dhcp_ip" != "0" ] ; then
			log_dhcp "Setup $cfg with $dhcp_ip"
			setup_dhcp $cfg_dhcp "$dhcp_ip" "$ipv6"
		fi
		json_cleanup
	fi
}

setup_dhcpbase() {
	local cfg="$1"
	uci_set dhcp $cfg local "/olsr/"
	uci_set dhcp $cfg domain "olsr"
	uci_remove dhcp $cfg server
	uci_add_list dhcp $cfg server "8.8.8.8"
	uci_add_list dhcp $cfg server "8.8.4.4"
	config_get meshnode $cfg olsr_mesh "0"
	if [ "$olsr_mesh" -eq "1" ]; then
		uci_remove dhcp $cfg addnhosts
		uci_add_list dhcp $cfg addnhosts "/tmp/hosts/olsr.ipv4"
	fi
}

setup_odhcpbase() {
	local cfg="$1"
	#uci_set dhcp $cfg maindhcp "1"
	uci_set dhcp $cfg maindhcp "0"
}

br_name="vap"
#lan_iface="lan"
wan_iface="wan"

#Load dhcp config
config_load dhcp
#Setup dnsmasq
config_foreach setup_dhcpbase dnsmasq

#Setup odhcpd
config_foreach setup_odhcpbase odhcpd

#Setup ether and wifi
config_load meshnode
config_get nodenumber settings nodenumber
nodedata=$(node2nets_json $nodenumber)
config_foreach setup_ether ether "$nodenumber" 
config_foreach setup_wifi wifi "$nodenumber" 

#Setup DHCP Batman Bridge
#config_get br ffwizard br "0"
#if [ "$br" == "1" ] ; then
#	config_get dhcp_ip ffwizard dhcp_ip
#	log_dhcp "Setup iface $br_name with ip $dhcp_ip"
#	setup_dhcp $br_name $dhcp_ip
#else
#	if uci_get dhcp $br_name >/dev/null ; then
#		log_dhcp "Setup $br_name remove"
#		uci_remove dhcp $br_name 2>/dev/null
#	fi
#fi


#Enable dhcp on LAN
#if [ -n "$lan_iface" ] ; then
#	log_dhcp "Setup iface $lan_iface to default"
#	uci_set dhcp $cfg ignore "0"
#	uci_set dhcp $lan_iface start "1"
#	uci_set dhcp $lan_iface limit "13"
#	uci_set dhcp $lan_iface leasetime "12h"
#	uci_add_list dhcp $cfg_dhcp dhcp_option "119,olsr,lan,p2p"
#	uci_add_list dhcp $cfg_dhcp domain "olsr"
#	uci_add_list dhcp $cfg_dhcp domain "lan"
#	uci_add_list dhcp $cfg_dhcp domain "p2p"
#	uci_set dhcp $lan_iface dhcpv6 "server"
#	uci_set dhcp $lan_iface ra "server"
#fi

#Disable dhcp on WAN
if [ -n "$wan_iface" ] ; then
	log_dhcp "Setup iface $wan_iface to default"
	uci_set dhcp $wan_iface ignore "1"
	uci_set dhcp $wan_iface dhcpv6 "disabled"
	uci_set dhcp $wan_iface ra "disabled"
fi

uci_commit dhcp
# vim: set filetype=sh ai noet ts=4 sw=4 sts=4 :
