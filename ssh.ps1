# ssh.ps1 — SSH Key Launcher (with alias support and menu)
# https://github.com/markcross/windows-ssh

#   wt.exe powershell -NoExit -File "C:\Users\mark.cross\ssh.ps1"
#   doesn't work

$ConfigFile = "$env:USERPROFILE\ssh-config-menu"

# --- Detect if we should add keys ---
$ShouldAddKeys = $false
if ($args.Length -gt 0 -and $args[0].ToLower() -eq 'add') {
    $ShouldAddKeys = $true
}
# `ssh.ps1 keys` opens the key window (what kl launches)
$KeyMode = $args.Length -gt 0 -and $args[0].ToLower() -eq 'keys'

if (-not (Test-Path $ConfigFile)) {
    Write-Host "❌ Config file not found: $ConfigFile"
    exit 1
}

# NOTE: cmdlets only below, no direct .NET calls ([IO.File]::..., New-Object,
# [Console]::...). Corporate machines often run PowerShell in Constrained
# Language Mode, which blocks them.

$BackupCount = 10   # ssh-config-menu.bak.1 (newest) .. .bak.10 (oldest)

# --- Read and parse config ---
# Sets $sshDir, $privateKeys and $hosts (each host remembers its line number in
# the file). Called again after every change made from the menu.
function Read-Config {
    $script:sshDir = ""
    $script:privateKeys = @()
    $script:hosts = @()

    $configLines = @(Get-Content -LiteralPath $ConfigFile)
    for ($lineNo = 0; $lineNo -lt $configLines.Count; $lineNo++) {
        $line = $configLines[$lineNo].Trim()

        if ($line -match '^\s*\.ssh\s*=\s*"(.*?)"') {
            $dir = $Matches[1] -replace '\$env:USERPROFILE', $env:USERPROFILE
            $script:sshDir = $dir.Trim('"')
        }
        elseif ($line -ne "" -and $line -notmatch '#' -and ($line -match '\.pem' -or $line -match 'id_')) {
            $script:privateKeys += $line
        }
        elseif ($line -ne "" -and $line -notmatch '^#' -and $line -match '^[^#]+(#[^#]+){3,4}$') {
            $script:hosts += @{ Text = $line; LineNo = $lineNo }
        }
    }

    if (-not $script:sshDir) { $script:sshDir = "$env:USERPROFILE\.ssh" }
    $script:sshDir = $script:sshDir.TrimEnd('\')
}

Read-Config

# --- Writing the config, with rotating backups ---
function Get-ConfigEncoding {
    # Write back with the encoding Get-Content read it with:
    # UTF-8 if the file has a UTF-8 BOM, otherwise the Windows default.
    $firstBytes = @(Get-Content -LiteralPath $ConfigFile -Encoding Byte -TotalCount 3 -ErrorAction SilentlyContinue)
    $hasBom = $firstBytes.Count -eq 3 -and $firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF
    if ($hasBom) { return "UTF8" } else { return "Default" }
}

function Backup-Config {
    # .bak.9 -> .bak.10, ..., .bak.1 -> .bak.2, then current file -> .bak.1
    for ($i = $BackupCount - 1; $i -ge 1; $i--) {
        if (Test-Path -LiteralPath "$ConfigFile.bak.$i") {
            Move-Item -LiteralPath "$ConfigFile.bak.$i" -Destination "$ConfigFile.bak.$($i + 1)" -Force
        }
    }
    Copy-Item -LiteralPath $ConfigFile -Destination "$ConfigFile.bak.1" -Force
}

function Write-Config {
    param($lines)
    $encoding = Get-ConfigEncoding
    Backup-Config
    Set-Content -LiteralPath $ConfigFile -Value $lines -Encoding $encoding -ErrorAction Stop
    Read-Config
}

function Restore-Config {
    # REVERT: put .bak.1 back, then shift the rest up (.bak.2 -> .bak.1, ...),
    # so typing REVERT again steps back one more change.
    $newest = "$ConfigFile.bak.1"
    if (-not (Test-Path -LiteralPath $newest)) {
        Set-Status "❌ No backup to revert to ($newest not found)." Red
        return
    }
    $when = (Get-Item -LiteralPath $newest).LastWriteTime
    Write-Host "`n↩️  Revert ssh-config-menu to the version saved $when ?"
    if (-not (Confirm-YesNo "Revert? (y/N)")) {
        Set-Status "Revert cancelled." DarkGray
        return
    }
    Copy-Item -LiteralPath $newest -Destination $ConfigFile -Force
    Remove-Item -LiteralPath $newest -Force
    for ($i = 2; $i -le $BackupCount; $i++) {
        if (Test-Path -LiteralPath "$ConfigFile.bak.$i") {
            Move-Item -LiteralPath "$ConfigFile.bak.$i" -Destination "$ConfigFile.bak.$($i - 1)" -Force
        }
    }
    Read-Config
    Set-Status "✅ Reverted to the version saved $when." Green
}


# --- Load all SSH keys ---
function Get-LoadedKeys {
    try {
        return (& ssh-add -L 2>$null)
    } catch {
        return @()
    }
}

$LoadedKeys = Get-LoadedKeys

function Ensure-All-Keys-Added {
    param($keyList, $sshDir)
    foreach ($keyName in $keyList) {
        $keyPath = "$sshDir\$keyName"
        if (-not (Test-Path $keyPath)) {
            Write-Host "⚠️ Key not found: $keyPath" -ForegroundColor Yellow
            continue
        }
        $isLoaded = $false
        foreach ($line in $LoadedKeys) {
            if ($line -like "*$keyName*") { $isLoaded = $true; break }
        }
        if (-not $isLoaded) {
            Write-Host "`n🔐 Adding SSH key: $keyPath"
            & ssh-add "$keyPath"
            $LoadedKeys = Get-LoadedKeys
        }
    }
}

# --- Show loaded keys (skipped in the key window) ---
if (-not $KeyMode) {
    # --- Only add keys if requested ---
    if ($ShouldAddKeys) {
        Ensure-All-Keys-Added -keyList $privateKeys -sshDir $sshDir
    }

    Write-Host "`n✅ Currently loaded SSH keys (via ssh-agent):" -ForegroundColor Green
    try {
        $agentKeys = & ssh-add -L
        if ($agentKeys.Count -eq 0) {
            Write-Host "❌ No keys currently loaded in ssh-agent." -ForegroundColor Red
        } else {
            $agentKeys | ForEach-Object { Write-Host "  • $_" }
        }
    } catch {
        Write-Host "⚠️ Unable to retrieve keys from ssh-agent." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 3
}

# --- Build host menu items ---
function Build-MenuItems {
    param($hosts, $sshDir)
    $items = @()
    for ($h = 0; $h -lt $hosts.Count; $h++) {
        $parts = $hosts[$h].Text -split '#'
        if ($parts.Count -eq 4 -or $parts.Count -eq 5) {
            $folder = ""
            if ($parts.Count -eq 5) { $folder = $parts[4].Trim() }
            $items += @{
                Alias    = $parts[0]
                Host     = $parts[1]
                Username = $parts[2]
                Keyname  = $parts[3]
                KeyPath  = "$sshDir\$($parts[3])"
                Folder   = $folder
                HostIdx  = $h
            }
        }
    }
    return $items
}

# --- Status line shown under the menu after an action ---
$StatusText = ""
$StatusColor = "Gray"
function Set-Status {
    param($text, $color = "Gray")
    $script:StatusText = $text
    $script:StatusColor = $color
}

function Confirm-YesNo {
    param($prompt)
    $answer = Read-Host "`n$prompt"
    return ($answer -match '^(y|yes)$')
}

# --- Entry editing: <n>e edit, <n>+ insert above, <n>- insert below ---
function Read-Field {
    param($label, $current, [switch]$AllowClear)
    while ($true) {
        $answer = Read-Host ("  {0,-8} [{1}]" -f $label, $current)
        if ($null -eq $answer) { $answer = "" }
        $answer = $answer.Trim()
        if ($answer -eq "") {
            if ($current -eq "" -and -not $AllowClear) {
                Write-Host "    ❌ $label is required." -ForegroundColor Red
                continue
            }
            return $current
        }
        if ($AllowClear -and $answer -eq "-") { return "" }
        if ($answer -match '#') {
            Write-Host "    ❌ '#' isn't allowed (it separates the fields). Try again." -ForegroundColor Red
            continue
        }
        if ($AllowClear -and $answer -match '\s') {
            Write-Host "    ❌ Folder can't contain spaces. Try again." -ForegroundColor Red
            continue
        }
        return $answer
    }
}

# Asks for each field, starting from $start's values; returns the config line.
function Read-EntryFields {
    param($title, $start)
    Write-Host "`n$title  (press Enter to keep the value shown)" -ForegroundColor Cyan
    Write-Host "    For Folder, type - to remove it.`n"

    $alias    = Read-Field "Alias"    $start.Alias
    $hostName = Read-Field "Host"     $start.Host
    $userName = Read-Field "Username" $start.Username
    $keyName  = Read-Field "Key"      $start.Keyname
    $folder   = Read-Field "Folder"   $start.Folder -AllowClear

    if (-not (Test-Path "$sshDir\$keyName")) {
        Write-Host "`n  ⚠️ Key file not found: $sshDir\$keyName" -ForegroundColor Yellow
    }

    $newLine = "$alias#$hostName#$userName#$keyName"
    if ($folder) { $newLine += "#$folder" }
    return $newLine
}

function Edit-Entry {
    param($index, $entry)
    $oldLine = $hosts[$entry.HostIdx].Text
    $newLine = Read-EntryFields ("✏️  Editing entry [{0}]" -f $index) $entry

    if ($newLine -eq $oldLine) {
        Set-Status "No changes made to [$index]." DarkGray
        return
    }
    Write-Host "`n  Old: $oldLine"
    Write-Host "  New: $newLine" -ForegroundColor Green
    if (-not (Confirm-YesNo "Save? (y/N)")) {
        Set-Status "Edit of [$index] not saved." DarkGray
        return
    }
    $lines = @(Get-Content -LiteralPath $ConfigFile)
    $lines[$hosts[$entry.HostIdx].LineNo] = $newLine
    Write-Config $lines
    Set-Status "✅ Saved [$index]." Green
}

function Insert-Entry {
    param($index, $entry, [switch]$Below)
    # The new entry starts as a copy of the one it's inserted next to.
    if ($entry) {
        $start = $entry
        $where = if ($Below) { "below [$index]" } else { "above [$index]" }
    } else {
        $start = @{ Alias = ""; Host = ""; Username = ""; Keyname = ""; Folder = "" }
        $where = "as the first entry"
    }
    $newLine = Read-EntryFields "➕ New entry $where" $start

    Write-Host "`n  New: $newLine" -ForegroundColor Green
    if (-not (Confirm-YesNo "Insert? (y/N)")) {
        Set-Status "Nothing inserted." DarkGray
        return
    }

    $lines = @(Get-Content -LiteralPath $ConfigFile)
    if ($entry) {
        $at = $hosts[$entry.HostIdx].LineNo
        if ($Below) { $at++ }
    } else {
        $at = $lines.Count   # no hosts yet: add at the end of the file
    }
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $at) { $out += $newLine }
        $out += $lines[$i]
    }
    if ($at -ge $lines.Count) { $out += $newLine }
    Write-Config $out
    Set-Status "✅ Inserted $where." Green
}

