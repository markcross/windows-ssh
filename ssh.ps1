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

# --- Main menu loop ---
do {
    Clear-Host
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
    Write-Host "                  < up   > down   , top   . bottom" -ForegroundColor DarkGray
    Write-Host "On its own:       x exit   REVERT undo last change" -ForegroundColor DarkGray
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
        elseif ($choiceRaw -match '^revert$') {
            $action = "revert"
            $isValid = $true
        }
        elseif ($choiceRaw -match '^(\d+)([e+\-<>,.d])$') {
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