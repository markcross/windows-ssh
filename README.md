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
[5] Configure SSH Menu (edit config file)

After a number:  e edit   + insert above   - insert below   d delete
                  < up   > down   , top   . bottom
On its own:       x exit   REVERT undo last change   ka add key   kl list keys

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
ssh -t -i "<keypath>" mark@bluebottle 'export PROMPT_COMMAND=''cd /var/www; unset PROMPT_COMMAND''; exec $SHELL -l'
```

- `-t` gives you a proper interactive terminal
- `exec $SHELL -l` starts your normal login shell, so `.bash_profile` / `.bashrc` load as usual (environment, aliases) and `exit` closes the connection
- `PROMPT_COMMAND` runs just before the first prompt, so the `cd` happens *after* your profile. This matters if your `.bash_profile` has its own `cd` (common on Oracle-style servers), which would otherwise move you straight back. It removes itself after running once.
- If the folder doesn't exist you'll see a `cd` error and stay wherever your profile left you

Notes: the remote login shell must be bash (zsh ignores `PROMPT_COMMAND`, so you'd connect without changing folder). The folder can't contain spaces or a `#`. `~/projects` style paths work.

### Managing entries from the menu

Type an entry's number followed by one of these (`REVERT` and `x` are typed on their own), then press Enter:

| Type | Does |
|---|---|
| `6e` | Edit entry 6 |
| `6+` | Insert a new entry above 6, then edit it |
| `6-` | Insert a new entry below 6, then edit it |
| `6<` | Move entry 6 up one place |
| `6>` | Move entry 6 down one place |
| `6,` | Move entry 6 to the top |
| `6.` | Move entry 6 to the bottom |
| `6d` | Delete entry 6 (you must type `YES` in capitals to confirm) |
| `REVERT` | Undo the last change (type it again to go back further) |
| `x` | Exit the menu |
| `ka` | Create a new key pair (see below) |
| `kl` | Open the key list in a new window (see below) |

The menu shows a reminder of these under the list, and a one-line result (e.g. `✅ Moved [6] to [0].`) after each action.

**Editing** shows each field with its current value: press Enter to keep it, or type a new value. For Folder, type `-` to remove it.

```
Enter the number of your choice: 6e

✏️  Editing entry [6]  (press Enter to keep the value shown)
    For Folder, type - to remove it.

  Alias    [cainsight]:
  Host     [mdsp]:
  Username [cainsight]:
  Key      [id_ecdsa_btop_2024-04-17]:
  Folder   [/u05/app/insight/tools/TytanCCSimulator/run/]: /u05/app/insight/logs

  Old: cainsight#mdsp#cainsight#id_ecdsa_btop_2024-04-17#/u05/app/insight/tools/TytanCCSimulator/run/
  New: cainsight#mdsp#cainsight#id_ecdsa_btop_2024-04-17#/u05/app/insight/logs

Save? (y/N): y
```

**Inserting** works the same way. The new entry starts as a copy of the one you numbered, so usually only the alias and host need typing. Answer `n` at `Insert? (y/N)` and nothing is added. If the menu has no entries yet, `0+` adds the first one.

**Moving** only reorders host lines. Key lines, comments and blank lines in `ssh-config-menu` stay where they are.

**Checks:** `#` isn't allowed in any field, the folder can't contain spaces, and you get a warning if the key file isn't in your `.ssh` folder.

#### Backups and REVERT

Before every change, the current `ssh-config-menu` is copied to `ssh-config-menu.bak.1`. Older backups move up one (`.bak.1` → `.bak.2` … `.bak.9` → `.bak.10`), so the last 10 versions are kept:

```
ssh-config-menu.bak.1    newest
ssh-config-menu.bak.2
...
ssh-config-menu.bak.10   oldest
```

`REVERT` shows when the newest backup was saved and asks `Revert? (y/N)`. It then restores `ssh-config-menu.bak.1` and moves the rest down one (`.bak.2` → `.bak.1` …), so typing `REVERT` again goes back another step. A revert can't itself be undone.

Changes made in Notepad (the "Configure SSH Menu" option) aren't backed up.

### Managing SSH keys: `ka` and `kl`

**`ka`: add a key pair.** Asks for:
- **Type:** `[1] ed25519` (default, recommended), `[2] ecdsa` or `[3] rsa`
- **Length:** fixed at 256 for ed25519; 256 / 384 / 521 for ecdsa (default 256); 2048 / 3072 / 4096 for rsa (default 4096)
- **Name:** default `id_<type>_<date>`, e.g. `id_ed25519_2026-11-24`. It must contain `id_` so the menu treats it as a key, and it can't already exist.
- **Comment:** default `<username>@<computer> <date>`

It then runs `ssh-keygen`, which asks for the passphrase. The new key is added to the key list in `ssh-config-menu` (with a backup first, so `REVERT` works), and the public key is shown and copied to the clipboard ready to paste into a server's `~/.ssh/authorized_keys`. Finally it offers to load the key into ssh-agent.

Windows uses the same file names as Linux: the private key has no extension (`id_ed25519_work`) and the public key ends in `.pub` (`id_ed25519_work.pub`).

**`kl`: list keys.** Opens a new window listing every key pair in your `.ssh` folder:

```
🔑 SSH keys in C:\Users\you\.ssh
[0] id_ecdsa_2024-04-17  ED25519 256  you@example.com 2024-04-17
      loaded in ssh-agent · in key list · used by: JumpBox, PRIMARY Bastion
[1] id_ed25519_mdsp  ED25519 256  you@PC123 2026-11-24
      in key list

After a number:  e edit comment   d delete
On its own:       ka add key   x close
```

| Type | Does |
|---|---|
| `0e` | Edit key 0's comment (`ssh-keygen -c`; it may ask for the passphrase). Only works for keys in the newer OpenSSH format; very old RSA keys don't store a comment. |
| `0d` | Delete key 0. It shows which menu entries use it, then you must type `YES` in capitals. The key files are **moved** to `.ssh\deleted\<date_time>\` rather than erased, the key is removed from ssh-agent, and its line is removed from the key list in `ssh-config-menu`. |
| `ka` | Add a key pair, as above |
| `x` | Close the key window |

You can also open the key window directly with `.\ssh.ps1 keys`.

## Installation

Download and copy both the script "ssh.ps1" and skeleton "ssh-config-menu" to your %USERPROFILE% folder.
Edit the first line .ssh, location definition is your are going non windows standard
Replace the lines two and three with your "private keys"
Remove my host line examples and define your own

**How do I create key pairs in windows, example:**

The easiest way is `ka` in the menu (see "Managing SSH keys" above). By hand:

ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_oracle_prod -C "your_email@example.com 2026-05-22"

ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_oracle_drc  -C "your_email@example.com 2026-05-22"

**Why not use windows built in .ssh\config as per Linux and also available to PowerShell**

It is way too complicated and easy to make a mistake and does not integrate "ssh-agent"

**Why is 2013_id_rsa in the ssh-config-menu on the third line?**

"Well cook me a kipper for breakfast", you are sharp! This was legacy but I thought I would leave it as a README comprehension test :-)

It used to be silently ignored because it doesn't start with `id_`. Key lines now only need to contain `id_` (or `.pem`) anywhere, so it is loaded into ssh-agent like the others. Remove the line if you don't want it loaded.

I hope you find this an absolute time saver and a putty buster. I have nothing against putty, I just hate having to use Windows.

Enjoy

