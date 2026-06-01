PLAYBOOK       = ansible-playbook playbooks/proxmox_snapshot.yaml --ask-vault-pass
PLAYBOOK_LOCAL = ansible-playbook playbooks/proxmox_cloudinit.yaml --ask-vault-pass
SNAP          ?= snapshot

# Site 1 — ns3183326.ip-146-59-253.eu
SITE1_FW  = 105
SITE1_DB  = 2037
SITE1_APP = 3037

# Site 2 — ns3050272.ip-51-255-76.eu
SITE2_FW = 124
SITE2_JS = 2037
SITE2_MT = 3037

# ---- Site 1 ----------------------------------------------------------------

snap.create.site1.fw:   ; $(PLAYBOOK) -e "snap_action=create  site=site1 vmid=$(SITE1_FW)  snap_name=$(SNAP)"
snap.restore.site1.fw:  ; $(PLAYBOOK) -e "snap_action=restore site=site1 vmid=$(SITE1_FW)  snap_name=$(SNAP)"
snap.delete.site1.fw:   ; $(PLAYBOOK) -e "snap_action=delete  site=site1 vmid=$(SITE1_FW)  snap_name=$(SNAP)"

snap.create.site1.db:   ; $(PLAYBOOK) -e "snap_action=create  site=site1 vmid=$(SITE1_DB)  snap_name=$(SNAP)"
snap.restore.site1.db:  ; $(PLAYBOOK) -e "snap_action=restore site=site1 vmid=$(SITE1_DB)  snap_name=$(SNAP)"
snap.delete.site1.db:   ; $(PLAYBOOK) -e "snap_action=delete  site=site1 vmid=$(SITE1_DB)  snap_name=$(SNAP)"

snap.create.site1.app:  ; $(PLAYBOOK) -e "snap_action=create  site=site1 vmid=$(SITE1_APP) snap_name=$(SNAP)"
snap.restore.site1.app: ; $(PLAYBOOK) -e "snap_action=restore site=site1 vmid=$(SITE1_APP) snap_name=$(SNAP)"
snap.delete.site1.app:  ; $(PLAYBOOK) -e "snap_action=delete  site=site1 vmid=$(SITE1_APP) snap_name=$(SNAP)"

# ---- Site 2 ----------------------------------------------------------------

snap.create.site2.fw:   ; $(PLAYBOOK) -e "snap_action=create  site=site2 vmid=$(SITE2_FW)  snap_name=$(SNAP)"
snap.restore.site2.fw:  ; $(PLAYBOOK) -e "snap_action=restore site=site2 vmid=$(SITE2_FW)  snap_name=$(SNAP)"
snap.delete.site2.fw:   ; $(PLAYBOOK) -e "snap_action=delete  site=site2 vmid=$(SITE2_FW)  snap_name=$(SNAP)"

snap.create.site2.js:   ; $(PLAYBOOK) -e "snap_action=create  site=site2 vmid=$(SITE2_JS)  snap_name=$(SNAP)"
snap.restore.site2.js:  ; $(PLAYBOOK) -e "snap_action=restore site=site2 vmid=$(SITE2_JS)  snap_name=$(SNAP)"
snap.delete.site2.js:   ; $(PLAYBOOK) -e "snap_action=delete  site=site2 vmid=$(SITE2_JS)  snap_name=$(SNAP)"

snap.create.site2.mt:   ; $(PLAYBOOK) -e "snap_action=create  site=site2 vmid=$(SITE2_MT)  snap_name=$(SNAP)"
snap.restore.site2.mt:  ; $(PLAYBOOK) -e "snap_action=restore site=site2 vmid=$(SITE2_MT)  snap_name=$(SNAP)"
snap.delete.site2.mt:   ; $(PLAYBOOK) -e "snap_action=delete  site=site2 vmid=$(SITE2_MT)  snap_name=$(SNAP)"

# ---- Cloud-init ------------------------------------------------------------

cloudinit.site1.fw:  ; $(PLAYBOOK_LOCAL) -e "site=site1 vmid=$(SITE1_FW)  node=vm002"
cloudinit.site1.db:  ; $(PLAYBOOK_LOCAL) -e "site=site1 vmid=$(SITE1_DB)  node=vm002"
cloudinit.site1.app: ; $(PLAYBOOK_LOCAL) -e "site=site1 vmid=$(SITE1_APP) node=vm002"

cloudinit.site2.fw:  ; $(PLAYBOOK_LOCAL) -e "site=site2 vmid=$(SITE2_FW)  node=vm3"
cloudinit.site2.js:  ; $(PLAYBOOK_LOCAL) -e "site=site2 vmid=$(SITE2_JS)  node=vm3"
cloudinit.site2.mt:  ; $(PLAYBOOK_LOCAL) -e "site=site2 vmid=$(SITE2_MT)  node=vm3"

# ---- Network ---------------------------------------------------------------

network.site1.db:
	ansible-playbook playbooks/network.yaml -e "target=s1_db" --ask-vault-pass

# ---- Help ------------------------------------------------------------------

.PHONY: help
help:
	@echo "Usage: make snap.<action>.<site>.<vm> SNAP=<name>"
	@echo ""
	@echo "Actions:  create  restore  delete"
	@echo ""
	@echo "Site 1 (ns3183326.ip-146-59-253.eu)"
	@echo "  site1.fw   Firewall     (vmid $(SITE1_FW))"
	@echo "  site1.db   Database     (vmid $(SITE1_DB))"
	@echo "  site1.app  App server   (vmid $(SITE1_APP))"
	@echo ""
	@echo "Site 2 (ns3050272.ip-51-255-76.eu)"
	@echo "  site2.fw   Firewall     (vmid $(SITE2_FW))"
	@echo "  site2.js   Jump server  (vmid $(SITE2_JS))"
	@echo "  site2.mt   Monitoring   (vmid $(SITE2_MT))"
	@echo ""
	@echo "Examples:"
	@echo "  make snap.create.site1.db  SNAP=pre-mongo"
	@echo "  make snap.restore.site2.mt SNAP=pre-update"
	@echo "  make snap.delete.site1.fw  SNAP=old-snap"
