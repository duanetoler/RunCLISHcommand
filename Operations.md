# Playbook Operation

The playbook does some crafty trickery with the list of targets provided
with ```-l``` and when working with VSX Virtual Systems.  The first play in
the playbook will build a new dynamic inventory of play hosts.

The first task in this play parses the value of ```-l``` (the internal
variable ```targets```).  If the target is a group, it will expand that
group to its list of hosts and add to a new list variable
```targets_list```.

The second task loops through the comma-separated value of ```-l```,
concatenated with the above ```targets_list``` list variable, or default to
a null list.  If the item is a host in the specified inventory, and the
inventory host does not have the variable ```vsx_host```, then it is also
added to a new dynamic group ```new_play_hosts```.

The third task loops through the same list as the second task, but instead
checking if the variable ```vsx_host``` is defined for that inventory host
(meaning this target is a VSX VS, the logical host with ```vs_id``` and
```vs_host```).

If this is a VS with ```vsx_host``` defined, an inner task is processed that
loops through the inventory group named by the value of ```vsx_host``` (the
VSX cluster group: ```hostvars[VS]['vsx_host']```) to expand that list of
VSX gateways for this VS (```groups[vsx_host]```) (hang on and you'll see why).

If ```vsx_host``` is a single gateway, however, this is returned as a 1-item
list for an second-level interior loop but the processing is the same.

The second-level loop cycles through all inventory hosts in the VSX cluster
group ("{{ groups[vsx_host] }}") and builds a new list named ```vs_list```,
which contains the list of all virtual systems requested in the ```-l```
targets, for the VSX gateway host.  This is an orthogonal list compared with
the inventory.

For example:

```sh
./run_clish_command.sh -l VS01,VS09 -c "show route exact 0.0.0.0/0"
```

The VS01 and VS09 may be hosted on VSX_Cluster01, but VSX_Cluster01 has 42
virtual systems.  Only VS01 and VS09 are the ones we care about.

A new list fact is created dynamically such that:

```yaml
VSX_Cluster01:
  hosts:
    vsx_gw01:
    vsx_gw02:
    vsx_gw03:
  vars:
    vs_list:  ## This is created dynamically
      - VS01
      - VS09
```

This lets the playbook remain targeting VS01 and VS09, even though
the tasks will later be used as ```delegate_to: vsx_gw01``` and
```delegate_to: vsx_gw02```, etc.

### Why?

This allows the plays to run in serial fashion for a VS, but in parallel
fashion for all gateways of the VS.  I ran this playbook in the original
design, but that ended up being serial execution for all targets, which was
VERY slow.  When I switched to this dynamic orthogonal technique, the tasks
were much faster and operated as you would expect.

When mixing VS and non-VS targets, the non-VS targets will go first and run
in parallel execution as Ansible normally does.  The VS targets run second
and they run sequentially per-VS (because they are in a loop from the
dynamically-built ```targets_list``` with a ```when:``` clause), but their
delegation to the VSX gateway is in parallel.

```
TASK [Parse output] ********************************************************************************
ok: [rtp-gw3]
ok: [rtp-gw1]
ok: [rtp-gw2]

TASK [Show command output] *************************************************************************
ok: [rtp-gw1] => {
    "msg": [
        "Virtual System: rtp-VS-FW, VS ID: 6",
        [
            "Flags: R - Peer restarted, W - Waiting for End-Of-RIB from Peer",
            "",
            "PeerID         AS      Routes  ActRts  State             InUpds  OutUpds  Uptime    ",
            "10.0.0.2       65505   0       0       Idle              0       0        00:00:00  ",
            "10.0.0.3       65505   0       0       Idle              0       0        00:00:00  ",
            "192.0.2.6      65506   0       0       Idle              0       0        00:00:00  ",
            "192.0.2.7      65506   0       0       Idle              0       0        00:00:00  "
        ]
    ]
}
ok: [rtp-gw3] => {
    "msg": [
        "Virtual System: rtp-VS-FW, VS ID: 6",
        [
            "Flags: R - Peer restarted, W - Waiting for End-Of-RIB from Peer",
            "",   
            "PeerID         AS     Routes  ActRts  State             InUpds  OutUpds  Uptime    ",
            "10.0.0.2       65505  2390    2382    Established       10975   1        1w1d      ",
            "10.0.0.3       65505  2390    7       Established       11008   1        1w1d      ",
            "192.0.2.6      65506  0       0       Active            0       0        00:00:00  ",
            "192.0.2.7      65506  0       0       Active            0       0        00:00:00  "
        ]
    ]
}
ok: [rtp-gw2] => {
    "msg": [
        "Virtual System: rtp-VS-FW, VS ID: 6",
        [
            "Flags: R - Peer restarted, W - Waiting for End-Of-RIB from Peer",
            "",
            "PeerID         AS     Routes  ActRts  State             InUpds  OutUpds  Uptime    ",
            "10.0.0.2       65505  0       0       Idle              0       0        00:00:00  ",
            "10.0.0.3       65505  0       0       Idle              0       0        00:00:00  ",
            "192.0.2.6      65506  0       0       Idle              0       0        00:00:00  ",
            "192.0.2.7      65506  0       0       Idle              0       0        00:00:00  "
        ]
    ]
}
```

## CLISH scripts and templates

The core tasks are done in clish_script_build.yml.  A Jinja2 template is
used to create the CLISH script in a local directory on the Ansible
controller.  Several Gaia API calls are used to create a directory on the
remote host, transfer the file with Gaia Ansible module put_file, and
execute the script on the remote host with Gaia Ansible module run_script.

After execution, the script is removed from the remote host and the local
copy on the Ansible controller (assuming ```keep_script``` is false).

THe output of the script execution can be shown during the playbook
operation, and/or saved to a file on the Ansible controller, or neither
(most "set" and "delete" commands generally don't return output anyway;
although some exceptions exist).

At certain points, the CLISH database lock needs to be obtained.  This
occurs in the included task list ```clish_lock.yml```.  This uses run_script
Gaia Ansible module to do a ```clish -c 'lock database override'``` and ```clish
-c 'unlock database'```.  This isn't super perfect, but it tends to work
well enough.
