# Gaia CLISH Command via Ansible

This Ansible playbook will execute arbitrary commands on any Check Point
Gaia host or VSX Virtual System.

## Requirements

* Check Point Gaia host with Gaia API v1.3+
* Ansible 2.12+
* [Check Point Gaia Ansible modules](https://github.com/CheckPointSW/CheckPointAnsibleGAIACollection)

## Installation instructions

1. Clone git repo:

```
git clone https://github.com/duanetoler/run_clish_command.git
```

2. Configure inventory.  A sample inventory is provided in
```inventory.yml``` as a guide.

3. Run ```run_clish_command.sh``` script:

```sh
./run_clish_command.sh -c "show configuration"
```

## Usage

```
Usage: run_clish_command.sh [ -l <list of targets> ] [ -i inventory ] [ -h ] [-c <command>]

    i   Specify an inventory (optional; default to inventory.yml in local dir)
    k   Keep the generated script on both Ansible controller and remote host; default is to remove scripts
    l   List of targets, comma-separated; defaults to all hosts
    s   Save output to clish_output/ directory
    c   CLISH command to run; default: "show hostname"
    u   Optional Gaia admin user name, if you need to override inventory or vars.yml

    I   ignore errors from CLISH; default is to fail if CLISH returns non-zero result
        This is useful if you're trying to compare hosts with mismatched configs, like VSX gateways
    O   Do NOT show output on console (default is to show output); recommended to use with -s
    P   Prompt for Ansible vault passphrase (this is NOT the gaia admin user password)
    h   This help
```

An alternate inventory can be provided with ```-i``` argument rather than
the default inventory.yml in the playbook directory.

By default, the playbook will show output of the CLISH commands and not save
anything locally.

Any valid Ansible target list can be provided with ```-l```, including
groups, hosts, and comma-separated lists of targets.

A default command "show hostname" is used if ```-c``` is not provided.  Any
valid CLISH command can be used, not just "show" commands.

```sh
./run_clish_command.sh -i /etc/ansible/inventory.yml -l gw01,gw02 -c 'set static-route
default nexthop gateway address 192.0.2.1 on'

./run_clish_command.sh -i /etc/ansible/inventory.yml -c 'show route static'

./run_clish_command.sh -i /etc/ansible/inventory.yml -l
mgmt01,office-fw -c 'set snmp agent on'

# show configuration, don't show output, use a different username, assuming
# it's encrypted with ansible-vault, prompt for vault passphrase
./run_clish_command.sh -i /etc/ansible/inventory.yml -l
mgmt01,office-fw,VS01 -c 'show configuration' -s -O -u jr_admin -P
```

However, be wary of trying to send values with special characters and
quotes.  This is a Bash script, and rules of interpolation apply.  You have
been warned.

## Inventory

Your inventory can be constructed however you wish, with an exception for
VSX virtual systems (if any).  Variables for usernames/passwords have a
special provision (see "Authentication" below).

1. Hosts (management, gateways and cluster members, VSX gateways and
cluster members):

All hosts can be defined and grouped into any order you wish.  You may
apply variables in the inventory file or in the group_vars and host_vars
directories.

2. Gateway clusters and VSX clusters

Gateway clusters should be defined as a logical group, with each of the
cluster members defined as child hosts of the group.  This is required for
VSX clusters:

```yaml
---
all:
  children:
    rtp_cluster01:
      hosts:
        rtpfw01:
          ansible_host: 192.0.2.17 # Or define in host_vars/rtpfw01/vars.yml
        rtpfw02:
          ansible_host: 192.0.2.18 # Or define in host_vars/rtpfw02/vars.yml
    vsx_cluster01:
      hosts:
        vsx_gw01:
          ansible_host: 192.0.2.1 # Or define in host_vars/vsx_gw01/vars.yml
        vsx_gw02:
          ansible_host: 192.0.2.2 # Or define in host_vars/vsx_gw02/vars.yml
    vsx_single_gw:  # a single non-cluster VSX gateway
      ansible_host: 192.0.2.33
...
```

3. VSX Virtual Systems

Each VSX VS must be defined as a host.  These hosts get two variables applied:
* vs_id: the virtual system ID number
* vsx_host: the name of the VSX cluster group (or single VSX gateway host)

```yaml
---
all:
  children:
    vsx_vs:
      hosts:
        VS01:
          vs_id: 5
          vsx_host: vsx_cluster01
        VS02:
          vs_id: 10
          vsx_host: vsx_single_gw
...
```

A VSX VS doesn't need to have any authentication mechanisms; it's not a real
host anyway.  The ```vsx_host``` variable determines what underlying host is to
be used for the VS (via delegate_to:).  The playbook will figure out how to get
there.

I still make a host_vars/VS_NAME/vars.yml with those two variables, for
consistency with my other variables.  I also have many other definitions in
the VS-specific inventory directory for other uses.  You can also make a
logical group of virtual systems if you wish, and use that as the parameter
to ```-l ...```.

4. Ansible HTTPAPI plugin variables

Somewhere in your inventory, at some level, these Ansible HTTPAPI plugin
variables need to be defined:

```yaml
---
ansible_httpapi_validate_certs: false
ansible_httpapi_use_ssl: true
ansible_httpapi_port: "{{ gaia_api_port |default(443) }}"
...
```

You can override the default Gaia API port elsewhere in your inventory
for the Gaia host, with the variable ```gaia_api_port```.  You can put
this variable on VSX gateway host_vars, or the cluster group_vars, or any
other group_vars you have.  You can define it in the playbook vars as well. 
The default will be 443 if not defined.

This playbook has vars.yml included and the ```ansible_network_os```
variable is defined as ```check_point.gaia.checkpoint```.  You can move this
to anywhere else in your inventory for Gaia API connections.  Be careful not
to cause a conflict with the Mgmt API definition
```check_point.mgmt.checkpoint```.  I usually forego defining
```ansible_network_os``` in inventory and instead define it per-play for
this reason.

## Authentication

Authentication to Gaia API needs two variables (obviously):
* ansible_user
* ansible_password

The vars.yml for this playbook contains these two variables, but you can
place them anywhere else in your inventory.  However, you will be better
served by using a level of indirection, which also helps keep vaulted
variables safe.

1. ```ansible_user``` with ```gaia_admin_user```

The variable ```gaia_admin_user``` can be defined anywhere in the inventory,
and should be a user with access to the host via Gaia API and CLISH (not an
Expert-equivalent user).  In the play vars (or vars_files), define
```ansible_user```, referencing ```gaia_admin_user```, and default to
'admin' if not present.  This playbook includes vars.yml with this
indirection.  This allows you to (re)define ```gaia_admin_user``` at any
level you wish without having to globally override ```ansible_user```.

```yaml
ansible_user: "{{ gaia_admin_user |default('admin') }}"
```

2. ```ansible_password``` with ```gaia_admin_password```

The variable ```gaia_admin_password``` can be defined in any number of ways,
depending on your preference and security needs.  This can be defined as a
plain text string in the play vars (or vars_files), but this is rarely
desirable.  Instead, I provide an option in vars.yml to use a vaulted
variable in another location (such as the inventory).  This indirection
allows you to (re)define ```gaia_admin_password``` at any level without also
globally overriding ```ansible_password```.

```yaml
ansible_password: "{{ gaia_admin_password |default(clish_users_vault[ansible_user]) }}"
```

The vaulted variable name is ```clish_users_vault``` and is dict type.  The
keys of the dict are the CLISH user names (admin, your-user, etc.).  The
values of each key are the plain text passwords.  The entire file is
encrypted with ansible-vault.

```ansible_password``` can use ```gaia_admin_password``` for an immediate
override or default to a key lookukp in ```clish_users_vault[ansible_user]```
otherwise.  This playbook includes vars.yml with this indirection as well.

This example uses the implicit 'all' group, but this should be somewhere
more appropriate for your inventory.

* group_vars/all/clish_users_vault.yml:

```yaml
---
clish_users_vault:
  admin:  'adminpassword',
  myuser: 'mypassword123'
...
```

Encrypt the whole file:
```sh
ansible-vault encrypt --vault-id VAULT_NAME --ask-vault-pass clish_users_vault.yml
```

## Docker

This will run under Docker as well.  You will need to modify the script,
however, to include your Docker runtime, volume mapping, and other arguments. 
Likewise, you may need to modify the paths to the playbook and inventory to
be relative to your Docker runtime.  I run this similar command to run this
on other hosts via Docker:

```sh
docker run \
  -v PLAYBOOK_DIR:DOCKER_MAPPING \
  -w /CONTAINER \
  -it --rm \
  DOCKER/CONTAINER \
  ansible-playbook \
    -i ${inventory} \
    ... \
    /CONTAINER/run_clish_command/run_clish_command.yml \
    ...
    
```

## Licensing

GNU General Public License v3.0 or later.

See [COPYING](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.

# Support

In case of any issue or a bug(!!  gasp!), please open an
[issue](https://github.com/duanetoler/run_clish_command/issues) or [send me
an email ](mailto:dtoler@webfargo.com).  For best results, please use a
[gist](https://gist.github.com) to send any output examples of your issue
(clearing any sensitive bits, of course).

