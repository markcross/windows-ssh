# windows-ssh aka [ SSH Quick Connect Menu ]
Powershell menu system for managing ssh connections in a corporate environment not requiring administrator access with scp built in. Putty not required.

## windows-ssh
AI tells me it is a "Windows-native interactive SSH orchestrator" inspired by OpenSSH config + agent + CLI launchers"

I hope it is a complete key management toolset to create, manage ssh keys, ssh-agent management, ssh into machines; cd into a destination folder of your choice and scp files. It replaces putty and puttygen and uses native windows tools, negating forward upgrading concerns for putty security issues like CVE-2024-31497, as this will be maintained by windows update.
It works for me in a extremely locked down corporate user profile environment after a few workarounds. Bonus, it also manages AWS .pem files, allowing you to add a passphrase were there never was one issued by Amazon at EC2 creation time for example.

In your %USERPROFILE% I created a file called "ssh.ps1". The script was built up over time and polished by various AI coding sessions, as agentic coding is surely the way forwards?

When I run a PowerShell icon from my task bar it comes up in my %USERPROFILE% so can now run the script linux style:

**PS %USERPROFILE%> ./ssh**    # then TAB next to obtain autocomplete

The the current Windows 11 OS then converts it to: 

**PS %USERPROFILE%> .\ssh.ps1**

I just HIT return and it shows the keys currently cached in ssh-agent. To load the keys from your key list into ssh-agent (asking for each passphrase once), run it with `add` the first time, e.g. after a reboot:

**PS %USERPROFILE%> .\ssh.ps1 add**

(Yes windows does this slightly differently)

✅ Currently loaded SSH keys (via ssh-agent):

  • ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk7OpV8XsDP2Y40kuJfbKxIxpewi1k7gXc9OMO4MPe0 your_email@example.com 2026-05-22
  
  • ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIh7Z9FmwxpB8DW2pQ72q/daWXQiC1rJjSQdSe8OQ3iR your_email@example.com 2026-05-22
  
Then brings up the following:

```
📡 SSH Quick Connect Menu v0.20
[0] mark.cross@ezPR (Bastion as mark.cross) [key: id_ecdsa_2024-04-17]
[1] mark@192.168.165.10 (JumpBox) [key: id_ecdsa_2024-04-17]
[2] mark@ezPR (PRIMARY Bastion) [key: id_ecdsa_2024-04-17]
[3] mark@ezSEC (SECONDARY Bastion) [key: id_ecdsa_2024-04-17]
[4] mark@bluebottle (bluebottle) [key: id_ecdsa_2024-04-17]
[5] Configure SSH Menu (edit config file)

After a number:  e edit   + insert above   - insert below   d delete
                  < up   > down   , top   . bottom
                  c copy from host   p push to host   i install a key on this host
On its own:       x exit   REVERT undo last change   ka add key   kl list keys

Enter the number of your choice:
```

## Menu options at a glance

### Main menu

