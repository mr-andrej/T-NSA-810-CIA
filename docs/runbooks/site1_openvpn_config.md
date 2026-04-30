Below is the configuration on site 1 in pfSense/VPN/OpenVPN/client, edit page

# OpenVPN Clients

|Interface|Protocol|Server|Mode/Crypto|Description|
|WAN|UDP4(TUN)|5.196.45.7:1195|Mode: Peer to Peer (SSL/TLS) Data Ciphers: AES-256-GCM, AES-128-GCM, CHACHA20-POLY1305, AES-256-CBC Digest: SHA256|S2S Site1-Site2|

# OpenVPN Clients/Edit page

## General Information

Description: S2S Site1-Site2
Disabled: not checked
Unique VPN ID: Client 1(ovpnc1)

## Mode Configuration

Server mode: Peer to Peer (SSL/TLS)
Device mode: tun-Layer 3 Tunnel Mode

## Endpoint Configuration
Protocol: UDP on IPv4 only
Interface: WAN
Local port:
Server host or address: 5.196.45.7
Server port: 1195
Proxy host or address:
Proxy host:
Proxy Authentificaiton: none

## User Authentification Settings

## Cryptographic Settings

Use a TLS Key: checked
TLS Key: Some 2048 bit OpenVPN static key pasted here
TLS Key Usage Mode: TLS Authentication
TLS keydir direction: Use default direction
Peer Certificate Authority: site2-vpn-ca
Client Certificate: s2s-site1-client(CA: site2-vpn-ca, In User)

## Tunnel Settings

IPv4 Tunnel Network: 172.16.0.0/30
IPv4 Remote network(s): 192.168.10.0/24, 192.168.20.0/24
