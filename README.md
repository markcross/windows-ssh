# windows-ssh
Powershell menu system for managing ssh connections in a corporate environment not requiring administrator access - "Can't install putty..."

## windows-ssh
Powershell menu system for managing ssh connections in a corporate environment not requiring administrator access - "Can't install putty..."

AI tells me it is a "Windows-native interactive SSH orchestrator" inspired by OpenSSH config + agent + CLI launchers"

In your %USERPROFILE% I have created a file called "ssh.ps1"

When I run a PowerShell icon from my task bar it comes up in my %USERPROFILE% so can now run the script linux style:

**PS %USERPROFILE%> ./ssh**    # then TAB next to obtain autocomplete

The the current Windows 11 OS then converts it to: 

**PS %USERPROFILE%> .\ssh.ps1**

I just HIT return and running for the first time will cache your ssh key passphrases if required or subsequent runs it will show your cached keys. (Yes windows does this slightly differently)

✅ Currently loaded SSH keys (via ssh-agent):

  • ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk7OpV8XsDP2Y40kuJfbKxIxpewi1k7gXc9OMO4MPe0 your_email@example.com 2026-05-22
  
  • ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIh7Z9FmwxpB8DW2pQ72q/daWXQiC1rJjSQdSe8OQ3iR your_email@example.com 2026-05-22
  
Then bring up the following:

```
📡 SSH Quick Connect Menu
[0] mark.cross@ezPR (Bastion as mark.cross) [key: id_ecdsa_2024-04-17]
[1] mark@192.168.165.10 (JumpBox) [key: id_ecdsa_2024-04-17]
[2] mark@ezPR (PRIMARY Bastion) [key: id_ecdsa_2024-04-17]
[3] mark@ezSEC (SECONDARY Bastion) [key: id_ecdsa_2024-04-17]
[4] mark@bluebottle (bluebottle) [key: id_ecdsa_2024-04-17]
[5] Exit
[6] Configure SSH Menu (edit config file)

Enter the number of your choice:
```

## ssh-config-menu
  
The menu is then configured by a file called:

**%USERPROFILE%\ssh-config-menu**

The lines is where you keys are stored, followed by your available keys

```
.ssh = "$env:USERPROFILE\.ssh\"
id_ecdsa_2024-04-17
2013_id_rsa
```

**Any lines after** the last definition are your menu, here is a full exammple which would produce the menu

```
.ssh = "$env:USERPROFILE\.ssh\"
id_ecdsa_2024-04-17
2013_id_rsa
Bastion as mark.cross#ezPR#mark.cross#id_ecdsa_2024-04-17
JumpBox#192.168.165.10#mark#id_ecdsa_2024-04-17
PRIMARY Bastion#ezPR#mark#id_ecdsa_2024-04-17
SECONDARY Bastion#ezSEC#mark#id_ecdsa_2024-04-17
bluebottle#bluebottle#mark#id_ecdsa_2024-04-17
```

## Explanation

First line .ssh path if customised - define here.
Lines before host definitions (a key line is any line with no `#` that contains `id_` or `.pem`, e.g. `id_ecdsa_2024-04-17`, `2013_id_rsa`, `aws.pem`)
Checks if each private file(s) exist
If exists and not already loaded, it runs ssh-add to cache the passphrase
So this block is your “key list” that the script automatically feeds into ssh-agent

Next are your "Alias#Host#Username#Keyname" line definitions

```
Alias → human‑readable description shown in the menu
Host → hostname or IP you SSH to
Username → username on the remote host
Keyname → the key filename (must exist under the .ssh path define on your first line of ssh-config-menu )
```

### Optional: start in a folder on the remote host

Add a fifth field, "Alias#Host#Username#Keyname#Folder", and the menu will SSH in and `cd` to that folder in one step. Lines without it work exactly as before.

```
bluebottle#bluebottle#mark#id_ecdsa_2024-04-17#/var/www
JumpBox#192.168.165.10#mark#id_ecdsa_2024-04-17
```

The folder shows in the menu after the host:

```
[0] mark@bluebottle:/var/www (bluebottle) [key: id_ecdsa_2024-04-17]
[1] mark@192.168.165.10 (JumpBox) [key: id_ecdsa_2024-04-17]
```

Behind the scenes it runs:

```
ssh -t -i "<keypath>" mark@bluebottle 'cd /var/www && exec $SHELL -l'
```

- `-t` gives you a proper interactive terminal
- `cd` changes folder; if the folder doesn't exist you'll see the error and the session closes, so typos are easy to spot
- `exec $SHELL -l` starts your normal login shell (bash, zsh, ...), so `.bashrc` / `.profile` still load and `exit` closes the connection

Notes: the folder can't contain spaces or a `#`. `~/projects` style paths work.

## Installation

Download and copy both the script "ssh.ps1" and skeleton "ssh-config-menu" to your %USERPROFILE% folder.
Edit the first line .ssh, location definition is your are going non windows standard
Replace the lines two and three with your "private keys"
Remove my host line examples and define your own

**How do I create key pairs in windows, example:**

ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ecdsa_oracle_prod -C "your_email@example.com 2026-05-22"

ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ecdsa_oracle_drc  -C "your_email@example.com 2026-05-22"

**Why not use windows built in .ssh\config as per Linux and also available to PowerShell**

It is way too complicated and easy to make a mistake and does not integrate "ssh-agent"

**Why is 2013_id_rsa in the ssh-config-menu on the third line?**

"Well cook me a kipper for breakfast", you are sharp! This was legacy but I thought I would leave it as a README comprehension test :-)

It used to be silently ignored because it doesn't start with `id_`. Key lines now only need to contain `id_` (or `.pem`) anywhere, so it is loaded into ssh-agent like the others. Remove the line if you don't want it loaded.

I hope you find this an absolute time saver and a putty buster. I have nothing against putty, I just hate having to use Windows.

Enjoy

