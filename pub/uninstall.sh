#!/bin/bash

# uninstall.sh
#
# Undo environment setup (install required packages)
# and Lima instance configuration.
#
# Most actions remove files which the user might be using
# for other reasons, so they are prompted before removal.
#
# Run using the command:
#   curl 'https://raw.githubusercontent.com/jeffreyalanwang/ITSC_3146_Lima/refs/heads/main/pub/uninstall.sh' | bash
#
# Alternatively, download this file, change permissions, then run:
#   chmod +x $FILE
#   bash $FILE

instance_name="ITSC-3146"

# Returns 0 if the command specified with $1 was found in $PATH.
command_available() {
    /usr/bin/env which -s "$1"
}

# Returns 0 if the user agrees to the prompt specified with $1.
prompt() {
    local prompt; prompt="$1"
    
    printf '%s [y/n] ' "$prompt"
    local answer; read -r answer

    if [ "$answer" != "${answer#[Yy]}" ]; then 
        return 0
    else
        return 1
    fi
}

# Each element of this array is one string instructing the user to
# uninstall something that we can't programatically remove for them
user_uninstalls=( )

undo_environment_setup() {
    export NONINTERACTIVE=1

    # Remove lima if user wants
    if (command_available "limactl") && (
        [[ $remove_lima == "true" ]] || prompt "Do you want to uninstall Lima?"
    ); then
        brew uninstall lima
    fi

    # Remove xquartz if user wants
    if prompt "Do you want to uninstall XQuartz?"; then
        brew uninstall xquartz ||
            user_uninstalls+=("Uninstall XQuartz")
    fi

    # Remove vscode if user wants
    if prompt "Do you want to uninstall VS Code?"; then
        brew uninstall visual-studio-code ||
            user_uninstalls+=("Uninstall Visual Studio Code")
    fi

    # Remove homebrew if user wants
    if (command_available "brew") && prompt "Do you want to uninstall Homebrew?"; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" ||
            user_uninstalls+=("Uninstall Homebrew")
    fi

}

undo_install_instance() {

    # start-at-login
    limactl start-at-login --tty=false ${instance_name} --enabled false

    # macOS Terminal profile
    user_uninstalls+=("Uninstall Terminal profile: open Terminal -> settings -> ${INSTANCE_NAME} -> '-'")

    # SSH hosts config
    local ssh_hosts_file; ssh_hosts_file="${HOME}/.ssh/config"
    if [[ -f "$ssh_hosts_file" ]] && ( grep -q '^Include ~/.lima' "$ssh_hosts_file" ) &&
        prompt "Do you want to remove Lima SSH/VS Code config?"
    then
        echo "Attempting to remove instance SSH config from $ssh_hosts_file..."
        
        local line1; line1='# Lima instances';
        local line2; line2="# (this line created by ${instance_name} setup.sh)"
        local line3; line3='Include ~/.lima/*/ssh.config'

        local n2 # Line num in document, of line 2/3 to remove
        n2="$(
                cat "$ssh_hosts_file"   |
                grep -n "$line2"        |
                awk '{print $1}' FS=":"
            )"
        local n1; n1=$(( n2 - 1 ))
        local n3; n3=$(( n2 + 1 ))

        # If there is exactly one instance of line2,
        # and it is accompanied by expected line1 and line3,
        # remove automatically.
        # Otherwise, let the user remove it.
        if  [[ $( echo "$n2" | wc -l ) == 1 ]]      &&
            (  sed -n "${n1}p" |
                grep "$line1" >/dev/null        )   &&
            (  sed -n "${n3}p" |
                grep "$line3" >/dev/null        )
        then
            sed -i "${n1},${n3}d" "$ssh_hosts_file"
            echo "Successfully removed."
        else
            echo "Could not automatically remove."
            user_uninstalls+=("Remove Lima SSH hosts: $ nano ~/.ssh/config")
        fi
    fi

    limactl stop ${instance_name}
    limactl delete ${instance_name}
    
    lima_data_dir=${LIMA_HOME}
    if prompt "Do you want to completely remove Lima (including data and config in $lima_data_dir)?"; then
        remove_lima="true" # global
        echo "Deleting $lima_data_dir..."
        rm "$lima_data_dir"
    fi
}

undo_install_instance
undo_environment_setup

echo
echo 'The following items cannot be uninstalled within this script.'
echo 'Follow the instructions below to remove them yourself.'
echo '--'
printf '%s\n' "${user_uninstalls[@]}"
