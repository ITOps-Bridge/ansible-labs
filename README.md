# Ansible Fil Rouge — Version FORMATEUR

Cette version contient **les solutions** complètes et des commentaires pédagogiques.

## Démarrage rapide
```bash
vagrant up controller
vagrant up node1 node2
# Depuis la VM controller
vagrant ssh controller
cd /vagrant/ansible-fil-rouge-formateur
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook playbooks/00_ping.yml
ansible-playbook playbooks/01_setup_users.yml
ansible-playbook playbooks/05_stack.yml
```

## Différences clés vs Stagiaires
- `playbooks/01_setup_users.yml`: tâches complètes (list/dict/when).
- `roles/common/tasks/main.yml`: rôle implémenté.
- `vars/vault.yml`: exemple fourni (à chiffrer en vrai).
- Tous les rôles (web/db) prêts à l’emploi.

## Périmètre couvert
- Ad-hoc, variables (listes/dicts), when
- Lookups & Vault
- Modules, rôles, collections, handlers
- Web (Nginx) + DB (MariaDB)
- Orchestration `05_stack.yml`
- AWX/Tower (survey, job template)
