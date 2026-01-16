# T-NSA-810-CIA: Hybrid Infrastructure with Proxmox

> **Deployment and Securing of a Hybrid Infrastructure with Proxmox**  
> A GitOps-driven project for building secure, scalable multi-site infrastructure

[![Project Status](https://img.shields.io/badge/status-in%20development-yellow)](https://github.com/mr-andrej/T-NSA-810-CIA)

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Technology Stack](#technology-stack)
- [Getting Started](#getting-started)
- [Documentation](#documentation)
- [Team](#team)
- [Contributing Guidelines](#contributing-guidelines)

## Overview

This project implements a **hybrid infrastructure** composed of two Proxmox sites (on-premises and remote) with secure site-to-site connectivity, automated IP management, centralized logging, and comprehensive observability. Built with GitOps principles, the infrastructure is designed to be reproducible, scalable, and ready for multi-site expansion.

### Key Objectives

- Deploy dual-site Proxmox infrastructure (Site 1 + Site 2)
- Establish secure site-to-site VPN connectivity
- Implement firewalls with emergency cut-off capability
- Set up bastion host for remote access
- Automate IP management via NetBox (IPAM)
- Centralize logs and monitoring with Elasticsearch
- Deploy internal-only web services
- Create scalable architecture for future site integration

## Repository Structure

This project follows a **mono-repository** approach with clear separation of concerns:

```
T-NSA-810-CIA/
├── infra/                     # Infrastructure as Code
│   ├── terraform/             # Terraform configurations
│   │   ├── proxmox/           # Proxmox provider configs
│   │   ├── modules/           # Reusable Terraform modules
│   │   └── environments/      # Site-specific variables
│   ├── ansible/               # Ansible playbooks and roles
│   │   ├── playbooks/         # Service deployment playbooks
│   │   ├── roles/             # Reusable Ansible roles
│   │   └── inventory/         # Dynamic inventory from NetBox
│   ├── networking/            # Network configurations (VPN, firewall)
│   └── services/              # Service-specific configs
│
├── docs/                      # Project documentation
│   ├── architecture/          # Architecture diagrams and decisions
│   ├── runbooks/              # Operational procedures
│   └── disaster-recovery/     # DRP and recovery procedures
│
├── scripts/                   # Automation and utility scripts
│   ├── deployment/            # Deployment automation
│   ├── monitoring/            # Monitoring and health checks
│   └── maintenance/           # Backup and maintenance scripts
│
├── configs/                   # Configuration files
│   ├── firewall/              # pfSense rules and configs
│   ├── vpn/                   # OpenVPN configurations
│   └── dns/                   # DNS forwarding configs
│
├── tests/                     # Testing and validation
│   ├── integration/           # Integration tests
│   └── validation/            # Infrastructure validation scripts
│
├── .github/                        # GitHub-specific
│   ├── workflows/                 # CI/CD pipelines
│   ├── ISSUE_TEMPLATE/
│
├── .gitignore                      # Git ignore patterns
├── README.md                       # Project overview
└── CONTRIBUTING.md                 # Contribution guidelines
```

See our [Repository Strategy](https://github.com/mr-andrej/T-NSA-810-CIA/wiki/Repository-Strategy) wiki page for detailed justification.

## Technology Stack

### Core Infrastructure
- **Proxmox VE**: Bare-metal virtualization platform
- **pfSense**: FreeBSD-based firewall/router
- **OpenVPN**: Site-to-site VPN encryption

### Automation & Management
- **Terraform**: Infrastructure provisioning and VM lifecycle management
- **Ansible**: Configuration management and service deployment
- **NetBox**: IPAM/DCIM source of truth with API integration

### Observability
- **Elasticsearch**: Centralized logging and analysis
- **Kibana**: Log visualization and dashboards
- **Filebeat/Logstash**: Log collection and processing

### GitOps & CI/CD
- **GitHub Actions**: Automated testing and deployment
- **Git**: Version control and infrastructure state

## Getting Started

### Prerequisites

- Proxmox VE 8.x installed on bare metal
- Access to two separate network sites
- Basic understanding of networking and virtualization
- Git and SSH configured

### Quick Start

`TODO`

## Documentation

All project documentation and planning information is available in the `/docs` directory, the repository [project page](https://github.com/users/mr-andrej/projects/2) and the [project wiki](https://github.com/mr-andrej/T-NSA-810-CIA/wiki):

- **[Architecture Overview](docs/architecture/overview.md)**: System design and diagrams (TBD)
- **[Deployment Runbooks](docs/runbooks/)**: Step-by-step deployment procedures (TBD)
- **[Disaster Recovery Plan](docs/disaster-recovery/)**: DRP and business continuity (TBD)
- **[Wiki](https://github.com/mr-andrej/T-NSA-810-CIA/wiki)**: Additional guides and references
- **[Project](https://github.com/users/mr-andrej/projects/2)**: Roadmap/Gantt, Backlog, Kanban 

## Team
PAR_14

**Collaborators**

- [@CherryClairette](https://github.com/CherryClairette)
- [@kylian-epitech](https://github.com/kylian-epitech)
- [@LuckyShuii](https://github.com/LuckyShuii)
- [@PaulDecauchy](https://github.com/PaulDecauchy)
- [@mr-andrej](https://github.com/mr-andrej)

## Contributing Guidelines

We follow GitOps best practices. All infrastructure changes must:

1. Be committed to this repository
2. Pass automated validation checks
3. Be reviewed by at least one team member
4. Be documented in relevant runbooks

## Links

- **Repository**: [https://github.com/mr-andrej/T-NSA-810-CIA](https://github.com/mr-andrej/T-NSA-810-CIA)
- **Wiki**: [https://github.com/mr-andrej/T-NSA-810-CIA/wiki](https://github.com/mr-andrej/T-NSA-810-CIA/wiki)
- **Issues**: [https://github.com/mr-andrej/T-NSA-810-CIA/issues](https://github.com/mr-andrej/T-NSA-810-CIA/issues)
- **Project Board**: [https://github.com/mr-andrej/T-NSA-810-CIA/projects](https://github.com/users/mr-andrej/projects/2)

---

**Last Updated**: January 16, 2026  
**Project Status**: In Development  
**Version**: 1.0.0
