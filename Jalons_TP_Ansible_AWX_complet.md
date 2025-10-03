# TP Ansible Fil Rouge + AWX Plan Global (2 Jours)

Ce document décrit pas à pas les **TPs** du TP Ansible (2 jours), de la **mise en place Vagrant**
jusqu’à l’intégration dans **AWX** sur **k3s**.

Il s'agit de déployer une petite stack “Web + DB” (Nginx + MariaDB) sur 2 nœuds Linux (Ubuntu), avec gestion d’utilisateurs, templating, variables hiérarchisées, rôles, collections, plugins, et finalement exécution via AWX.

---

## Pré-requis

- **VirtualBox** (ou Hyper-V, adapter si besoin)
- **Vagrant**
- **Visual Studio Code**
- **Git**
- **Client SSH (Tabby)**
- 16 Go RAM minimum sur la machine hôte (Windows Ou Linux)
- Accès Internet

---

## 🚀 Setup Vagrant (lab 3 VMs : controller + node1 + node2)

Copiez ce **Vagrantfile** à la racine du projet.
Il crée 3 VMs : `controller` (avec Ansible) + `node1` (web) + `node2` (db).  
Le contrôleur génère une **clé SSH** partagée via le dossier synchronisé `./ssh`.

> Réseau privé utilisé : `192.168.56.1/24` (modifiez au besoin).

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
  end

  controller_pubkey_path = "/vagrant/ssh/id_rsa.pub"

  config.vm.define "controller" do |c|
    c.vm.hostname = "controller"
    c.vm.network "private_network", ip: "192.168.56.110"
    c.vm.provision "shell", inline: <<-SHELL
      set -e
      sudo apt-get update -y
      sudo apt-get install -y python3-pip
      python3 -m pip install --upgrade pip
      pip install ansible passlib
      sudo apt-get install -y  git sshpass
      mkdir -p /vagrant/ssh
      if [ ! -f /vagrant/ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -N "" -f /vagrant/ssh/id_rsa
        chmod 600 /vagrant/ssh/id_rsa
      fi
      echo "[OK] Clé SSH générée dans /vagrant/ssh/"
    SHELL
  end

  def provision_node(vmconfig, ip, hostname, controller_pubkey_path)
    vmconfig.vm.hostname = hostname
    vmconfig.vm.network "private_network", ip: ip
    vmconfig.vm.provision "shell", inline: <<-SHELL
      set -e
      sudo apt-get update -y
      sudo apt-get install -y python3
      if ! id ansible >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash ansible
        echo "ansible ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-ansible
      fi
      sudo mkdir -p /home/ansible/.ssh
      if [ -f #{controller_pubkey_path} ]; then
        sudo cp #{controller_pubkey_path} /home/ansible/.ssh/authorized_keys
        sudo chown -R ansible:ansible /home/ansible/.ssh
        sudo chmod 700 /home/ansible/.ssh
        sudo chmod 600 /home/ansible/.ssh/authorized_keys
      else
        echo "ATTENTION: clé publique introuvable (#{controller_pubkey_path}). Lance d’abord 'vagrant up controller'."
      fi
    SHELL
  end

  config.vm.define "node1" do |n1|
    provision_node(n1, "192.168.56.111", "node1", controller_pubkey_path)
  end

  config.vm.define "node2" do |n2|
    provision_node(n2, "192.168.56.112", "node2", controller_pubkey_path)
  end
end
```

**Démarrage :**
```bash
PS C:\Users\Administrateur\ansible-labs> vagrant.exe up controller # génère la clé SSH dans ./ssh/
Bringing machine 'controller' up with 'virtualbox' provider...
==> controller: Box 'ubuntu/jammy64' could not be found. Attempting to find and install...
    controller: Box Provider: virtualbox
    controller: Box Version: >= 0
==> controller: Loading metadata for box 'ubuntu/jammy64'
    controller: URL: https://vagrantcloud.com/api/v2/vagrant/ubuntu/jammy64
==> controller: Adding box 'ubuntu/jammy64' (v20241002.0.0) for provider: virtualbox
    controller: Downloading: https://vagrantcloud.com/ubuntu/boxes/jammy64/versions/20241002.0.0/providers/virtualbox/unknown/vagrant.box
    controller:
==> controller: Successfully added box 'ubuntu/jammy64' (v20241002.0.0) for 'virtualbox'!
==> controller: Importing base box 'ubuntu/jammy64'...
==> controller: Matching MAC address for NAT networking...
==> controller: Checking if box 'ubuntu/jammy64' version '20241002.0.0' is up to date...
==> controller: Setting the name of the VM: ansible-labs_controller_1759134255414_97685
Vagrant is currently configured to create VirtualBox synced folders with
...............
$ vagrant up node1 node2        # injecte la clé publique sur les nodes
PS C:\Users\Administrateur\ansible-labs> vagrant up node1 node2
Bringing machine 'node1' up with 'virtualbox' provider...
Bringing machine 'node2' up with 'virtualbox' provider...
==> node1: Importing base box 'ubuntu/jammy64'...
==> node1: Matching MAC address for NAT networking...
==> node1: Checking if box 'ubuntu/jammy64' version '20241002.0.0' is up to date...
==> node1: Setting the name of the VM: ansible-labs_node1_1759135537556_28229
==> node1: Fixed port collision for 22 => 2222. Now on port 2200.
==> node1: Clearing any previously set network interfaces...
==> node1: Preparing network interfaces based on configuration...
    node1: Adapter 1: nat
    node1: Adapter 2: hostonly
==> node1: Forwarding ports...
    node1: 22 (guest) => 2200 (host) (adapter 1)
==> node1: Running 'pre-boot' VM customizations...
==> node1: Booting VM...
==> node1: Waiting for machine to boot. This may take a few minutes...
    node1: SSH address: 127.0.0.1:2200
    node1: SSH username: vagrant
    node1: SSH auth method: private key
...................
```

**Démarrage :**
```bash
PS C:\Users\Administrateur\ansible-labs> vagrant.exe status
Current machine states:

controller                running (virtualbox)
node1                     running (virtualbox)
node2                     running (virtualbox)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run `vagrant status NAME`.
PS C:\Users\Administrateur\ansible-labs>

$ vagrant ssh controller        # pour lancer ansible depuis /vagrant
$ sudo su
root@controller:/home/vagrant# ssh -i /vagrant/ssh/id_rsa ansible@192.168.56.111
root@controller:/home/vagrant# ssh -i /vagrant/ssh/id_rsa ansible@192.168.56.112
```

**Create the ansible.cfg file :**
```ini
[defaults]
inventory = /vagrant/inventories/dev/hosts.ini
roles_path = roles
remote_user = ansible
private_key_file = /vagrant/ssh/id_rsa
stdout_callback = yaml
# Sortie formatée en YAML
host_key_checking = False
# Désactive la vérification d’empreinte SSH. Pas de blocage SSH au premier run
retry_files_enabled = False
# Désactive la création des fichiers *.retry
forks = 20
# Nombre de connexions SSH en parallèle. Par défaut c’est 5, mais en pratique on monte souvent à 20 ou 50.
interpreter_python = /usr/bin/python3
# Ansible va choisir automatiquement /usr/bin/python3 sur Ubuntu 22.04. auto + silent (supprime les warnings)

[ssh_connection]
pipelining = True
# Accélère l’exécution (souvent de 20-30%). Ansible exécute les modules plus vite en envoyant le code directement via SSH
```

```bash
root@controller:/vagrant#$ cd /vagrant
root@controller:/vagrant#$ mkdir  mkdir /etc/ansible/
root@controller:/vagrant# vi  /etc/ansible/ansible.cfg
root@controller:/vagrant# ansible-config view
```

**Inventaire DEV (`inventories/dev/hosts.ini`) :**
```bash
root@controller:/vagrant# mkdir -p inventories/dev
```

```ini
[web]
node1 ansible_host=192.168.56.111

[db]
node2 ansible_host=192.168.56.112
```

---

## 📌 TP 0 — Initialisation & ad-hoc

**Objectif :** prendre en main l’inventaire et exécuter des commandes ad-hoc.

```bash
ansible all -m ping
root@controller:/vagrant# ansible all -m ping
node2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

root@controller:/vagrant# ansible web -a "uptime"
node1 | CHANGED | rc=0 >>
 14:42:39 up  2:19,  0 users,  load average: 0.00, 0.00, 0.00
root@controller:/vagrant# ansible web -a "uptime"
node1 | CHANGED | rc=0 >>
 14:43:26 up  2:20,  0 users,  load average: 0.00, 0.00, 0.00

root@controller:/vagrant# ansible db -m apt -a "name=mariadb-server state=present update_cache=yes" --become
root@controller:/vagrant# ansible db -m shell -a "mariadb --version"
node2 | CHANGED | rc=0 >>
mariadb  Ver 15.1 Distrib 10.6.22-MariaDB, for debian-linux-gnu (x86_64) using  EditLine wrapper
root@controller:/vagrant#
root@controller:/vagrant# ansible db -m service -a "name=mariadb state=started"
node2 | SUCCESS => {
    "changed": false,
    "name": "mariadb",
    "state": "started",
    "status": {
.....................
```

---

## 📌 TP 1 — Playbooks, Variables (listes, dictionnaires) Loops & conditions (when)
- Creer le repertoire `inventories/dev/group_vars/`
```bash
root@controller:/vagrant# mkdir -p inventories/dev/group_vars/
```

- `inventories/dev/group_vars/all.yml`

```yaml
project_name: "fil-rouge"
timezone: "Europe/Paris"
app_env: "dev"

common_packages:
  - git
  - curl
  - vim
  - htop

users_map:
  alice:
    groups: ["sudo"]
    shell: /bin/bash
  bob:
    groups: ["www-data"]
    shell: /bin/bash
```

- `inventories/dev/group_vars/web.yml`

```yaml
nginx_listen_port: 80
web_index_message: "Hello from {{ inventory_hostname }} / {{ app_env }}"
```

- `inventories/dev/group_vars/db.yml`

```yaml
mariadb_bind_address: "0.0.0.0"
# Secrets DB (exemple)
db_app_name: "appdb"            # nom de la base
db_app_user: "appuser"          # utilisateur applicatif
db_app_password: "Str0ngPass!"  # MOT DE PASSE EN CLAIR (chiffré par le vault au repos)
db_app_host: "localhost"             
# (optionnel) surcharger le root si tu préfères le mettre aussi dans Vault :
mariadb_root_password: "ChangeMeRoot"
```
**Premier Playbook :**
`Playbook 00_ping.yml` :

```yaml
- name: Premier Playbook
  hosts: all
  gather_facts: true
  become: yes
  tasks:
    - name: Ping All
      ansible.builtin.ping:
    - name: Afficher Les varaibles Group Vars
      debug:
        msg: "Env={{ app_env }}, Host={{ inventory_hostname }}, TZ={{ timezone }}"
```
`Exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/00_ping.yml 

PLAY [Premier Playbook] *******************************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [Ping All] ***************************************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [Afficher Les varaibles Group Vars] **************************************************************************************************************************************************************************************************ok: [node1] => 
  msg: Env=dev, Host=node1, TZ=Europe/Paris
ok: [node2] => 
  msg: Env=dev, Host=node2, TZ=Europe/Paris

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

root@controller:/vagrant# 
```

`Playbook 01_setup_users.yml` :

```yaml
- name: Baseline (common) + exemples listes/dicts/when
  hosts: all
  gather_facts: true

  tasks:
    - name: Display os_family Fact
      debug:
       msg: "{{ ansible_facts['os_family'] }}"
       
    - name: Installer des paquets communs (LISTE) - Debian only
      ansible.builtin.package:
        name: "{{ common_packages }}"
        state: present
      become: true
      when: ansible_facts['os_family'] == "Debian"  # condition d'exemple

    - name: Créer des utilisateurs depuis DICTIONNAIRE
      ansible.builtin.user:
        name: "{{ item.key }}"
        shell: "{{ item.value.shell }}"
        groups: "{{ item.value.groups | default([]) }}"
        append: true
        create_home: true
      loop: "{{ users_map | dict2items }}"
      become: true

    - name: Déployer un MOTD différent en dev
      ansible.builtin.copy:
        dest: /etc/motd
        content: "ENV={{ app_env }} | Host={{ inventory_hostname }} | Projet={{ project_name }}\n"
        mode: '0644'
      become: true
      when: app_env == "dev"
```
`Exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/01_setup_users.yml 

PLAY [Baseline (common) + exemples listes/dicts/when] *************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [Display os_family Fact] *************************************************************************************************************************************************************************************************************ok: [node1] => 
  msg: Debian
ok: [node2] => 
  msg: Debian

TASK [Installer des paquets communs (LISTE) - Debian only] ********************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [Créer des utilisateurs depuis DICTIONNAIRE] *****************************************************************************************************************************************************************************************ok: [node2] => (item={'key': 'alice', 'value': {'groups': ['sudo'], 'shell': '/bin/bash'}})
ok: [node1] => (item={'key': 'alice', 'value': {'groups': ['sudo'], 'shell': '/bin/bash'}})
ok: [node1] => (item={'key': 'bob', 'value': {'groups': ['www-data'], 'shell': '/bin/bash'}})
ok: [node2] => (item={'key': 'bob', 'value': {'groups': ['www-data'], 'shell': '/bin/bash'}})

TASK [Déployer un MOTD différent en dev] **************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

root@controller:/vagrant# 
```
---

## 📌 TP 2 — Vault Collections & Lookups
### Ansible Vault
`Utiliser le contenu suivant pour creer le  fichier vars/vault_users.yml` :
```yaml
vault_users:
  - name: "secretdba"
    password: "SuperSecret123!"
    groups: "sudo"
```

`Créer un vault` :
```bash
$ ansible-vault create vars/vault_users.yml # Sepecifier votre mot de passe vault
$ ansible-vault edit vars/vault_users.yml
```

`Creer un playbook pour utiliser le secret playbooks/02_vault.yml` :
```yaml
- name: Créer un utilisateur dont le mot de passe est stocké dans Vault
  hosts: all
  become: true
  vars_files:
    - ../vars/vault_users.yml

  tasks:
    - name: Créer un utilisateur sécurisé
      user:
        name: "{{ item.name }}"
        password: "{{ item.password | password_hash('sha512') }}" #on utilise le filter password_hash('sha512') pour transformer le mot de passe clair en hash Linux compatible (/etc/shadow).
        groups: "{{ item.groups }}"
        state: present
      loop: "{{ vault_users }}"
```

`Exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/02_vault.yml --ask-vault-pass
Vault password: 

PLAY [Créer un utilisateur dont le mot de passe est stocké dans Vault] ********************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [Créer un utilisateur sécurisé] ******************************************************************************************************************************************************************************************************changed: [node1] => (item={'name': 'secretdba', 'password': 'SuperSecret123!', 'groups': 'sudo'})
changed: [node2] => (item={'name': 'secretdba', 'password': 'SuperSecret123!', 'groups': 'sudo'})

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

root@controller:/vagrant#
```
### Collections
- Créer le fichier `collections/requirements.yml`

```yaml
collections:
  - name: community.general
    source: https://galaxy.ansible.com
    version: "8.5.0"

  - name: ansible.posix
    source: https://galaxy.ansible.com
    version: "1.5.4"

  - name: community.mysql
    source: https://galaxy.ansible.com
    version: "3.9.0"
```
`Installation des collections` :

```bash
root@controller:/vagrant# ansible-galaxy collection install -r collections/requirements.yml
Starting galaxy collection install process
Process install dependency map
Starting collection install process
Downloading https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/artifacts/community-general-8.5.0.tar.gz to /root/.ansible/tmp/ansible-local-15921whvsnabk/tmpdd_bazrz/community-general-8.5.0-430_4dtc
Installing 'community.general:8.5.0' to '/root/.ansible/collections/ansible_collections/community/general'
Downloading https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/artifacts/ansible-posix-1.5.4.tar.gz to /root/.ansible/tmp/ansible-local-15921whvsnabk/tmpdd_bazrz/ansible-posix-1.5.4-od3u2fqq
community.general:8.5.0 was installed successfully
Installing 'ansible.posix:1.5.4' to '/root/.ansible/collections/ansible_collections/ansible/posix'
ansible.posix:1.5.4 was installed successfully
Downloading https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/artifacts/community-mysql-3.9.0.tar.gz to /root/.ansible/tmp/ansible-local-15921whvsnabk/tmpdd_bazrz/community-mysql-3.9.0-rhkyj6g_
Installing 'community.mysql:3.9.0' to '/root/.ansible/collections/ansible_collections/community/mysql'
community.mysql:3.9.0 was installed successfully
root@controller:/vagrant# 
root@controller:/vagrant# ls /root/.ansible/
collections/  cp/           galaxy_cache/ galaxy_token  tmp/
root@controller:/vagrant#
```
### Lookups
- Créer `un fichier files/motd.txt` :
```bash
Bienvenue sur le serveur Ansible !
```
- Creer le fichier `files/users.csv`. Ici chaque ligne = un utilisateur, avec son mot de passe.

- Creer un playbook  `playbooks/03_collections_lookups.yml` :
```yaml
- name: Manipulations Lookup
  hosts: all
  become: true
  vars:
    users_file: "../files/users.csv"

  tasks:
    - name: Lire le CSV (localhost, une fois)
      community.general.read_csv:
        path: "{{ users_file }}"
        fieldnames: username,password,groups
        delimiter: ','
      register: csv_users
      delegate_to: localhost


    - name: Afficher la liste des utilisateurs
      debug:
        msg: "{{ csv_users }}"
      delegate_to: localhost
      run_once: true

    - name: Lire un fichier avec lookup
      debug:
        msg: "{{ lookup('file', '../files/motd.txt') }}"
      delegate_to: localhost
      

    - name: Générer un mot de passe aléatoire
      debug:
        msg: "{{ lookup('password', '/dev/null length=12 chars=ascii_letters') }}"
```

`Exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/03_collections_lookups.yml 

PLAY [Manipulations Lookup] *******************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [Lire le CSV (localhost, une fois)] **************************************************************************************************************************************************************************************************ok: [node1 -> localhost]
ok: [node2 -> localhost]

TASK [Afficher la liste des utilisateurs] *************************************************************************************************************************************************************************************************ok: [node1 -> localhost] => 
  msg:
    changed: false
    dict: {}
    failed: false
    list:
    - groups: groups
      password: password
      username: username
    - groups: sudo
      password: Azerty123!
      username: erick
    - groups: www-data
      password: ChangeMe123
      username: benoit
    - groups: developers
      password: Passw0rd!
      username: charlie

TASK [Lire un fichier avec lookup] ********************************************************************************************************************************************************************************************************ok: [node1 -> localhost] => 
  msg: Bienvenue sur le serveur Ansible !
ok: [node2 -> localhost] => 
  msg: Bienvenue sur le serveur Ansible !

TASK [Générer un mot de passe aléatoire] **************************************************************************************************************************************************************************************************ok: [node1] => 
  msg: kpxofZzfPhSR
ok: [node2] => 
  msg: BlEPZjKimlmd

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
---

## 📌 TP 3 — Rôle `common`
But : standardiser préparation système via rôle common.
```bash
root@controller:/vagrant# mkdir roles
root@controller:/vagrant# cd roles/
root@controller:/vagrant/roles# ansible-galaxy role init common
- Role common was created successfully
root@controller:/vagrant/roles# ls common/
README.md  defaults  files  handlers  meta  tasks  templates  tests  vars
root@controller:/vagrant/roles#
```
Exemple rôle `roles/common/` 

`roles/common/defaults/main.yml` :
```yaml
common_motd: "Bienvenue sur {{ inventory_hostname }} ({{ project_name }})"
timezone: "Europe/Paris"
```

`roles/common/tasks/main.yml` :
```yaml
- name: Ensure common packages
  package:
    name: "{{ common_packages }}"
    state: present
  become: true

- name: Set timezone
  community.general.timezone:
    name: "{{ timezone }}"
  become: true

- name: Deploy MOTD
  template:
    src: motd.j2
    dest: /etc/motd
    owner: root
    group: root
    mode: '0644'
  become: true

- name: Ensure app user
  user:
    name: app
    shell: /bin/bash
    create_home: true
  become: true
```

`roles/common/templates/motd.j2` :

```
{{ common_motd }}
Env: {{ app_env }}
```



`Playbook 04_hardening.yml` :

```yaml
- name: System baseline via common role
  hosts: all
  gather_facts: true
  become: yes
  roles:
  - role: common
```

`Exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/04_hardening.yml

PLAY [System baseline via common role] ****************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [common : Ensure common packages] ****************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [common : Set timezone] **************************************************************************************************************************************************************************************************************changed: [node1]
changed: [node2]

TASK [common : Deploy MOTD] ***************************************************************************************************************************************************************************************************************changed: [node1]
changed: [node2]

TASK [common : Ensure app user] ***********************************************************************************************************************************************************************************************************changed: [node2]
changed: [node1]

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

root@controller:/vagrant# 
```
---

## 📌 TP 4 — Handlers & Rôle `web` (Nginx)
- Creer un nouveau `Role web`:
```
root@controller:/vagrant# cd roles/
root@controller:/vagrant/roles#  ansible-galaxy role init web
Role web was created successfully
root@controller:/vagrant/roles# ls web/
README.md  defaults  files  handlers  meta  tasks  templates  tests  vars
root@controller:/vagrant/roles#
```
- `roles/web/defaults/main.yml` :
```yaml
nginx_listen_port: 8080
server_name: "{{ inventory_hostname }}"
```

- `roles/web/tasks/main.yml` : 
```yaml
- name: Install nginx
  package:
    name: nginx
    state: present
  become: true

- name: Push nginx.conf
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/sites-available/default
  notify: restart nginx
  become: true

- name: Place index.html
  copy:
    src: files/index.html
    dest: /var/www/html/index.html
  become: true

- name: Ensure nginx started
  service:
    name: nginx
    state: started
    enabled: true
  become: true
```

- Handler `roles/web/handlers/main.yml` :
```yaml
- name: restart nginx
  service:
    name: nginx
    state: restarted
  become: true
```

- `roles/web/templates/nginx.conf.j2 (minimal HTTP)` :
```
server {
  listen {{ nginx_listen_port }};
  server_name {{ server_name }};

  root /var/www/html;
  index index.html;

  location / {
    try_files $uri $uri/ =404;
  }
}
```

- `roles/web/files/index.html`
```
<h1>It works! Fil rouge Nginx</h1>
```
- `playbooks/05_web.yml` :
```yaml
- hosts: web
  gather_facts: false
  roles:
  - role: web
```

- `Execution`: 
```bash
root@controller:/vagrant# ansible-playbook playbooks/05_web.yml 

PLAY [web] ********************************************************************************************************************************************************************************************************************************
TASK [web : Install nginx] ****************************************************************************************************************************************************************************************************************changed: [node1]

TASK [web : Push nginx.conf] **************************************************************************************************************************************************************************************************************changed: [node1]

TASK [web : Place index.html] *************************************************************************************************************************************************************************************************************changed: [node1]

TASK [web : Ensure nginx started] *********************************************************************************************************************************************************************************************************ok: [node1]

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
---

- Acceder à votre serveur nginx via cette URL: http://192.168.56.111/

## 📌 TP 5 — Rôle `db` (MariaDB)
- Creer un nouveau `Role db`:
```
root@controller:/vagrant# ansible-galaxy role init roles/db
- Role roles/db was created successfully
root@controller:/vagrant# ls roles/
common  db  web
root@controller:/vagrant# ls roles/db/
README.md  defaults  files  handlers  meta  tasks  templates  tests  vars
root@controller:/vagrant# 
```
`roles/db/defaults/main.yml` :

```yaml
mariadb_bind_address: "0.0.0.0"
mariadb_root_password: "change-me"  # sera override par vars/vault.yml ou group_vars/db.yml
db_app_name: "appdb"
db_app_user: "appuser"
db_app_password: ""
db_app_host: "localhost"
```
`roles/db/tasks/main.yml` :
```yaml
- name: Install MariaDB
  ansible.builtin.package:
    name: mariadb-server
    state: present
  become: true

- name: Configure my.cnf
  ansible.builtin.template:
    src: my.cnf.j2
    dest: /etc/mysql/mariadb.conf.d/99-fil-rouge.cnf
  notify: restart mariadb
  become: true

- name: Ensure MariaDB running
  ansible.builtin.service:
    name: mariadb
    state: started
    enabled: true
  become: true

- name: Install PyMySQL (needed by community.mysql)
  ansible.builtin.package:
    name: python3-pymysql
    state: present
  become: true

- name: Set root password using unix_socket
  community.mysql.mysql_user:
    name: root
    host_all: true
    password: "{{ mariadb_root_password }}"
    login_unix_socket: /var/run/mysqld/mysqld.sock
    check_implicit_admin: true
    state: present
  become: true

- name: Ensure application database exists
  community.mysql.mysql_db:
    name: "{{ db_app_name }}"
    state: present
    login_user: root
    login_password: "{{ mariadb_root_password }}"
  become: true

- name: Ensure application user exists with password (from Vault)
  community.mysql.mysql_user:
    name: "{{ db_app_user }}"
    password: "{{ db_app_password }}"
    host: "{{ db_app_host }}"
    priv: "{{ db_app_name }}.*:ALL"
    state: present
    login_user: root
    login_password: "{{ mariadb_root_password }}"
  become: true
```

`roles/db/handlers/main.yml` :
```yaml
- name: restart mariadb
  ansible.builtin.service:
    name: mariadb
    state: restarted
  become: true
```

`roles/db/templates/my.cnf.j2` :
```yaml
[mysqld]
bind-address = {{ mariadb_bind_address }}
```

`playbooks/06_db.yml` :
```yaml
- hosts: db
  gather_facts: false
  vars_files:
    - ../vars/vault.yml
  roles:
    - db
```

- `Mettre les secrets DB dans le vault (chiffré) vars/vault.yml` : 
```yaml
mariadb_bind_address: "0.0.0.0"
# Secrets DB (exemple)
db_app_name: "appdb"            # nom de la base
db_app_user: "appuser"          # utilisateur applicatif
db_app_password: "Str0ngPass!"  # MOT DE PASSE EN CLAIR (chiffré par le vault au repos)
db_app_host: "localhost"             
# (optionnel) surcharger le root si tu préfères le mettre aussi dans Vault :
mariadb_root_password: "ChangeMeRoot"
```

```bash
ansible-vault create vars/vault.yml
```

- `Execution`: 
```bash
ansible-playbook playbooks/06_db.yml --ask-vault-pass
```

```bash
root@controller:/vagrant# ansible-playbook playbooks/06_db.yml --ask-vault-pass
Vault password: 

PLAY [db] *********************************************************************************************************************************************************************************************************************************
TASK [db : Install MariaDB] ***************************************************************************************************************************************************************************************************************changed: [node2]

TASK [db : Configure my.cnf] **************************************************************************************************************************************************************************************************************changed: [node2]

TASK [db : Ensure MariaDB running] ********************************************************************************************************************************************************************************************************changed: [node2]

TASK [db : Install PyMySQL (needed by community.mysql)] ***********************************************************************************************************************************************************************************changed: [node2]

TASK [db : Set root password using unix_socket] *******************************************************************************************************************************************************************************************[WARNING]: Option column_case_sensitive is not provided. The default is now false, so the column's name will be uppercased. The default will be changed to true in community.mysql 4.0.0.
changed: [node2]

TASK [db : Ensure application database exists] ********************************************************************************************************************************************************************************************changed: [node2]

TASK [db : Ensure application user exists with password (from Vault)] *********************************************************************************************************************************************************************changed: [node2]

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node2                      : ok=7    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
- Check DataBase:

```bash
vagrant@node2:~$ mysql -u root -h localhost -p
Enter password: 
Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MariaDB connection id is 52
Server version: 10.6.22-MariaDB-0ubuntu0.22.04.1 Ubuntu 22.04

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

MariaDB [(none)]> show databases;
+--------------------+
| Database           |
+--------------------+
| appdb              |
| information_schema |
| mysql              |
| performance_schema |
| sys                |
+--------------------+
5 rows in set (0.001 sec)

MariaDB [(none)]> quit
Bye
vagrant@node2:~$ mysql -u appuser -h localhost -p
Enter password: 
Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MariaDB connection id is 53
Server version: 10.6.22-MariaDB-0ubuntu0.22.04.1 Ubuntu 22.04

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

MariaDB [(none)]> show databases;
+--------------------+
| Database           |
+--------------------+
| appdb              |
| information_schema |
+--------------------+
2 rows in set (0.000 sec)

MariaDB [(none)]> 
```
---

## 📌 TP 6 — Orchestration complète (stack)

`playbooks/07_stack.yml`
```yaml
- name: Provision common baseline
  hosts: all
  gather_facts: true
  roles:
    - common
  tags: [baseline]

- name: Deploy DB
  hosts: db
  roles:
    - db
  tags: [db]

- name: Deploy Web
  hosts: web
  roles:
    - web
  tags: [web]

- name: Post-checks Serveur Web
  hosts: web
  gather_facts: false
  become: true
  tags: [post-ckeck-web]
  tasks:
    - name: Check HTTP
      ansible.builtin.uri:
        url: "http://{{ ansible_host }}:{{ nginx_listen_port }}/"
        return_content: true
      register: http
      failed_when: http.status not in [200] #failed_when Définit quand une tâche doit être considérée comme échouée
    - debug: var=http.status

- name: Post-check DB
  hosts: db
  become: true
  tags: [post-ckeck-db]
  vars:
    db_name: "{{ db_app_name }}"
    db_user: "{{ db_app_user }}"
    db_pass: "{{ db_app_password }}"          # vient du Vault
    db_host: "{{ db_app_host }}"
    db_port: 3306

  tasks:
    - name: Wait for DB TCP port
      ansible.builtin.wait_for:
        host: "{{ db_host }}"
        port: "{{ db_port }}"
        timeout: 30

    - name: Get DB server info (connectivity + auth)
      community.mysql.mysql_info:
        login_host: "{{ db_host }}"
        login_port: "{{ db_port }}"
        login_user: "root"
        login_password: "{{ mariadb_root_password }}"
        filter:
          - version
          - threads
      register: dbinfo

    - name: Assert we can connect and read server info
      ansible.builtin.assert: #une tâche dédiée à la validation
        that:
          - dbinfo.version is defined
        success_msg: "DB OK avec version: {{ dbinfo.version }}"
        fail_msg: "La DB n'est pas accessible ou version incorrecte"
        #ignore_errors: true

    - name: Vérifier que la base existe
      community.mysql.mysql_query:
        login_host: "{{ db_host }}"
        login_port: 3306
        login_user: "{{ db_user }}"
        login_password: "{{ db_pass }}"
        query: >
          SELECT COUNT(*) AS cnt
          FROM information_schema.SCHEMATA
          WHERE SCHEMA_NAME='{{ db_name }}';
      register: dbexists

    - name: Assert DB {{ db_name }} présente
      ansible.builtin.assert:
        that:
          - (dbexists.query_result[0][0].cnt | int) == 1
        success_msg: "DB {{ db_name }} est présente"
        fail_msg: "La base {{ db_name }} est absente"
```
`Exemples d’exécution` :

```bash
root@controller:/vagrant# ansible-playbook playbooks/07_stack.yml --ask-vault-pass
root@controller:/vagrant# ansible-playbook playbooks/07_stack.yml --ask-vault-pass  --tags post-ckeck-db
root@controller:/vagrant# ansible-playbook playbooks/07_stack.yml --ask-vault-pass  -e @inventories/dev/group_vars/db.yml --tags post-ckeck-web

Vault password: 

PLAY [Provision common baseline] **********************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [common : Ensure common packages] ****************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [common : Set timezone] **************************************************************************************************************************************************************************************************************ok: [node2]
ok: [node1]

TASK [common : Deploy MOTD] ***************************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

TASK [common : Ensure app user] ***********************************************************************************************************************************************************************************************************ok: [node1]
ok: [node2]

PLAY [Deploy DB] **************************************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]

TASK [db : Install MariaDB] ***************************************************************************************************************************************************************************************************************ok: [node2]

TASK [db : Configure my.cnf] **************************************************************************************************************************************************************************************************************ok: [node2]

TASK [db : Ensure MariaDB running] ********************************************************************************************************************************************************************************************************ok: [node2]

TASK [db : Install PyMySQL (needed by community.mysql)] ***********************************************************************************************************************************************************************************ok: [node2]

TASK [db : Ensure application database exists] ********************************************************************************************************************************************************************************************ok: [node2]

TASK [db : Ensure application user exists with password (from Vault)] *********************************************************************************************************************************************************************[WARNING]: Option column_case_sensitive is not provided. The default is now false, so the column's name will be uppercased. The default will be changed to true in community.mysql 4.0.0.
ok: [node2]

PLAY [Deploy Web] *************************************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node1]

TASK [web : Install nginx] ****************************************************************************************************************************************************************************************************************ok: [node1]

TASK [web : Push nginx.conf] **************************************************************************************************************************************************************************************************************ok: [node1]

TASK [web : Place index.html] *************************************************************************************************************************************************************************************************************ok: [node1]

TASK [web : Ensure nginx started] *********************************************************************************************************************************************************************************************************ok: [node1]

PLAY [Post-checks Serveur Web] ************************************************************************************************************************************************************************************************************
TASK [Check HTTP] *************************************************************************************************************************************************************************************************************************ok: [node1]

TASK [debug] ******************************************************************************************************************************************************************************************************************************ok: [node1] => 
  http.status: '200'

PLAY [Post-check DB] **********************************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]

TASK [Wait for DB TCP port] ***************************************************************************************************************************************************************************************************************ok: [node2]

TASK [Get DB server info (connectivity + auth)] *******************************************************************************************************************************************************************************************[WARNING]: filter element: threads is not allowable, ignored
ok: [node2]

TASK [Assert we can connect and read server info] *****************************************************************************************************************************************************************************************ok: [node2] => changed=false 
  msg: 'DB OK avec version: {''major'': 10, ''minor'': 6, ''release'': 22, ''suffix'': ''MariaDB-0ubuntu0'', ''full'': ''10.6.22-MariaDB-0ubuntu0.22.04.1''}'

TASK [Vérifier que la base existe] ********************************************************************************************************************************************************************************************************ok: [node2]

TASK [Assert DB appdb présente] ***********************************************************************************************************************************************************************************************************ok: [node2] => changed=false 
  msg: DB appdb est présente

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node1                      : ok=12   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=18   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

root@controller:/vagrant# 
```
- Exécution 2

```bash
root@controller:/vagrant# ansible-playbook playbooks/07_stack.yml --ask-vault-pass  -e @inventories/dev/group_vars/db.yml --tags post-ckeck-db
Vault password: 

PLAY [Provision common baseline] **********************************************************************************************************************************************************************************************************
PLAY [Deploy DB] **************************************************************************************************************************************************************************************************************************
PLAY [Deploy Web] *************************************************************************************************************************************************************************************************************************
PLAY [Post-checks Serveur Web] ************************************************************************************************************************************************************************************************************
PLAY [Post-check DB] **********************************************************************************************************************************************************************************************************************
TASK [Gathering Facts] ********************************************************************************************************************************************************************************************************************ok: [node2]

TASK [Wait for DB TCP port] ***************************************************************************************************************************************************************************************************************ok: [node2]

TASK [Get DB server info (connectivity + auth)] *******************************************************************************************************************************************************************************************[WARNING]: filter element: threads is not allowable, ignored
ok: [node2]

TASK [Assert we can connect and read server info] *****************************************************************************************************************************************************************************************ok: [node2] => changed=false 
  msg: 'DB OK avec version: {''major'': 10, ''minor'': 6, ''release'': 22, ''suffix'': ''MariaDB-0ubuntu0'', ''full'': ''10.6.22-MariaDB-0ubuntu0.22.04.1''}'

TASK [Vérifier que la base existe] ********************************************************************************************************************************************************************************************************ok: [node2]

TASK [Assert DB appdb présente] ***********************************************************************************************************************************************************************************************************ok: [node2] => changed=false 
  msg: DB appdb est présente

PLAY RECAP ********************************************************************************************************************************************************************************************************************************node2                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

root@controller:/vagrant# 
```
---

## 📌 TP 7 — AWX sur K3s (VM dédiée)

Créez une **VM unique** `awx` (4 Go RAM, 2 vCPU conseillés) qui installe **k3s** + **AWX Operator** + **AWX**.

```ruby
# Vagrantfile : VM unique "awx" qui installe k3s + AWX Operator + AWX (NodePort)
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "awx"
  config.vm.network "private_network", ip: "192.168.56.120"

  # Rendre le boot plus tolérant (Windows/VirtualBox)
  config.ssh.insert_key = false
  config.vm.boot_timeout = 600

  config.vm.provider "virtualbox" do |vb|
    vb.cpus = 2
    vb.memory = 4096
  end

config.vm.provision "shell", path: "provision-awx.sh"
end
```
```bash
#!/bin/bash
set -eux

# 1) Dépendances
echo "Install deps"
sudo apt-get update -y
sudo apt-get install -y curl git jq python3-pip
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 2) Installer k3s
echo "Install k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3) AWX Operator via Kustomize
echo "Deploy AWX Operator"
export AWX_OPERATOR_VERSION="2.19.1"

kubectl create ns awx || true
mkdir -p /root/awx
cd /root/awx

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}
namespace: awx
EOF

kubectl apply -k .

# attendre l'operator
echo "Waiting for awx-operator-controller-manager..."
for i in $(seq 1 60); do
  phase=$(kubectl -n awx get pods -l control-plane=controller-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
  [ "$phase" = "Running" ] && break
  sleep 5
done

# 4) Déployer AWX instance
echo "Deploy AWX instance"
cat > awx.yml <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: nodeport
  nodeport_port: 30080
EOF

kubectl apply -n awx -f awx.yml

# attendre awx pods
echo "Waiting for AWX pods..."
for i in $(seq 1 120); do
  ready=$(kubectl -n awx get pods -l app.kubernetes.io/name=awx -o jsonpath='{range .items[*]}{.status.phase}{" "}{end}' 2>/dev/null || true)
  echo "$ready" | grep -qE 'Running|Succeeded' && break
  sleep 5
done

# 5) Afficher mot de passe
echo "Admin password (user: admin):"
for i in $(seq 1 60); do
  if kubectl get secret awx-admin-password -n awx >/dev/null 2>&1; then
    kubectl get secret awx-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode; echo
    break
  fi
  sleep 5
done

# 6) Afficher service et URL
echo "Service AWX (NodePort):"
kubectl get svc -n awx | grep awx-service || true
NODEPORT=$(kubectl -n awx get svc awx-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 30080)
echo "Accès UI : http://192.168.56.120:${NODEPORT}"
```
**Deployer AWX :**
```bash
C:\Users\Administrateur\awx-lab>vagrant.exe up
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'ubuntu/jammy64'...
==> default: Matching MAC address for NAT networking...
==> default: Checking if box 'ubuntu/jammy64' version '20241002.0.0' is up to date...
==> default: Setting the name of the VM: awx-lab_default_1759179288508_29706
==> default: Fixed port collision for 22 => 2222. Now on port 2202.
==> default: Clearing any previously set network interfaces...
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
    default: Adapter 2: hostonly
==> default: Forwarding ports...
    default: 22 (guest) => 2202 (host) (adapter 1)
==> default: Running 'pre-boot' VM customizations...
==> default: Booting VM...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:2202
    default: SSH username: vagrant
    default: SSH auth method: private key
==> default: Machine booted and ready!
==> default: Checking for guest additions in VM...
    default: The guest additions on this VM do not match the installed version of
    default: VirtualBox! In most cases this is fine, but in rare cases it can
    default: prevent things such as shared folders from working properly. If you see
    default: shared folder errors, please make sure the guest additions within the
    default: virtual machine match the version of VirtualBox you have installed on
    default: your host and reload your VM.
......................
 default: + curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    default:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
    default:                                  Dload  Upload   Total   Spent    Left  Speed
100 11913  100 11913    0     0  36954      0 --:--:-- --:--:-- --:--:-- 36996
    default: Downloading https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz
    default: Verifying checksum... Done.
    default: Preparing to install helm into /usr/local/bin
    default: helm installed into /usr/local/bin/helm
    default: Install k3s
    default: + echo 'Install k3s'
    default: + curl -sfL https://get.k3s.io
    default: + sh -s - --write-kubeconfig-mode 644
    default: [INFO]  Finding release for channel stable
    default: [INFO]  Using v1.33.4+k3s1 as release
    default: [INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.33.4+k3s1/sha256sum-amd64.txt
    default: [INFO]  Downloading binary https://github.com/k3s-io/k3s/releases/download/v1.33.4+k3s1/k3s
    default: [INFO]  Verifying binary download
    default: [INFO]  Installing k3s to /usr/local/bin/k3s
    default: [INFO]  Skipping installation of SELinux RPM
    default: [INFO]  Creating /usr/local/bin/kubectl symlink to k3s
    default: [INFO]  Creating /usr/local/bin/crictl symlink to k3s
    default: [INFO]  Creating /usr/local/bin/ctr symlink to k3s
    default: [INFO]  Creating killall script /usr/local/bin/k3s-killall.sh
    default: [INFO]  Creating uninstall script /usr/local/bin/k3s-uninstall.sh
    default: [INFO]  env: Creating environment file /etc/systemd/system/k3s.service.env
    default: [INFO]  systemd: Creating service file /etc/systemd/system/k3s.service
    default: [INFO]  systemd: Enabling k3s unit
    default: Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
    default: [INFO]  systemd: Starting k3s
    default: Deploy AWX Operator
    default: + export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    default: + KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    default: + echo 'Deploy AWX Operator'
    default: + export AWX_OPERATOR_VERSION=2.19.1
    default: + AWX_OPERATOR_VERSION=2.19.1
    default: + kubectl create ns awx
    default: namespace/awx created
    default: + mkdir -p /root/awx
    default: + cd /root/awx
    default: + cat
    default: + kubectl apply -k .
    default: Warning: resource namespaces/awx is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
    default: namespace/awx configured
    default: customresourcedefinition.apiextensions.k8s.io/awxbackups.awx.ansible.com created
    default: customresourcedefinition.apiextensions.k8s.io/awxmeshingresses.awx.ansible.com created
    default: customresourcedefinition.apiextensions.k8s.io/awxrestores.awx.ansible.com created
    default: customresourcedefinition.apiextensions.k8s.io/awxs.awx.ansible.com created
    default: serviceaccount/awx-operator-controller-manager created
    default: role.rbac.authorization.k8s.io/awx-operator-awx-manager-role created
    default: role.rbac.authorization.k8s.io/awx-operator-leader-election-role created
    default: clusterrole.rbac.authorization.k8s.io/awx-operator-metrics-reader created
    default: clusterrole.rbac.authorization.k8s.io/awx-operator-proxy-role created
    default: rolebinding.rbac.authorization.k8s.io/awx-operator-awx-manager-rolebinding created
    default: rolebinding.rbac.authorization.k8s.io/awx-operator-leader-election-rolebinding created
    default: clusterrolebinding.rbac.authorization.k8s.io/awx-operator-proxy-rolebinding created
    default: configmap/awx-operator-awx-manager-config created
    default: service/awx-operator-controller-manager-metrics-service created
    default: deployment.apps/awx-operator-controller-manager created
    default: Waiting for awx-operator-controller-manager...
    default: + echo 'Waiting for awx-operator-controller-manager...'
    default: ++ seq 1 60
    default: + for i in $(seq 1 60)
    default: ++ kubectl -n awx get pods -l control-plane=controller-manager -o 'jsonpath={.items[0].status.phase}'
    default: ++ true
    default: + phase=
    default: + '[' '' = Running ']'
    default: + sleep 5
    default: + for i in $(seq 1 60)
    default: ++ kubectl -n awx get pods -l control-plane=controller-manager -o 'jsonpath={.items[0].status.phase}'
    default: + phase=Pending
    default: + '[' Pending = Running ']'
................
default: + sleep 5
    default: + for i in $(seq 1 60)
    default: ++ kubectl -n awx get pods -l control-plane=controller-manager -o 'jsonpath={.items[0].status.phase}'
    default: Deploy AWX instance
    default: + phase=Running
    default: + '[' Running = Running ']'
    default: + break
    default: + echo 'Deploy AWX instance'
    default: + cat
    default: + kubectl apply -n awx -f awx.yml
    default: awx.awx.ansible.com/awx created
    default: Waiting for AWX pods...
    default: + echo 'Waiting for AWX pods...'
    default: ++ seq 1 120
    default: + for i in $(seq 1 120)
    default: ++ kubectl -n awx get pods -l app.kubernetes.io/name=awx -o 'jsonpath={range .items[*]}{.status.phase}{" "}{end}'
    default: + ready=
    default: + grep -qE 'Running|Succeeded'
    default: + echo ''
    default: + sleep 5
    default: + for i in $(seq 1 120)
    default: ++ kubectl -n awx get pods -l app.kubernetes.io/name=awx -o 'jsonpath={range .items[*]}{.status.phase}{" "}{end}'
    default: + ready=
    default: + echo ''
    default: + grep -qE 'Running|Succeeded'
    default: + sleep 5
..................
 default: Admin password (user: admin):
    default: + echo 'Admin password (user: admin):'
    default: ++ seq 1 60
    default: + for i in $(seq 1 60)
    default: + kubectl get secret awx-admin-password -n awx
    default: + kubectl get secret awx-admin-password -n awx -o 'jsonpath={.data.password}'
    default: + base64 --decode
    default: t7rMrf5DqLzBPmpURGhBglLL8EnJzYxA
    default: Service AWX (NodePort):
    default: + echo
    default: + break
    default: + echo 'Service AWX (NodePort):'
    default: + kubectl get svc -n awx
    default: + grep awx-service
    default: awx-service                                       NodePort    10.43.159.59   <none>        80:30080/TCP   9m12s
    default: ++ kubectl -n awx get svc awx-service -o 'jsonpath={.spec.ports[0].nodePort}'
    default: Accès UI : http://192.168.56.120:30080
    default: + NODEPORT=30080
    default: + echo 'Accès UI : http://192.168.56.120:30080'
```
**Accès AWX :**
```bash
http://192.168.56.120:30080
# user: admin password: t7rMrf5DqLzBPmpURGhBglLL8EnJzYxA
```
**AWX Instance:**
Voilà un schéma clair du flux AWX :

- AWX Web/API (UI + REST) : interface et API.
- AWX Task : planifie/orchestre les jobs, déclenche les EE pods (runners), suit l’exécution et les logs.
- PostgreSQL : base de données d’AWX (projets, inventaires, jobs, résultats…).
- EE pods (runners) : pods éphémères lancés par job avec l’image Execution Environment (ansible-core + collections). Ils exécutent les playbooks.
- Targets/Nodes : les hôtes gérés (node1, node2…), contactés en SSH/WinRM/API par les EE pods.

**Dans l’UI AWX :**
1. **Projects** → connecter votre repo Git (contenant ce TP)  
2. **Credentials** → clé SSH (celle qui accède à node1/node2)  
3. **Inventories** → créer `DEV` avec `node1` et `node2`  
4. **Job Templates** → `playbooks/07_stack.yml` → Launch  
5. Vérifier l’**idempotence** (relancer sans changements)

---