function Remove-Entry {
    param($index, $entry)
    $line = $hosts[$entry.HostIdx].Text
    Write-Host "`n🗑️  Delete entry [$index]?" -ForegroundColor Yellow
    Write-Host "  $line"
    $answer = Read-Host "`nAre you sure? Type YES (in capitals) to delete"
    if ($answer -cne "YES") {
        Set-Status "Delete cancelled." DarkGray
        return
    }
    $skip = $hosts[$entry.HostIdx].LineNo
    $lines = @(Get-Content -LiteralPath $ConfigFile)
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -ne $skip) { $out += $lines[$i] }
    }
    Write-Config $out
    Set-Status "✅ Deleted: $line" Green
}

# Moves host entry $from to position $to. Only host lines are reordered: key
# lines, comments and blank lines stay where they are in the file.
function Move-Entry {
    param($from, $to)
    $count = $hosts.Count
    if ($to -lt 0) { $to = 0 }
    if ($to -gt $count - 1) { $to = $count - 1 }
    if ($from -eq $to) {
        Set-Status "[$from] is already there." DarkGray
        return
    }

    $moving = $hosts[$from].Text
    $rest = @()
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -ne $from) { $rest += $hosts[$i].Text }
    }
    $order = @()
    for ($i = 0; $i -lt $rest.Count; $i++) {
        if ($i -eq $to) { $order += $moving }
        $order += $rest[$i]
    }
    if ($to -ge $rest.Count) { $order += $moving }

    $lines = @(Get-Content -LiteralPath $ConfigFile)
    for ($k = 0; $k -lt $count; $k++) {
        $lines[$hosts[$k].LineNo] = $order[$k]
    }
    Write-Config $lines
    Set-Status "✅ Moved [$from] to [$to]." Green
}