| Type | Does | Details |
|---|---|---|
| `6` | Connect to entry 6 in a new window. The menu stays ready for your next choice, with the ssh command it ran shown underneath | [Start in a folder](#optional-start-in-a-folder-on-the-remote-host) |
| `6e` | Edit entry 6 | [Managing entries](#managing-entries-from-the-menu) |
| `6+` | Insert a new entry above 6, then edit it | [Managing entries](#managing-entries-from-the-menu) |
| `6-` | Insert a new entry below 6, then edit it | [Managing entries](#managing-entries-from-the-menu) |
| `6<` | Move entry 6 up one place | [Managing entries](#managing-entries-from-the-menu) |
| `6>` | Move entry 6 down one place | [Managing entries](#managing-entries-from-the-menu) |
| `6,` | Move entry 6 to the top | [Managing entries](#managing-entries-from-the-menu) |
| `6.` | Move entry 6 to the bottom | [Managing entries](#managing-entries-from-the-menu) |
| `6d` | Delete entry 6 (type `YES` in capitals to confirm) | [Managing entries](#managing-entries-from-the-menu) |
| `6i` | Install one of your public keys on entry 6's host | [Installing a public key](#installing-a-public-key-on-a-host) |
| `6c` | Copy files from entry 6's host to this PC (scp) | [Copying files](#copying-files-from-a-host-scp) |
| `6p` | Push files from this PC to entry 6's host (scp) | [Pushing files](#pushing-files-to-a-host-scp) |
| *Configure number* | Open `ssh-config-menu` in Notepad (the number straight after the last entry, `[5]` above) | |
| `REVERT` | Undo the last change to `ssh-config-menu` (again to go further back) | [Backups and REVERT](#backups-and-revert) |
| `ka` | Create a new key pair | [Managing SSH keys](#managing-ssh-keys-ka-and-kl) |
| `kl` | Open the key list in a new window | [Managing SSH keys](#managing-ssh-keys-ka-and-kl) |
| `x` | Exit | |

Letters can be typed in either case (`6E`, `X`, `revert`), except that delete needs `YES` in capitals.

After an action, the menu redraws straight away with the result underneath, e.g. `✅ Moved [6] to [0].` For a connect, copy or push, the ssh or scp command it ran is shown too:

```
[5] Configure SSH Menu (edit config file)
...
🚀 Opened a new window connecting to mark@bluebottle
Running: ssh -i "C:\Users\you\.ssh\id_ecdsa_2024-04-17" mark@bluebottle

Enter the number of your choice:
```

The result disappears at the next redraw.

### Key window (`kl`)

```
🔑 SSH keys in C:\Users\you\.ssh
[0] 2013_id_rsa  RSA 2048  old-laptop 2013
      in key list
[1] aws.pem  ?
      no .pub file
[2] id_ecdsa_2024-04-17  ED25519 256  your_email@example.com 2026-05-22
      loaded in ssh-agent · in key list · used by: Bastion as mark.cross, JumpBox, PRIMARY Bastion, SECONDARY Bastion, bluebottle
[3] id_ed25519_2026-11-24  ED25519 256  you@PC123 2026-11-24
      loaded in ssh-agent · in key list
[4] id_ed25519_mdp  ED25519 256  you@PC123 2026-11-24
      in key list · used by: cane

After a number:  e edit comment   p passphrase   d delete   i install on a host
On its own:       ka add key   x close

✅ Created id_ed25519_2026-11-24.

Enter your choice:
```

Each key shows its name, type and length, and comment. Keys are sorted by name, and the grey line underneath says:

| Flag | Meaning |
|---|---|
| `loaded in ssh-agent` | The key is cached in ssh-agent right now, so it won't ask for its passphrase |
| `in key list` | It's listed in `ssh-config-menu`, so `.\ssh.ps1 add` loads it |
| `used by: …` | The menu entries (by alias) whose Key is this key |
| `no .pub file` | Only the private key was found (e.g. a `.pem` from AWS). Its type shows as `?` with no length or comment, it can't be installed with `i`, and the menu can't tell whether it's loaded |
| `no private key file` | Only the `.pub` was found. Its comment can't be edited, and although `i` can install it, the sign-in test afterwards will fail without the private key |

The line starting `✅` is the result of the last action (here, `ka` creating a key). It disappears at the next redraw.

| Type | Does |
|---|---|
| `0e` | Edit key 0's comment |
| `0p` | Change key 0's passphrase (also adds or removes one) |
| `0d` | Delete key 0 (type `YES` in capitals to confirm; the files are moved to `.ssh\deleted\`, not erased) |
| `0i` | Install key 0 on one of your menu hosts |
| `ka` | Create a new key pair |
| `x` | Close the key window |

`p` means **passphrase** here, but **push** in the main menu. The two windows each have their own letters, and numbers here are key numbers, not menu entries.

### Command line

| Run | Does |
|---|---|
| `.\ssh.ps1` | Show the loaded keys, then the menu |
| `.\ssh.ps1 add` | First load every key in your key list into ssh-agent (asks each passphrase once), then the menu |
| `.\ssh.ps1 keys` | Open the key window directly (what `kl` does) |

Using an AWS `.pem` key? See [Using an AWS `.pem` key](#using-an-aws-pem-key) for the setup steps and fixes for common errors.

### Version number

The menu title shows the version, e.g. `SSH Quick Connect Menu v0.20`. The number after `0.` is the pull request that last changed `ssh.ps1`, so it tells you which change your copy includes. Compare it with the [pull requests](https://github.com/markcross/windows-ssh/pulls?q=is%3Apr+is%3Amerged) to see what's new since.

### Files the menu uses

| File | What it is |
|---|---|
| `%USERPROFILE%\ssh.ps1` | The script |
| `%USERPROFILE%\ssh-config-menu` | Your key list and menu entries ([format](#ssh-config-menu)) |
| `%USERPROFILE%\ssh-config-menu.bak.1` … `.bak.10` | The last 10 versions of `ssh-config-menu`, newest first, made before each change from the menu ([Backups and REVERT](#backups-and-revert)) |
| `%USERPROFILE%\ssh-config-menu.scp` | The last copy (`c`) and push (`p`) paths used for each host ([Copying files](#copying-files-from-a-host-scp)) |
| `%USERPROFILE%\.ssh\` | Your keys (or the folder set on the `.ssh = ` line) |
| `%USERPROFILE%\.ssh\deleted\<date_time>\` | Keys deleted from the key window, moved rather than erased |

The menu creates the backups, `ssh-config-menu.scp` and the `deleted` folders when they're first needed. You can delete any of those at any time.

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

Type an entry's number followed by an action letter or symbol, e.g. `6e`, `6+` or `6d`, then press Enter. The full list is in [Menu options at a glance](#menu-options-at-a-glance).

The menu shows a reminder of these under the list, and a one-line result (e.g. `✅ Moved [6] to [0].`) after each action.

**Editing** shows each field with its current value: press Enter to keep it, or type a new value. For Folder, type `-` to remove it.

```
Enter the number of your choice: 6e

✏️  Editing entry [6]  (press Enter to keep the value shown)
    For Folder, type - to remove it.

  Alias    [cane]:
  Host     [mdp]:
  Username [cane]:
  Key      [id_ecdsa_btop_2024-04-17]:
  Folder   [/home/cane/bin]: /home/cane/logs

  Old: cane#mdp#cane#id_ecdsa_btop_2024-04-17#/home/cane/bin
  New: cane#mdp#cane#id_ecdsa_btop_2024-04-17#/home/cane/logs

Save? (y/N): y
```

**Inserting** works the same way. The new entry starts as a copy of the one you numbered, so usually only the alias and host need typing. Answer `n` at `Insert? (y/N)` and nothing is added. If the menu has no entries yet, `0+` adds the first one.

**Moving** only reorders host lines. Key lines, comments and blank lines in `ssh-config-menu` stay where they are.

**Separator lines:** give an entry an alias starting with `-----` to draw a line across the menu, e.g. to group your hosts. Only the alias is asked for; the other fields are filled with `-`. The line is as wide as the longest entry, and anything after the dashes is kept as a label:

```
[0] mark.cross@ezPR (Bastion as mark.cross) [key: id_ecdsa_2024-04-17]
[1] -----------------------------------------------------------------
[2] mark@192.168.165.10 (JumpBox) [key: id_ecdsa_2024-04-17]
[3] ----- Production ------------------------------------------------
[4] mark@ezPR (PRIMARY Bastion) [key: id_ecdsa_2024-04-17]
```

In `ssh-config-menu` these are lines like `-----#-#-#-` or `----- Production#-#-#-`. A separator keeps its number, so you can edit, move or delete it like any entry (`1e`, `1<`, `1d`). Choosing it, or using `c`, `p` or `i` on it, just says it's a separator. Separators aren't offered as hosts when installing a key.

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

It then runs `ssh-keygen`, which asks for the passphrase. The new key is added to the key list in `ssh-config-menu` (with a backup first, so `REVERT` works), and the public key is shown and copied to the clipboard ready to paste into a server's `~/.ssh/authorized_keys`. Finally it offers to load the key into ssh-agent and to install it on one of your menu hosts.

Windows uses the same file names as Linux: the private key has no extension (`id_ed25519_work`) and the public key ends in `.pub` (`id_ed25519_work.pub`).

**`kl`: list keys.** Opens a new window listing every key pair in your `.ssh` folder. There's an example of the page, with what each flag means, under [Key window](#key-window-kl).

| Type | Does |
|---|---|
| `0e` | Edit key 0's comment (`ssh-keygen -c`; it may ask for the passphrase). Only works for keys in the newer OpenSSH format; very old RSA keys don't store a comment (changing the passphrase with `p` converts them, after which `e` works). |
| `0p` | Change key 0's passphrase with `ssh-keygen -p`. It asks for the current passphrase (just Enter if the key has none, e.g. an AWS `.pem`), then the new one twice; Enter twice removes the passphrase. The passphrases go straight to `ssh-keygen`, never through the script. A wrong old passphrase leaves the file untouched. If the key is loaded in ssh-agent, the loaded copy keeps working; the next `.\ssh.ps1 add` asks for the new passphrase. Older-format keys (`BEGIN RSA PRIVATE KEY`) are saved in the newer OpenSSH format, which works the same with ssh. No backup copy is kept, because it would still open with the old passphrase. |
| `0d` | Delete key 0. It shows which menu entries use it, then you must type `YES` in capitals. The key files are **moved** to `.ssh\deleted\<date_time>\` rather than erased, the key is removed from ssh-agent, and its line is removed from the key list in `ssh-config-menu`. |
| `0i` | Install key 0 on one of your menu hosts (see below) |
| `ka` | Add a key pair, as above |
| `x` | Close the key window |

You can also open the key window directly with `.\ssh.ps1 keys`.

### Installing a public key on a host

There are three ways in:
- **Main menu `6i`:** pick which key to install on entry 6's host.
- **Key window `0i`:** pick which host to install key 0 on.
- **At the end of `ka`:** answer `y` to "Install it on one of your menu hosts now?"

What happens:
1. It signs in the way that menu entry already does, using its current key. If that key isn't accepted, ssh tries your ssh-agent keys and then asks for the password.
2. It adds the public key to `~/.ssh/authorized_keys` on the server, creating `~/.ssh` if needed with owner-only permissions. If that exact key line is already there, it says so and adds nothing. On SELinux servers it also runs `restorecon`, as `ssh-copy-id` does.
3. It tests signing in with the new key on its own. If that works and the menu entry uses a different key, it offers to switch the entry to the new key (with a backup, so `REVERT` works).

This is the Windows equivalent of Linux's `ssh-copy-id`. The server needs a `sh`-compatible shell (bash, sh, ksh, zsh).

### Copying files from a host (scp)

`6c` copies files **from** entry 6's host **to** this PC. It asks for a source and a destination. Each is pre-filled with what you last used for that host, so repeating a copy is just Enter, Enter:

```
Enter the number of your choice: 6c

📥 Copy files from [6] cane@mdp to this PC  (press Enter to accept the value shown)
   Source on the host: a file, a wildcard, or a folder ending in /
     /home/user/thefile.txt    /home/user/*2026-11-01.log    /home/user/*    /home/user/logs/
   Destination on this PC: Downloads\... is your Downloads folder; other paths are relative to C:\Users\you
     You can paste a path (Explorer: Shift+right-click, Copy as path) or drag a folder into this window.

  Source       [/home/cane/*2026-11-01.log]:
  Destination  [Downloads\wireshark\]:

  Copy  cane@mdp:/home/cane/*2026-11-01.log
  to    C:\Users\you\Downloads\wireshark

Copy? (y/N): y

  Running: scp -i C:\Users\you\.ssh\id_ecdsa_btop_2024-04-17 cane@mdp:/home/cane/*2026-11-01.log C:\Users\you\Downloads\wireshark

app_2026-11-01.log                       100%   48KB   1.2MB/s   00:00
db_2026-11-01.log                        100%  210KB   2.8MB/s   00:00

Open C:\Users\you\Downloads\wireshark in Explorer? (y/N):
```

You're then back at the menu, with the copy and the scp command shown under it.

**Made a mistake?** The `Copy? (y/N)` check shows the full local folder, which is where a typo shows up (`(will be created)` after it means the folder doesn't exist yet). Answer `n`, or just press Enter, and you're back at the menu with nothing copied and no folder created. What you typed is still remembered, so `6c` brings it back for you to correct.

**Source** (on the host):

| Type | Copies |
|---|---|
| `/home/user/thefile.txt` | That one file |
| `/home/user/*2026-11-01.log` | Every file matching the wildcard |
| `/home/user/*` | Every file in the folder; subfolders are skipped |
| `/home/user/logs/` | The whole `logs` folder, including subfolders (a trailing `/` copies recursively) |

`~/` works for your home folder on the host. The first time you copy from a host, the source defaults to the entry's start folder followed by `/*`, if the entry has one.

**Destination** (on this PC):

| Type | Goes to |
|---|---|
| `Downloads\` | Your Downloads folder (the default the first time) |
| `Downloads\wireshark\` | `wireshark` inside your Downloads folder |
| `projects\logs` | `C:\Users\you\projects\logs` (other relative paths are relative to your profile folder) |
| `C:\temp\logs` | That exact folder |

- `Downloads` means your real Downloads folder, looked up from Windows, so it's still right if it has been moved (e.g. to OneDrive).
- The trailing `\` is optional, and `/` works too (`Downloads/wireshark/.` is the same folder).
- The folder is created if it doesn't exist, but only after you answer `y` at `Copy?`. When it would be created, the check also lists similar folders that do exist, as ready-to-paste paths (e.g. `Downloads\wireshark\` for `Downloads\wiresharks\`), so the typo is easy to spot and fix with `n` then `6c`.
- Files with the same name are overwritten.

**Remembered values** are stored per `user@host` in `%USERPROFILE%\ssh-config-menu.scp`, one line per host, shared with `p` (`user@host#copySource#copyDestination#pushSource#pushDestination`). Any `#` in a path is stored as `%23` and `%` as `%25`, so they can't break the line format. They're saved even when a copy fails, so you can correct a typo and try again. Delete the file to forget them all.

**Notes:**
- It signs in with the entry's key, like connecting does. A password or passphrase prompt appears in the menu window.
- Paths can contain spaces, `#`, quotes and brackets. Type them plainly, without quotes or backslashes. For the source, the menu escapes them for the server itself, leaving `*`, `?` and `[ ]` working as wildcards.
- If scp reports an error (e.g. no files matched the wildcard), the menu pauses so you can read it.

### Pushing files to a host (scp)

`6p` is the reverse of `6c`: it sends files **from** this PC **to** entry 6's host. The source and destination are again pre-filled with what you last used for that host:

```
Enter the number of your choice: 6p

📤 Push files from this PC to [6] cane@mdp  (press Enter to accept the value shown)
   Source on this PC: a file, a wildcard, or a folder ending in \   (- to cancel)
     Downloads\report.txt    Downloads\*2026-11-01.log    Downloads\wireshark\*    Downloads\wireshark\
     Downloads\... is your Downloads folder; other paths are relative to C:\Users\you
     You can paste a path (Explorer: Shift+right-click, Copy as path) or drag a file into this window.
   Destination on the host: an existing folder, e.g. ~/ or /home/user/uploads/
   Files with the same name on the host are overwritten.

  Source       [Downloads\wireshark\*.pcap]:
  Destination  [/home/cane/bin/]:

  Sending 2 file(s):
    C:\Users\you\Downloads\wireshark\capture1.pcap
    C:\Users\you\Downloads\wireshark\capture2.pcap

Send to cane@mdp:/home/cane/bin/? (y/N): y

  Running: scp -i C:\Users\you\.ssh\id_ecdsa_btop_2024-04-17 C:\Users\you\Downloads\wireshark\capture1.pcap C:\Users\you\Downloads\wireshark\capture2.pcap cane@mdp:/home/cane/bin/

capture1.pcap                            100%  1.2MB   3.1MB/s   00:00
capture2.pcap                            100%  860KB   2.9MB/s   00:00
```

**Source** (on this PC). Paths work the same way as `6c`'s destination: `Downloads\...` is your real Downloads folder, other relative paths are relative to your profile folder, and full paths like `C:\temp\x.log` are used as they are.

| Type | Sends |
|---|---|
| `Downloads\report.txt` | That one file |
| `Downloads\*2026-11-01.log` | Every file matching the wildcard |
| `Downloads\wireshark\*` | Every file in the folder; subfolders are skipped |
| `Downloads\wireshark\` | The whole `wireshark` folder, including subfolders (a trailing `\` sends recursively) |

`/` works as well as `\` in all of these.

Windows doesn't expand wildcards for scp, so the menu finds the matching files itself and lists them, showing the first 10 if there are more. You're then asked `Send to ...? (y/N)`. If nothing matches, it says so, lists what *is* there, and asks for the source again; type `-` to cancel:

```
  Source       []: Downloads\wiresh\*
    ❌ Nothing matches C:\Users\you\Downloads\wiresh\*
    Close matches in C:\Users\you\Downloads:
      Downloads\wireshark\*
  Source       [Downloads\wiresh\*]: Downloads\wireshark\*
```

It walks up to the nearest folder that exists and finds the names starting like the part that's missing. If none do, it lists everything in that folder. Each suggestion is **your path with the wrong part corrected**, in the form you typed it, so you can copy it and paste it straight back in. The rest of what you typed is kept: here `\*` (just the files), not a trailing `\`, which would send the whole folder.

There's no default source the first time, so pressing Enter can never upload a whole folder by accident.

**Destination** (on the host): a folder that already exists. It defaults to the last one you used, or the first time to the entry's start folder (or `~/` if it has none).

**Notes:**
- **No tab completion.** The prompts can't offer it on locked-down PowerShell (Constrained Language Mode). Instead, paste a path: in Explorer, Shift+right-click a file and choose **Copy as path**, or drag the file into the window. The quotes Windows adds are removed automatically. This works at every copy and push prompt.
- Files with the same name on the host are overwritten without asking.
- If the destination folder doesn't exist, scp reports an error. Create it with an ssh session first.
- Spaces and `#` are fine in both paths, as with `6c`.
- The result appears under the menu: `📤 Sent 2 file(s) to cane@mdp:/home/cane/bin/` plus the scp command. With more than 3 files, the command is shortened to `<N files>`.

## Using an AWS `.pem` key

A `.pem` file from AWS is an ordinary private key with a different file extension, and the menu uses it like any other. AWS gives you only the private half; there's no `.pub` file.

### Setup

**1. Copy the `.pem` into your `.ssh` folder,** e.g. `C:\Users\you\.ssh\aws-prod.pem`. Keys are always looked up in the folder set on the `.ssh = ` line of `ssh-config-menu`.

**2. Lock down its permissions.** Windows OpenSSH refuses a private key that other accounts can read, and a downloaded `.pem` usually can. You own the file, so this doesn't need admin rights:

```
icacls "$env:USERPROFILE\.ssh\aws-prod.pem" /inheritance:r
icacls "$env:USERPROFILE\.ssh\aws-prod.pem" /grant:r "$($env:USERNAME):(R)"
```

The first command removes the inherited permissions; the second gives only you read access.

**3. Add a menu entry** with `+` / `-` in the menu, or in `ssh-config-menu`:

```
AWS prod#ec2-12-34-56-78.eu-west-2.compute.amazonaws.com#ec2-user#aws-prod.pem
```

The username depends on the image the instance was built from:

| Image (AMI) | Username |
|---|---|
| Amazon Linux, RHEL, Fedora | `ec2-user` |
| Ubuntu | `ubuntu` |
| Debian | `admin` |
| CentOS | `centos` (or `ec2-user`) |
| SUSE | `ec2-user` |

**4. Optional: create the `.pub`,** so the key window (`kl`) can show the key's type and whether it's loaded, and so `i` can install it on other servers:

```
ssh-keygen -y -f "$env:USERPROFILE\.ssh\aws-prod.pem" | Set-Content -Encoding ascii "$env:USERPROFILE\.ssh\aws-prod.pem.pub"
```

Use `Set-Content -Encoding ascii`, not `>`. In Windows PowerShell, `>` writes UTF-16, which ssh tools can't read. Without the `.pub`, `kl` shows the key as `aws-prod.pem  ?` with `no .pub file`, which is harmless.

**5. Optional: add it to the key list.** Put `aws-prod.pem` on its own line near the top of `ssh-config-menu`. Its name contains `.pem`, so the menu recognises it as a key, and `.\ssh.ps1 add` loads it into ssh-agent. AWS keys have no passphrase, so this step is optional.

### Problem notes

| You see | Cause | Fix |
|---|---|---|
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` / `Permissions for '...pem' are too open` / `bad permissions` | Other accounts (often `Users` or `Authenticated Users`) can read the file | Step 2 above. Check with `icacls "$env:USERPROFILE\.ssh\aws-prod.pem"`: only your account should be listed. |
| `Permission denied (publickey)` | Usually the wrong username for the AMI. Can also mean the wrong `.pem` for that instance (each instance is tied to the key pair chosen at launch). | Check the username table in step 3. In the AWS console, the instance's details show its **Key pair name**. |
| `Load key "...pem": invalid format` | The file was damaged when it was copied, e.g. pasted into Notepad and saved as UTF-16, or the `-----BEGIN` / `-----END` lines lost | Download it again, or save it from Notepad with encoding **UTF-8** or **ANSI**. It must start with `-----BEGIN` and end with a newline after `-----END ... KEY-----`. |
| `Connection timed out` | Nothing answered on port 22. Either the instance's **security group** doesn't allow ssh from your IP, or the **corporate firewall** blocks outgoing ssh. | Ask for port 22 to be opened from your office's public IP in the security group. Test from another network (e.g. a phone hotspot) to tell the two apart. Some companies only allow ssh through a bastion. |
| `Connection refused` | The instance answered but sshd isn't running, or it's still booting | Wait a minute after start-up. Check the instance's system log in the AWS console. |
| `Could not resolve hostname` | The public DNS name changed or is wrong. A stopped and restarted instance gets a **new public IP and DNS name** unless it has an Elastic IP. | Copy the current public DNS name or IP from the console and `6e` the entry. Ask for an Elastic IP if it changes often. |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | The DNS name or IP now belongs to a different instance (after a rebuild, or IP reuse), whose host key is different from the one remembered | If you know the instance was replaced, remove the old entry with `ssh-keygen -R <host>`, then connect again and accept the new key. If you don't know why it changed, stop and check. This warning is also what an interception attack looks like. |
| `Too many authentication failures` | ssh can try the keys in your ssh-agent before the `.pem`. With several keys loaded, the server gives up before reaching the right one (it allows about 6 tries). | Run `ssh -o IdentitiesOnly=yes -i "$env:USERPROFILE\.ssh\aws-prod.pem" ec2-user@<host>` to check the key itself works. Clearing ssh-agent with `ssh-add -D` also works (run `.\ssh.ps1 add` afterwards to reload your keys). |

To see exactly where it fails, connect by hand with `-v` and look at the last few lines:

```
ssh -v -i "$env:USERPROFILE\.ssh\aws-prod.pem" ec2-user@<host>
```

## Installation

Download and copy both the script "ssh.ps1" and skeleton "ssh-config-menu" to your %USERPROFILE% folder.
If PowerShell refuses to run the downloaded script, unblock it once with `Unblock-File $env:USERPROFILE\ssh.ps1`.
To update later, download `ssh.ps1` again and replace the old one: your `ssh-config-menu`, backups and scp history are separate files and are kept.
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

