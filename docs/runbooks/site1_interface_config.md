# WAN

## General Configuration
Enable: checked
Description: WAN
IPv4 Configuration Type: Static IPv4

## Static IPv4 Configuration

IPv4 Address: 5.196.50.51/24
IPv4 Upstream gateway: WANGW - 5.196.50.254

# LAN

## General Configuration
Enable: checked
Description: LAN
IPv4 Configuration Type: Static IPv4

## Static IPv4 Configuration

IPv4 Address: 10.0.0.254/24
IPv4 Upstream gateway: None

# OPT1

## General Configuration
Enable: checked
Description: OPT1
IPv4 Configuration Type: Static IPv4

## Static IPv4 Configuration

IPv4 Address: 10.0.10.254/24
IPv4 Upstream gateway: None

# OPT2

## General Configuration
Enable: unchecked
Description: OPT2
IPv4 Configuration Type: None

## Static IPv4 Configuration

IPv4 Address: 10.0.20.254/24
IPv4 Upstream gateway: None

# Diagnostics/routes

## IPv4 Routes
|Destination|Gateway|Flags|Uses|MTU|Interface|
|0.0.0.0|5.196.50.254|UGS|11|1500|vtnet0|
|5.196.50.0/24|link#1|U|6|1500|vtnet0|
|5.196.50.51|link#3|UHS|7|16384|lo0|
|10.0.10.0/24|link#10|U|1|1500|vtnet1.10|
|10.0.10.254|link#3|UHS|3|16384|lo0|
|10.0.20.0/24|link#11|U|4|1500|vtnet1.20|
|10.0.20.254|link#3|UHS|5|16384|lo0|
|127.0.0.1|link#3|UH|2|16384|lo0|