# --- SSH key management ---
# ka = add a key pair (main menu and key window)
# kl = open the key window: `ssh.ps1 keys` in a new PowerShell window, where
#      <n>e edits a key's comment and <n>d deletes a key.

function Get-Today { return (Get-Date -Format "yyyy-MM-dd") }

# Is this a key line in ssh-config-menu? (same rule as Read-Config)
function Test-KeyLine {
    param($line)
    $t = $line.Trim()
    return ($t -ne "" -and $t -notmatch '#' -and ($t -match '\.pem' -or $t -match 'id_'))
}

# One entry per key in $sshDir: found from *.pub files, plus private keys
# (files starting -----BEGIN ... PRIVATE KEY-----) that have no .pub.
function Get-KeyFiles {
    $files = @(Get-ChildItem -LiteralPath $sshDir -File -ErrorAction SilentlyContinue)
    $names = @()
    foreach ($f in $files) {
        if ($f.Name -like "*.pub") { $names += $f.Name.Substring(0, $f.Name.Length - 4) }
    }
    foreach ($f in $files) {
        if ($f.Name -like "*.pub" -or $names -contains $f.Name) { continue }
        $first = Get-Content -LiteralPath $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue
        if ($first -match '^-----BEGIN .*PRIVATE KEY-----') { $names += $f.Name }
    }
    $names = @($names | Sort-Object)

    $agentList = @(& ssh-add -l 2>$null)
    $keys = @()
    foreach ($name in $names) {
        $priv = "$sshDir\$name"
        $pub = "$priv.pub"
        $key = @{
            Name = $name; Private = $priv; Public = $pub
            HasPrivate = (Test-Path -LiteralPath $priv); HasPublic = (Test-Path -LiteralPath $pub)
            Type = "?"; Bits = ""; Comment = ""; Fingerprint = ""; Loaded = $false
            InKeyList = ($privateKeys -contains $name); UsedBy = @()
        }
        if ($key.HasPublic) {
            # "256 SHA256:abc... the comment (ED25519)"
            $info = @(& ssh-keygen -l -f $pub 2>$null) | Select-Object -First 1
            if ($info -match '^(\d+)\s+(\S+)\s+(.*)\s+\(([^)]+)\)$') {
                $key.Bits = $Matches[1]; $key.Fingerprint = $Matches[2]
                $key.Comment = $Matches[3]; $key.Type = $Matches[4]
                if ($key.Comment -eq "no comment") { $key.Comment = "" }
            }
        }
        if ($key.Fingerprint) {
            $fp = $key.Fingerprint
            $key.Loaded = @($agentList | Where-Object { $_ -like "*$fp*" }).Count -gt 0
        }
        foreach ($h in $hosts) {
            $parts = $h.Text -split '#'
            if ($parts[3] -eq $name) { $key.UsedBy += $parts[0] }
        }
        $keys += $key
    }
    return $keys
}

