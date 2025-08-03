# UNC Charlotte ITSC 3146 virtual environment (Lima)

This repository is meant for Mac users. Windows users should use the [WSL version](https://github.com/jeffreyalanwang/ITSC_3146_WSL).

## Usage
### Install
Run `setup.sh`:

`curl https://raw.githubusercontent.com/jeffreyalanwang/ITSC_3146_Lima/refs/heads/main/pub/setup.sh | bash`

**Full installation instructions & Getting Started:** [Google Doc](https://docs.google.com/document/d/1cVBNAIqBanecqzs8SjHQX2mCBXuv-sqH/edit?usp=sharing&ouid=103252777093034404109&rtpof=true&sd=true)

### Uninstall
`curl https://raw.githubusercontent.com/jeffreyalanwang/ITSC_3146_Lima/refs/heads/main/pub/uninstall.sh | bash`

## Linux users
`setup.sh` will not work for you, but if you install Lima on your own, you should be able to download [ITSC-3146.yaml](/host/ITSC-3146.yaml) and load it into Lima yourself.

* You will need to remove the following line:
  
  `- vzNAT: true`

  and you will probably want to replace it with:
  
  `- lima: user-v2`

## Mechanics
Files in [/host/](/host/) are retrieved for use by software running in the host (i.e. macOS) OS, and files in [/guest/](/guest/) are required in the guest (Ubuntu) OS.

### Install script
**`setup.sh`** installs `homebrew`, and uses it to install the following packages if not present on the system: `XQuartz`, `Visual Studio Code`, `Lima`

The script ensures that XQuartz is registered with `launchd`, creates the Lima instance, then adds an entry in `~/.ssh/config`, sets it to start at login, and finally downloads and opens the [`profile.terminal`](/host/profile.terminal) file to register it with the Terminal app.

**`uninstall.sh`** removes the Lima instance, then deletes any applications and files resulting from `setup.sh` that are no longer desired by the user.

### macOS Terminal
[`profile.terminal`](/host/profile.terminal) is imported into its associated application with the `open` command.

The macOS Terminal precedes profile shell executables with a hyphen to indicate that they are login shells. This causes internal issues within `limactl`. As a result, we indirectly call `limactl` using `/usr/bin/env`.

During install, `setup.sh` replaces "LIMACTL_EXECUTABLE" with the actual path to `limactl`, as macOS Terminal profiles cannot find an executable using `$PATH`.

### Guest system setup
Unlike in WSL:
* `cloud-init` is not configured directly, as Lima necessarily provides its own configuration
* No host-side configuration files are checked for inside the image.

As a result, we have Lima download a plain Ubuntu image with no modifications.

During install, cloud-init options are indirectly generated, and guest OS config files are copied in, using the instance's [limayaml config](/host/ITSC-3146.yaml).

### X11 applications
#### X11 forwarding
X11 forwarding is enabled in the instance's [limayaml config](/host/ITSC-3146.yaml). Trusted X11 forwarding is also enabled, to avoid issues such as [connection timeout](https://github.com/lima-vm/lima/issues/2099). Note that Debian-based ssh clients already default to trusted X11 forwarding, but not macOS clients.

Lima instances create one SSH connection, which is shared for use across all SSH shells and forwarded sockets with that VM instance. As a result, SSH forwards guest X11 traffic to whatever `$DISPLAY` was set to at SSH connection (i.e. instance restart) time. To reset X11 forwarding or change the host `$DISPLAY` value, use `limactl restart`. You can also kill all running `ssh` processes and start a new SSH shell.

#### XQuartz $DISPLAY socket
On the host, XQuartz makes a `$DISPLAY` socket available at `:0` (`/tmp/.X11_unix/X0`), as well as a dynamically generated one created by `launchd` at login (configured by `/Library/LaunchAgents/org.xquartz.startx.plist`; socket located at located at `/private/tmp/com.apple.launchd.??????????/org.xquartz:0`).

We prefer to use the `launchd` socket for our `$DISPLAY` value, because if XQuartz is not running, `launchd` monitors the socket and starts XQuartz automatically. To avoid requiring logout, `setup.sh` starts `/Library/LaunchAgents/org.xquartz.startx.plist` manually and then searches for the resulting socket.

#### Copy/paste
XQuartz is configured by default to remap **Command**+**C** to X11 copy, as well as clipboard sync.

Pasting is configured in [.Xdefaults](/guest/Xdefaults) (which is symlinked to root user's home directory as well), so that **Command**+**V** maps to paste in applications like XTerm. However, in Tk/Tcl apps like IMUNES, you will still have to use **Control**+**V** instead.

### IMUNES installation
We currently install IMUNES from a mirror with a few bugfixes required for this course at:
https://github.com/jeffreyalanwang/imunes

### VS Code editing
We take advantage of Lima's persistent SSH connection to use VS Code's Remote Development feature.

VS Code is able to read saved SSH hosts (including our Lima VM) from `~/.ssh/config`.

We start the Lima instance at login time using `limactl start-at-login` so that this SSH connection, as well as SMB file sharing (see [below](#file-access-from-host)), are always accessible.

### File access from guest
We configure read-write access to the user's host home directory in the `mounts` section of the [limayaml config](/host/ITSC-3146.yaml). macOS host users are mounted in the guest at the same path (e.g. `/Users/accountname`).

At runtime, `/tmp/lima` may also be available in both guest and host systems for use as a temporary shared folder.

### File access from host
In the guest, [Samba is configured](/guest/smb.conf) to be network-discoverable, with
* a read-only root directory share: `ITSC-3146-root`
* a read-write share of `/home/itsc`: `ITSC-3146-home`

#### Samba configuration

Samba is configured to allow guest connections, and force all connections to act as the `itsc` user for permission/access purposes.

Samba can only access users if they are given a password using `smbpasswd`. Because it does not have to match the user's normal password, we give `itsc` a blank password using `smbpasswd` at install time.

Note: Samba does not have built-in support for smb.conf.d, so files in that directory must be provided an `include` statement in /etc/samba/smb.conf.

#### Networking

The host network is not provided network access to the guest by Lima's defaults.

In the `networks` section of its [limayaml config](/host/ITSC-3146.yaml), we set the instance to use vzNAT, which relies on Apple's macOS Virtualization framework to access the Lima instance at the hostname `lima-itsc-3146` (non-case sensitive), or at the IP address assigned to the instance's `lima0` network interface.

For Linux users, the alternative would be [user-v2](https://lima-vm.io/docs/config/network/user-v2/).
