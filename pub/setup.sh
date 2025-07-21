#!/bin/bash
set -e -o pipefail

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
    # create image
    echo "Create Lima instance ${instance_name}..."
    limactl create --tty=false "${repo_url}/pub/${instance_name}.yaml"

    # configure host SSH
    echo "Adding instance SSH config to ~/.ssh/config..."
    mkdir -p ~/.ssh
    if [[ -f ~/.ssh/config ]] && ( ! grep -q '^Include ~/.lima' -f ~/.ssh/config ); then
        echo '' >> ~/.ssh/config # newline
        echo '# Lima instances' >> ~/.ssh/config
        echo "# (this line created by ${instance_name} setup.sh)" >> ~/.ssh/config
        echo 'Include ~/.lima/*/ssh.config' >> ~/.ssh/config
    fi

    # configure macOS Terminal
    echo "Adding instance as a profile in Terminal app..."
    {   curl "${repo_url}/pub/profile.terminal" ||
        cat "${repo_url}/pub/profile.terminal" # if we're using a local path
    } > "$HOME/Downloads/${instance_name}.terminal"
    open "$HOME/Downloads/${instance_name}.terminal"
}

environment_setup
install_instance