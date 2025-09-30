# AWX / Tower - Guide rapide

1) Créer un *Project* pointant sur ce dépôt (branch principale).
2) Créer des *Credentials* SSH (clé privée correspondante à `ssh/id_rsa` ou autre).
3) Créer un *Inventory* `DEV` et y associer `inventories/dev`.
4) Créer un *Job Template* :
   - Inventory: DEV
   - Project: Fil Rouge
   - Playbook: `playbooks/05_stack.yml`
   - Credentials: SSH
   - Options: "Enable privilege escalation"
   - (Option) Survey: importer `awx/survey.json`.
5) Lancer le Job et vérifier l'idempotence sur un second run.
