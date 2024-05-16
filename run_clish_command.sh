#!/bin/bash

save_output=0
show_output=1
vault_pass_prompt=0
clish_cmd="'show hostname'"

print_usage() {
  cat - <<EOF
Run arbitrary CLISH command on Check Point hosts and VSX Virtual Systems

Usage: $0 [ -l <list of targets> ] [ -i inventory ] [ -h ] [-c <command>]

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


EOF
}

while getopts c:skl:hIi:u:OP Opt; do
  case $Opt in
    h)
      print_usage
      exit 1
    ;;

    i)
      inventory=${OPTARG}
    ;;

    l)
      targets=${OPTARG}
    ;;

    I)
      ignore_errors=1
    ;;

    k)
      keep_script=1
    ;;

    s)
      save_output=1
    ;;

    O)
      show_output=0
    ;;

    P)
      vault_pass_prompt=1
    ;;

    c)
      clish_cmd="'${OPTARG}'"
    ;;

    u)
      gaia_admin_user="${OPTARG}"
    ;;
  esac
done

if [ -z "${inventory}" ]; then
  inventory=inventory.yml
fi

# Make output directory
rm -rf clish_output
install -d -m 0755 clish_output/

ansible-playbook \
  -i ${inventory} \
  $( (( "${vault_pass_prompt}" )) && echo "--ask-vault-pass" ) \
  $( (( "${keep_script}" )) && echo "-e keep_script=true" ) \
  $( [ -n "${gaia_admin_user}" ] && echo "-e gaia_admin_user=${gaia_admin_user}" ) \
  run_clish_command.yml \
  -e targets=${targets:-all} \
  -e show_output=${show_output} \
  -e save_output=${save_output} \
  -e errors_ignored=${ignore_errors} \
  -e clish_cmd="${clish_cmd}"

RET=$?

if (( $RET )); then
  echo "Error ${RET} from ansible-playbook"
  exit ${RET}
fi
