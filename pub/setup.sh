#!/bin/bash
set -e -o pipefail

# setup.sh
#
# Environment setup (install required packages) and Lima instance
# configuration.
# Other files in this repository are automatically downloaded
# and provided where they are needed, using curl or limayaml's
# ability to retrieve file contents from a URL.
#
# Run using the command:
#   curl 'https://raw.githubusercontent.com/jeffreyalanwang/ITSC_3146_Lima/refs/heads/main/pub/ITSC-3146.yaml' | bash
#
# Alternatively, download this file, change permissions, then run:
#   chmod +x $FILE
#   bash $FILE

instance_name="ITSC-3146"
# repo_url="/Users/ravirtualenvtest/Code/ITSC_3146_Lima"
repo_url="https://raw.githubusercontent.com/jeffreyalanwang/ITSC_3146_Lima/refs/heads/main"

# Returns 0 if the command specified with $? was found in $PATH.
command_available() {
    /usr/bin/env which -s $1
}

environment_setup() {
    export NONINTERACTIVE=1

    # Install homebrew, if not present
    if ! (command_available "brew"); then
        echo "Installing homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo "Homebrew found at $(which "brew")."
    fi

    # Install xquartz, if not present
    if ! (command_available "xquartz"); then
    echo "Installing xquartz..."
        brew install --cask xquartz
    else
        echo "XQuartz found at $(which "xquartz")."
    fi

    # Install lima, if not present
    if ! (command_available "lima"); then
        echo "Installing lima..."
        brew install lima
    else
        echo "Lima found at $(which "lima")."
    fi

    # Install vscode, if not present
    if ! (command_available "code") && ! (ls "/Applications/" | grep -q "Visual Studio Code"); then
        echo "Installing Visual Studio Code..."
        brew install --cask visual-studio-code
    else
        echo "Visual Studio Code found at $(which "code" || echo "/Applications/")."
    fi

    echo "Completed successfully."
}

install_instance() {
    # make sure xquartz is running
    if [[ -z "$DISPLAY" ]]; then
        {
            # Ask launchctl to start a socket for xquartz;
            # xquartz is autostarted when this socket is connected to.
            launchctl bootstrap "gui/$(id -u)" /Library/LaunchAgents/org.xquartz.startx.plist
            # Because launchctl output is subject to change,
            # this is our best option to extract the socket path
            DISPLAY="$(
                launchctl print "gui/$(id -u)/org.xquartz.startx" | 
                grep -o '/private/tmp/.*/org.xquartz:0' | head -n 1
            )"
        } || {
            # If any of the above returned with error,
            # use the trusty /tmp/.X11-unix/X0 socket
            # (which does not auto-start xquartz when connected to)
            xquartz &
            DISPLAY=':0'
        }
    fi
    echo 'Providing Lima the $DISPLAY value of: '"${DISPLAY}"
    export DISPLAY

    # create instance
    echo "Create Lima instance ${instance_name}..."
    limactl create --tty=false "${repo_url}/pub/${instance_name}.yaml"

    # start instance
    #
    # When setting up macOS Terminal profile, we open a Lima
    # shell; the open command means that the new Terminal 
    # window is not a child of this one.
    # By performing startup in advance, we use the environment
    # variables from this shell instead.)
    limactl start "${instance_name}"

    # configure host SSH
    echo "Adding instance SSH config to ~/.ssh/config..."
    mkdir -p ~/.ssh
    if [[ ! -f ~/.ssh/config ]] || ( ! grep -q '^Include ~/.lima' ~/.ssh/config ); then
        echo '' >> ~/.ssh/config # newline
        {
            echo '# Lima instances'
            echo "# (this line created by ${instance_name} setup.sh)"
            echo 'Include ~/.lima/*/ssh.config' >> ~/.ssh/config
        } >> ~/.ssh/config
    fi

    # configure macOS Terminal + open for user to setup password
    echo "Adding instance as a profile in Terminal app..."
    {   
        curl "${repo_url}/pub/profile.terminal" ||
        cat "${repo_url}/pub/profile.terminal" # if we're using a local path
    }   |
        sed "s|LIMACTL_EXECUTABLE|$(which limactl)|g" \
        > "$HOME/Downloads/${instance_name}.terminal"
    open "$HOME/Downloads/${instance_name}.terminal"
}

environment_setup
install_instance