function New-KeyPair {
    Write-Host "`n🔑 Create a new key pair  (press Enter to accept the value shown)" -ForegroundColor Cyan

    Write-Host "  Types: [1] ed25519 (recommended)   [2] ecdsa   [3] rsa"
    while ($true) {
        $answer = (Read-Host "  Type     [1]").Trim()
        if ($answer -eq "" -or $answer -eq "1" -or $answer -eq "ed25519") { $type = "ed25519"; break }
        if ($answer -eq "2" -or $answer -eq "ecdsa") { $type = "ecdsa"; break }
        if ($answer -eq "3" -or $answer -eq "rsa") { $type = "rsa"; break }
        Write-Host "    ❌ Enter 1, 2 or 3." -ForegroundColor Red
    }

    $bits = ""
    if ($type -eq "ed25519") {
        Write-Host "  Length   256 (fixed for ed25519)"
    } else {
        if ($type -eq "ecdsa") { $allowed = @("256", "384", "521"); $default = "256" }
        else                   { $allowed = @("2048", "3072", "4096"); $default = "4096" }
        while ($true) {
            $answer = (Read-Host ("  Length   [{0}]  ({1})" -f $default, ($allowed -join " / "))).Trim()
            if ($answer -eq "") { $bits = $default; break }
            if ($allowed -contains $answer) { $bits = $answer; break }
            Write-Host "    ❌ Choose one of: $($allowed -join ', ')" -ForegroundColor Red
        }
    }

    $today = Get-Today
    $defaultName = "id_$($type)_$today"
    while ($true) {
        $name = (Read-Host "  Name     [$defaultName]").Trim()
        if ($name -eq "") { $name = $defaultName }
        if ($name -notmatch '^[A-Za-z0-9._-]+$') {
            Write-Host "    ❌ Use letters, numbers, . _ and - only." -ForegroundColor Red
            continue
        }
        if ($name -notmatch 'id_') {
            # ssh-config-menu only treats lines containing id_ (or .pem) as keys
            Write-Host "    ❌ The name must contain id_ (e.g. id_ed25519_work) so the menu treats it as a key." -ForegroundColor Red
            continue
        }
        if ((Test-Path -LiteralPath "$sshDir\$name") -or (Test-Path -LiteralPath "$sshDir\$name.pub")) {
            Write-Host "    ❌ $name already exists in $sshDir. Choose another name." -ForegroundColor Red
            continue
        }
        break
    }

    $defaultComment = "$env:USERNAME@$env:COMPUTERNAME $today"
    $comment = (Read-Host "  Comment  [$defaultComment]").Trim()
    if ($comment -eq "") { $comment = $defaultComment }

    $path = "$sshDir\$name"
    $kgArgs = @("-t", $type)
    if ($bits) { $kgArgs += @("-b", $bits) }
    $kgArgs += @("-f", $path, "-C", $comment)

    Write-Host "`n  Running: ssh-keygen $($kgArgs -join ' ')" -ForegroundColor DarkGray
    Write-Host "  ssh-keygen will now ask for a passphrase (Enter twice for none).`n"
    & ssh-keygen @kgArgs

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $path)) {
        Set-Status "❌ ssh-keygen didn't create $name." Red
        return
    }
    Write-Host "`n✅ Created $name and $name.pub" -ForegroundColor Green

    # Add to the key list in ssh-config-menu, after the last key line
    # (or after the .ssh line, or at the top), so `ssh.ps1 add` loads it.
    $lines = @(Get-Content -LiteralPath $ConfigFile)
    $at = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\.ssh\s*=' -and $at -eq 0) { $at = $i + 1 }
        if (Test-KeyLine $lines[$i]) { $at = $i + 1 }
    }
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $at) { $out += $name }
        $out += $lines[$i]
    }
    if ($at -ge $lines.Count) { $out += $name }
    Write-Config $out
    Write-Host "   Added $name to the key list in ssh-config-menu"

    $pubText = (Get-Content -LiteralPath "$path.pub" -TotalCount 1)
    Write-Host "`n   Public key (paste into the server's ~/.ssh/authorized_keys):"
    Write-Host "   $pubText" -ForegroundColor Cyan
    try {
        Set-Clipboard -Value $pubText -ErrorAction Stop
        Write-Host "   📋 Copied to clipboard."
    } catch {
        Write-Host "   (Couldn't copy to the clipboard; copy it from above.)" -ForegroundColor Yellow
    }

    if (Confirm-YesNo "Load it into ssh-agent now? (y/N)") {
        & ssh-add $path
    }
    if (Confirm-YesNo "Install it on one of your menu hosts now? (y/N)") {
        $newKey = @{ Name = $name; Private = $path; Public = "$path.pub"; HasPrivate = $true; HasPublic = $true }
        Install-KeyOnChosenHost $newKey
        return
    }
    Write-Host "`nPress Enter to continue..."
    [void](Read-Host)
    Set-Status "✅ Created $name." Green
}

