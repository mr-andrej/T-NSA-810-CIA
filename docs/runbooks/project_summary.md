# Project Summary — Cloud Infrastructure Architects

## What the project is
A school project to design, deploy, and secure a hybrid infrastructure connecting two separate sites, with a focus on network segmentation, security, observability, and scalability. The team is called Cloud Infrastructure Architects.

## Architecture Overview

Two sites connected by an encrypted site-to-site VPN tunnel over the internet.

### Site 1 — Internal/On-prem (the simpler site)

Proxmox hypervisor hosting 3 VMs maximum
S1-FW — pfSense firewall, the central traffic enforcement point, VPN client toward Site 2, DNS forwarder
S1-APP — Ubuntu Server, hosts the internal web application (port 8080/443), sits on VLAN 10 (10.0.10.0/24)
S1-DB — Ubuntu Server, hosts PostgreSQL database, sits on VLAN 20 (10.0.20.0/24)

### Site 2 — Remote/Cloud (the more complex site)

Proxmox hypervisor hosting 3 VMs maximum
S2-FW — pfSense firewall, internet-facing, VPN server, emergency cut-off point, DNS forwarder
S2-JS — Bastion/Jump Server in DMZ (VLAN 10, 192.168.10.0/24), the only SSH entry point from outside, all sessions logged to Elasticsearch
S2-MT — Monitoring VM (VLAN 20, 192.168.20.0/24), running Ansible, Vault, Elasticsearch, Prometheus, Grafana, NetBox

VPN Tunnel

OpenVPN site-to-site between S1-FW and S2-FW
Tunnel subnet 172.16.0.0/30, Site 1 endpoint 172.16.0.2, Site 2 endpoint 172.16.0.1
All inter-site traffic including DNS forwarding travels through this tunnel

## Key Design Decisions
Network segmentation via VLANs — traffic separation enforced at pfSense level since Proxmox bridges are not VLAN-aware in the school environment. VLAN 10 and VLAN 20 on each site isolate services from each other, with pfSense as the only router between zones.
Least privilege firewall rules — only explicitly permitted traffic is allowed between VLANs. On Site 1 for example, the App Server can only reach the DB on port 5432, and DNS queries only go to pfSense itself. Everything else is blocked.
Bastion on Site 2 in DMZ — the only legitimate SSH entry point into the remote site. Positioned in the DMZ (semi-public zone), it cannot initiate connections to internal VLANs beyond what pfSense explicitly permits. All sessions are logged.
Centralised observability on Site 2 — Elasticsearch on S2-MT receives logs from both sites via log shipping (Filebeat agents). Keeping it on Site 2 means monitoring survives even if Site 1 goes down.
Emergency cut-off — handled at S2-FW firewall level. VPN and SSH can be blocked at the firewall without losing the bastion for recovery access.

## Infrastructure Constraints

3 VMs maximum per Proxmox site — already satisfied by the current design
No Terraform for Proxmox VM provisioning — students don't have hypervisor-level SSH access, so IaC shifts to Ansible for in-VM configuration management
Proxmox bridges not VLAN-aware — VLAN segmentation enforced entirely within pfSense, documented as a known environment constraint. Student VMs cannot use VLAN tags on their NICs (confirmed during ticket #54): Proxmox blocks VM startup with "no physical interface on bridge" when a VLAN tag is set. Workaround: VM NICs are left untagged; pfSense sub-interfaces (vtnet1.10, vtnet1.20) handle VLAN separation internally.
Site 2 potentially migrating to AWS — decision pending, would replace Proxmox VMs with EC2 instances inside a VPC, with subnets mapping to current VLAN design

## Current Progress

### Completed

Architecture designed and validated (V2 diagram)
S2-FW foundational network configuration — VLANs, firewall rules, DNS resolver, host overrides (teammate's work, runbook written)
S1-FW foundational network configuration (ticket #57) — VLANs 10 and 20, DHCP, inter-VLAN firewall rules, DNS resolver with host overrides and domain override pre-configured for Site 2
S1-APP Ubuntu Server installed and network configured (ticket #54) — static IP 10.0.10.1/24, gateway 10.0.10.254 and DNS pointing to pfSense. Netplan applied, interface enp6s18 UP with correct address. Full ping verification blocked by Proxmox VLAN tag restriction (see Infrastructure Constraints); configuration is correct and documented.

### In Progress

S1-DB network configuration (ticket #38) — same process as S1-APP, IP 10.0.20.1/24, gateway 10.0.20.254, DNS pointing to pfSense on VLAN 20

### Blocked

VPN client on Site 1 (ticket #48) — blocked on ticket #47 (OpenVPN server on Site 2) not yet complete
Inter-site routing (ticket #49) — blocked on VPN tunnel being up
DNS forwarding verification across sites — blocked on VPN tunnel
Cross-site log shipping via Filebeat — blocked on VPN tunnel

### Not yet started

Bastion outbound restriction rules on S2-FW (evaluator feedback)
Filebeat agent on S1-APP
S2-MT, S2-JS base network configuration (tickets #56, #55)
Runbook documentation (ticket #41) — intentionally left for last

## Open Action Items from Evaluator Feedback

Document firewall rules between VLAN 10 and VLAN 20 with explicit justification ✅ done
Restrict bastion outbound access — not full LAN access ⬜ pending
Document and justify DMZ positioning of bastion ⬜ pending
Add Filebeat agent on S1-APP for log shipping to Elasticsearch ⬜ pending
Review S2-MT resource load — Elasticsearch is RAM-hungry, may need to trim services ⬜ pending
