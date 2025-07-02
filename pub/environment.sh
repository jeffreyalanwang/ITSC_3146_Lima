#!/bin/bash

# Install homebrew, if not present
if ! (which "brew" -s); then
    echo "Installing homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "Homebrew found at $(which "brew")."
fi

# Install xquartz, if not present
if ! (which "xquartz" -s); then
    brew install --cask xquartz
else
    echo "XQuartz found at $(which "xquartz")."
fi

# Install lima, if not present
if ! (which "lima" -s); then
    brew install lima
else
    echo "Lima found at $(which "lima")."
fi

# Install vscode, if not present
if ! (which "code" -s) && ! (ls "/Applications/" | grep -q "Visual Studio Code"); then
    brew install --cask visual-studio-code
else
    echo "Visual Studio Code found at $(which "code" || echo "/Applications/")."
fi

echo "Completed successfully."