function Edit-KeyComment {
    param($index, $key)
    if (-not $key.HasPrivate) {
        Set-Status "❌ $($key.Name): the private key isn't in $sshDir, so its comment can't be changed." Red
        return
    }
    Write-Host "`n✏️  Edit comment of key [$index] $($key.Name)  (press Enter to keep it)" -ForegroundColor Cyan
    $new = (Read-Host "  Comment  [$($key.Comment)]").Trim()
    if ($new -eq "" -or $new -eq $key.Comment) {
        Set-Status "No change to [$index]." DarkGray
        return
    }
    Write-Host "`n  ssh-keygen may ask for the key's passphrase.`n" -ForegroundColor DarkGray
    & ssh-keygen -c -C $new -f $key.Private
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nPress Enter to continue..."
        [void](Read-Host)
        Set-Status "❌ ssh-keygen couldn't change the comment of $($key.Name) (see its message above)." Red
        return
    }
    $note = ""
    if ($key.Loaded) { $note = " ssh-agent shows the old comment until the key is loaded again." }
    Set-Status "✅ Comment of $($key.Name) is now: $new.$note" Green
}

function Remove-Key {
    param($index, $key)
    Write-Host "`n🗑️  Delete key [$index] $($key.Name)?" -ForegroundColor Yellow
    if ($key.HasPrivate) { Write-Host "  $($key.Private)" }
    if ($key.HasPublic)  { Write-Host "  $($key.Public)" }
    if ($key.UsedBy.Count -gt 0) {
        Write-Host "`n  ⚠️ Used by menu entries: $($key.UsedBy -join ', ')" -ForegroundColor Yellow
        Write-Host "     They won't be able to connect with this key any more." -ForegroundColor Yellow
    }
    if ($key.InKeyList) { Write-Host "  It will also be removed from the key list in ssh-config-menu." }

    $answer = Read-Host "`nAre you sure? Type YES (in capitals) to delete"
    if ($answer -cne "YES") {
        Set-Status "Delete cancelled." DarkGray
        return
    }

    if ($key.Loaded -and $key.HasPrivate) { & ssh-add -d $key.Private 2>&1 | Out-Null }

    # Moved, not erased: a deleted private key can't be recovered otherwise.
    $bin = "$sshDir\deleted\$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    if ($key.HasPrivate) { Move-Item -LiteralPath $key.Private -Destination $bin -Force }
    if ($key.HasPublic)  { Move-Item -LiteralPath $key.Public  -Destination $bin -Force }

    if ($key.InKeyList) {
        $lines = @(Get-Content -LiteralPath $ConfigFile)
        $out = @()
        foreach ($l in $lines) {
            if (-not ((Test-KeyLine $l) -and $l.Trim() -eq $key.Name)) { $out += $l }
        }
        Write-Config $out
    }
    Set-Status "✅ Deleted $($key.Name) (moved to $bin)." Green
}

# --- Install a public key on a host ---
# Main menu <n>i (pick a key), key window <n>i (pick a host), or after ka.

function Select-FromList {
    param($title, $labels)
    Write-Host "`n$title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $labels.Count; $i++) { Write-Host ("  [{0}] {1}" -f $i, $labels[$i]) }
    while ($true) {
        $answer = (Read-Host "`nNumber (Enter to cancel)").Trim()
        if ($answer -eq "") { return -1 }
        if ($answer -match '^\d+$' -and [int]$answer -lt $labels.Count) { return [int]$answer }
        Write-Host "    ❌ Enter 0 to $($labels.Count - 1)." -ForegroundColor Red
    }
}

function Get-HostLabel {
    param($e)
    return ("{0}@{1} ({2}) [key: {3}]" -f $e.Username, $e.Host, $e.Alias, $e.Keyname)
}

# Run on the server, with the public key line on stdin: strip Windows CRs,
# make sure authorized_keys ends with a newline, then append the key only if
# that exact line isn't already there. Then fix SELinux labels if the server
# uses SELinux (as ssh-copy-id does). No double quotes, so it survives
# Windows PowerShell's argument passing to ssh.exe.
$InstallKeyCommand = 'umask 077; mkdir -p ~/.ssh && tr -d ''\r'' > ~/.ssh/.ssh-ps1-newkey && touch ~/.ssh/authorized_keys && ' +
    'if [ -s ~/.ssh/authorized_keys ] && [ $(tail -c1 ~/.ssh/authorized_keys | wc -l) -eq 0 ]; then echo >> ~/.ssh/authorized_keys; fi; ' +
    'if grep -qxFf ~/.ssh/.ssh-ps1-newkey ~/.ssh/authorized_keys; then echo SSHPS1-ALREADY; ' +
    'else cat ~/.ssh/.ssh-ps1-newkey >> ~/.ssh/authorized_keys && echo SSHPS1-ADDED; fi; rm -f ~/.ssh/.ssh-ps1-newkey; ' +
    'if command -v restorecon >/dev/null 2>&1; then restorecon -F ~/.ssh ~/.ssh/authorized_keys >/dev/null 2>&1; fi'

function Install-PublicKey {
    param($key, $entry, $entryIndex)
    if (-not $key.HasPublic) {
        Set-Status "❌ $($key.Name).pub not found in $sshDir, so there's nothing to install." Red
        return
    }
    $target = "$($entry.Username)@$($entry.Host)"
    Write-Host "`n📤 Install $($key.Name).pub on $target" -ForegroundColor Cyan
    Write-Host "   Signs in the way entry [$entryIndex] does (key $($entry.Keyname)); if that key isn't"
    Write-Host "   accepted, ssh tries your ssh-agent keys and then asks for the password."
    Write-Host "   The key is added to ~/.ssh/authorized_keys on $target unless it's already there."
    if (-not (Confirm-YesNo "Go ahead? (y/N)")) {
        Set-Status "Install cancelled." DarkGray
        return
    }

    $pubLine = Get-Content -LiteralPath $key.Public -TotalCount 1
    Write-Host ""
    $output = @($pubLine | & ssh -i $entry.KeyPath $target $InstallKeyCommand)

    if ($output -contains "SSHPS1-ADDED") {
        Write-Host "✅ Added $($key.Name) to ~/.ssh/authorized_keys on $target" -ForegroundColor Green
    } elseif ($output -contains "SSHPS1-ALREADY") {
        Write-Host "✅ $($key.Name) was already in ~/.ssh/authorized_keys on $target" -ForegroundColor Green
    } else {
        $output | ForEach-Object { Write-Host "   $_" }
        Write-Host "`nPress Enter to continue..."
        [void](Read-Host)
        Set-Status "❌ Couldn't install $($key.Name) on $target (ssh exit code $LASTEXITCODE)." Red
        return
    }

    # Prove the new key works on its own before offering to switch to it.
    Write-Host "`n🔎 Testing sign-in with $($key.Name) only (it may ask for its passphrase)..."
    $test = @(& ssh -i $key.Private -o IdentitiesOnly=yes -o PreferredAuthentications=publickey $target echo SSHPS1-OK)
    if (-not ($test -contains "SSHPS1-OK")) {
        Write-Host "`nPress Enter to continue..."
        [void](Read-Host)
        Set-Status "⚠️ Installed $($key.Name) on $target, but signing in with it failed. Entry [$entryIndex] left unchanged." Yellow
        return
    }
    Write-Host "✅ Signed in with $($key.Name)." -ForegroundColor Green

    if ($entry.Keyname -ne $key.Name) {
        if (Confirm-YesNo "Switch menu entry [$entryIndex] ($($entry.Alias)) to use $($key.Name)? (y/N)") {
            $parts = $hosts[$entry.HostIdx].Text -split '#'
            $parts[3] = $key.Name
            $lines = @(Get-Content -LiteralPath $ConfigFile)
            $lines[$hosts[$entry.HostIdx].LineNo] = $parts -join '#'
            Write-Config $lines
            Set-Status "✅ Installed $($key.Name) on $target and switched entry [$entryIndex] to it." Green
            return
        }
    }
    Set-Status "✅ Installed $($key.Name) on $target and tested it." Green
}

# Pick a host from the menu entries, then install $key there.
function Install-KeyOnChosenHost {
    param($key)
    $entries = @(Build-MenuItems $hosts $sshDir)
    if ($entries.Count -eq 0) {
        Set-Status "❌ There are no menu entries to install on." Red
        return
    }
    $labels = @()
    foreach ($e in $entries) { $labels += (Get-HostLabel $e) }
    $pick = Select-FromList "📤 Install $($key.Name).pub on which host?" $labels
    if ($pick -lt 0) {
        Set-Status "Install cancelled." DarkGray
        return
    }
    Install-PublicKey $key $entries[$pick] $pick
}

# Pick a key from the .ssh folder, then install it on menu entry $index.
function Install-ChosenKeyOnHost {
    param($index, $entry)
    $keys = @(Get-KeyFiles | Where-Object { $_.HasPublic })
    if ($keys.Count -eq 0) {
        Set-Status "❌ No public keys (*.pub) found in $sshDir. ka creates one." Red
        return
    }
    $labels = @()
    foreach ($k in $keys) { $labels += ("{0}  {1} {2}  {3}" -f $k.Name, $k.Type, $k.Bits, $k.Comment) }
    $pick = Select-FromList ("📤 Install which key on [{0}] {1}?" -f $index, (Get-HostLabel $entry)) $labels
    if ($pick -lt 0) {
        Set-Status "Install cancelled." DarkGray
        return
    }
    Install-PublicKey $keys[$pick] $entry $index
}

# The key window (`ssh.ps1 keys`, opened by kl)
function Show-KeyManager {
    while ($true) {
        Clear-Host
        Read-Config
        $keys = @(Get-KeyFiles)

        Write-Host "`n🔑 SSH keys in $sshDir" -ForegroundColor Cyan
        if ($keys.Count -eq 0) { Write-Host "  (no keys found; ka creates one)" -ForegroundColor Yellow }
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k = $keys[$i]
            $size = if ($k.Bits) { "$($k.Type) $($k.Bits)" } else { $k.Type }
            Write-Host ("[{0}] {1}  {2}  {3}" -f $i, $k.Name, $size, $k.Comment)
            $flags = @()
            if ($k.Loaded) { $flags += "loaded in ssh-agent" }
            if ($k.InKeyList) { $flags += "in key list" }
            if ($k.UsedBy.Count -gt 0) { $flags += "used by: $($k.UsedBy -join ', ')" }
            if (-not $k.HasPrivate) { $flags += "no private key file" }
            if (-not $k.HasPublic) { $flags += "no .pub file" }
            if ($flags.Count -gt 0) { Write-Host ("      {0}" -f ($flags -join ' · ')) -ForegroundColor DarkGray }
        }
        Write-Host "`nAfter a number:  e edit comment   d delete   i install on a host" -ForegroundColor DarkGray
        Write-Host "On its own:       ka add key   x close" -ForegroundColor DarkGray
        if ($StatusText) {
            Write-Host "`n$StatusText" -ForegroundColor $StatusColor
            Set-Status ""
        }

        $choiceRaw = (Read-Host "`nEnter your choice").Trim()
        try {
            if ($choiceRaw -match '^x$') { return }
            elseif ($choiceRaw -match '^ka$') { New-KeyPair }
            elseif ($choiceRaw -match '^(\d+)([edi])$') {
                $n = [int]$Matches[1]
                $op = $Matches[2].ToLower()
                if ($n -ge $keys.Count) { Set-Status "❌ No key [$n]." Red }
                elseif ($op -eq "e") { Edit-KeyComment $n $keys[$n] }
                elseif ($op -eq "i") { Install-KeyOnChosenHost $keys[$n] }
                else { Remove-Key $n $keys[$n] }
            }
            elseif ($choiceRaw -ne "") {
                Set-Status "❌ Invalid choice. Try e.g. 0e, 0d, 0i, ka or x." Red
            }
        } catch {
            Set-Status "❌ $($_.Exception.Message)" Red
        }
    }
}

if ($KeyMode) {
    Show-KeyManager
    exit
}

# --- Main menu loop ---
do {
    Clear-Host
    Read-Config   # picks up changes from the key window or Notepad
    $menuItems = Build-MenuItems $hosts $sshDir
    $hostCount = $menuItems.Count
    $configIndex = $hostCount  # Configure comes straight after the hosts (x exits)

    Write-Host "`n📡 SSH Quick Connect Menu" -ForegroundColor Cyan
    if ($menuItems.Count -eq 0) {
        Write-Host "⚠️ No host entries found in $ConfigFile" -ForegroundColor Yellow
        Write-Host "   Expected lines like: Alias#Host#Username#Keyname[#Folder]  (0+ adds one)" -ForegroundColor Yellow
    }
    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        $entry = $menuItems[$i]
        $target = "{0}@{1}" -f $entry.Username, $entry.Host
        if ($entry.Folder) { $target += ":" + $entry.Folder }
        Write-Host ("[{0}] {1} ({2}) [key: {3}]" -f $i, $target, $entry.Alias, $entry.Keyname)
    }
    Write-Host ("[{0}] Configure SSH Menu (edit config file)" -f $configIndex)
    Write-Host "`nAfter a number:  e edit   + insert above   - insert below   d delete" -ForegroundColor DarkGray
    Write-Host "                  < up   > down   , top   . bottom   i install a key on this host" -ForegroundColor DarkGray
    Write-Host "On its own:       x exit   REVERT undo last change   ka add key   kl list keys" -ForegroundColor DarkGray
    if ($StatusText) {
        Write-Host "`n$StatusText" -ForegroundColor $StatusColor
        Set-Status ""
    }

    $action = ""
    do {
        $choiceRaw = (Read-Host "`nEnter the number of your choice").Trim()
        $isValid = $false
        if ($choiceRaw -match '^x$') {
            $action = "exit"
            $isValid = $true
        }
        elseif ($choiceRaw -match '^(ka|kl)$') {
            $action = $choiceRaw.ToLower()
            $isValid = $true
        }
        elseif ($choiceRaw -match '^revert$') {
            $action = "revert"
            $isValid = $true
        }
        elseif ($choiceRaw -match '^(\d+)([e+\-<>,.di])$') {
            $action = $Matches[2].ToLower()
            $choiceRaw = $Matches[1]
            $n = [int]$choiceRaw
            if ($menuItems.Count -eq 0) {
                $isValid = $n -eq 0 -and ($action -eq "+" -or $action -eq "-")
                if (-not $isValid) { Write-Host "❌ There are no entries yet: type 0+ to add one." }
            } else {
                $isValid = $n -lt $hostCount
                if (-not $isValid) { Write-Host "❌ That only works on host entries: 0 to $($hostCount - 1)." }
            }
        }
        else {
            $action = "connect"
            $isValid = $choiceRaw -match '^\d+$' -and [int]$choiceRaw -ge 0 -and [int]$choiceRaw -le $configIndex
            if (-not $isValid) {
                Write-Host "❌ Invalid choice. Enter a number between 0 and $configIndex, x to exit, or e.g. 0e to edit."
            }
        }
    } while (-not $isValid)

    if ($action -eq "exit") {
        Write-Host "`n👋 Exiting."
        break
    }

    if ($action -eq "kl") {
        Start-Process powershell.exe -ArgumentList "-File", "`"$PSCommandPath`"", "keys"
        Set-Status "🔑 Key list opened in a new window." DarkGray
        continue
    }
    if ($action -eq "ka") {
        try { New-KeyPair } catch { Set-Status "❌ $($_.Exception.Message)" Red }
        continue
    }

    if ($action -ne "connect") {
        $entry = $null
        if ($action -ne "revert") {
            $choice = [int]$choiceRaw
            if ($menuItems.Count -gt 0) { $entry = $menuItems[$choice] }
        }
        try {
            switch ($action) {
                "revert" { Restore-Config }
                "e"      { Edit-Entry $choice $entry }
                "+"      { Insert-Entry $choice $entry }
                "-"      { Insert-Entry $choice $entry -Below }
                "d"      { Remove-Entry $choice $entry }
                "i"      { Install-ChosenKeyOnHost $choice $entry }
                "<"      { Move-Entry $choice ($choice - 1) }
                ">"      { Move-Entry $choice ($choice + 1) }
                ","      { Move-Entry $choice 0 }
                "."      { Move-Entry $choice ($hosts.Count - 1) }
            }
        } catch {
            Set-Status "❌ Couldn't save: $($_.Exception.Message)" Red
        }
        continue
    }

    $choice = [int]$choiceRaw

    if ($choice -eq $configIndex) {
        Write-Host "`n📝 Opening config file in Notepad: $ConfigFile"
        Start-Process notepad.exe $ConfigFile
        break
    }

    $selected = $menuItems[$choice]
    $keyPath = $selected.KeyPath
    $user = $selected.Username
    $targetHost = $selected.Host

    $folder = $selected.Folder

    if ($folder) {
        # -t forces an interactive terminal. Start the user's normal login shell,
        # and cd via bash's PROMPT_COMMAND, which runs just before the first prompt:
        # after .bash_profile, so a 'cd' in the profile can't undo it, and aliases
        # defined there still work. It removes itself after running once.
        # '' is an escaped single quote; `$SHELL is expanded by the server, not PowerShell.
        $sshCmd = "ssh -t -i `"$keyPath`" $user@$targetHost 'export PROMPT_COMMAND=''cd $folder; unset PROMPT_COMMAND''; exec `$SHELL -l'"
        Write-Host "`n🚀 Connecting to $user@$targetHost and changing to $folder"
    } else {
        $sshCmd = "ssh -i `"$keyPath`" $user@$targetHost"
        Write-Host "`n🚀 Connecting to $user@$targetHost"
    }
    Write-Host "Running: $sshCmd"

    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", $sshCmd
	# Start-Process wt.exe -ArgumentList "new-tab", "powershell", "-NoExit", "-Command", $sshCmd  # Didn't work to spawn to a tab instead of new window
    
    Write-Host "`nPress Enter to return to menu..."
    [void](Read-Host)
} while ($true)

# I'm currently using Windows Terminal to front WSL 2 Ubuntu. I use it to SSH out to multiple servers.
# I'm now at a point where I'd need to run similar \ identical tasks across multiple servers,
# so I'd like to be able to say Open a new pane and SSH to server Foo, Bar and FooBar.
# I've got the server config stored in .ssh/config and SSH key access sorted.
# 
# https://stackoverflow.com/questions/67381475/windows-terminal-script-opening-panes-and-sshing-to-servers