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

# --- Read and parse config ---
$sshDir = ""
$privateKeys = @()
$hosts = @()

# Only cmdlets here, no direct .NET calls: corporate machines often run PowerShell
# in Constrained Language Mode, which blocks things like [IO.File]::ReadAllText.
# Save-ConfigLine reads the file the same way, so line numbers always match.
$configLines = @(Get-Content -LiteralPath $ConfigFile)

for ($lineNo = 0; $lineNo -lt $configLines.Count; $lineNo++) {
    $line = $configLines[$lineNo].Trim()

    if ($line -match '^\s*\.ssh\s*=\s*"(.*?)"') {
        $sshDir = $Matches[1] -replace '\$env:USERPROFILE', $env:USERPROFILE
        $sshDir = $sshDir.Trim('"')
    }
    elseif ($line -ne "" -and $line -notmatch '#' -and ($line -match '\.pem' -or $line -match 'id_')) {
        $privateKeys += $line
    }
    elseif ($line -ne "" -and $line -notmatch '^#' -and $line -match '^[^#]+(#[^#]+){3,4}$') {
        $hosts += @{ Text = $line; LineNo = $lineNo }
    }
}

if (-not $sshDir) { $sshDir = "$env:USERPROFILE\.ssh" }
$sshDir = $sshDir.TrimEnd('\')

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

# --- Edit an entry (menu "<n>m") ---
function Save-ConfigLine {
    param($path, $lineNo, $newText)
    # Cmdlets only (Constrained Language Mode safe). Every other line is written
    # back unchanged. Write with the same encoding Get-Content read it with:
    # UTF-8 if the file has a UTF-8 BOM, otherwise the Windows default.
    $lines = @(Get-Content -LiteralPath $path)
    $lines[$lineNo] = $newText
    $firstBytes = @(Get-Content -LiteralPath $path -Encoding Byte -TotalCount 3 -ErrorAction SilentlyContinue)
    $hasBom = $firstBytes.Count -eq 3 -and $firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF
    $encoding = if ($hasBom) { "UTF8" } else { "Default" }
    Copy-Item -LiteralPath $path -Destination "$path.bak" -Force
    Set-Content -LiteralPath $path -Value $lines -Encoding $encoding -ErrorAction Stop
}

function Read-Field {
    param($label, $current, [switch]$AllowClear)
    while ($true) {
        $answer = Read-Host ("  {0,-8} [{1}]" -f $label, $current)
        if ($null -eq $answer) { $answer = "" }
        $answer = $answer.Trim()
        if ($answer -eq "") { return $current }
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

function Edit-MenuEntry {
    param($index, $entry)
    Write-Host ("`n✏️  Editing entry [{0}]  (press Enter to keep the current value)" -f $index) -ForegroundColor Cyan
    Write-Host "    For Folder, type - to remove it.`n"

    $alias    = Read-Field "Alias"    $entry.Alias
    $hostName = Read-Field "Host"     $entry.Host
    $userName = Read-Field "Username" $entry.Username
    $keyName  = Read-Field "Key"      $entry.Keyname
    $folder   = Read-Field "Folder"   $entry.Folder -AllowClear

    if (-not (Test-Path "$sshDir\$keyName")) {
        Write-Host "`n  ⚠️ Key file not found: $sshDir\$keyName" -ForegroundColor Yellow
    }

    $newLine = "$alias#$hostName#$userName#$keyName"
    if ($folder) { $newLine += "#$folder" }
    $oldLine = $hosts[$entry.HostIdx].Text

    if ($newLine -eq $oldLine) {
        Write-Host "`n  No changes made."
        return
    }

    Write-Host "`n  Old: $oldLine"
    Write-Host "  New: $newLine" -ForegroundColor Green
    $confirm = Read-Host "`nSave? (y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "  Not saved."
        return
    }

    try {
        Save-ConfigLine $ConfigFile $hosts[$entry.HostIdx].LineNo $newLine
        $hosts[$entry.HostIdx].Text = $newLine
        Write-Host "✅ Saved. (Backup: $ConfigFile.bak)" -ForegroundColor Green
    } catch {
        Write-Host "❌ Couldn't save: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Main menu loop ---
do {
    Clear-Host
    $menuItems = Build-MenuItems $hosts $sshDir
    $exitIndex = $menuItems.Count
    $configIndex = $exitIndex + 1  # New menu index for config editor

    Write-Host "`n📡 SSH Quick Connect Menu" -ForegroundColor Cyan
    if ($menuItems.Count -eq 0) {
        Write-Host "⚠️ No host entries found in $ConfigFile" -ForegroundColor Yellow
        Write-Host "   Expected lines like: Alias#Host#Username#Keyname[#Folder]" -ForegroundColor Yellow
    }
    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        $entry = $menuItems[$i]
        $target = "{0}@{1}" -f $entry.Username, $entry.Host
        if ($entry.Folder) { $target += ":" + $entry.Folder }
        Write-Host ("[{0}] {1} ({2}) [key: {3}]" -f $i, $target, $entry.Alias, $entry.Keyname)
    }
    Write-Host ("[{0}] Exit" -f $exitIndex)
    Write-Host ("[{0}] Configure SSH Menu (edit config file)" -f $configIndex)
    Write-Host "`nTip: add m to edit an entry, e.g. 0m" -ForegroundColor DarkGray

    $editMode = $false
    do {
        $choiceRaw = (Read-Host "`nEnter the number of your choice").Trim()
        $isValid = $false
        if ($choiceRaw -match '^(\d+)m$') {
            $editMode = $true
            $isValid = [int]$Matches[1] -lt $exitIndex
            $choiceRaw = $Matches[1]
            if (-not $isValid) {
                Write-Host "❌ Only host entries can be edited: 0m to $($exitIndex - 1)m."
            }
        }
        else {
            $editMode = $false
            $isValid = $choiceRaw -match '^\d+$' -and [int]$choiceRaw -ge 0 -and [int]$choiceRaw -le $configIndex
            if (-not $isValid) {
                Write-Host "❌ Invalid choice. Enter a number between 0 and $configIndex, or e.g. 0m to edit."
            }
        }
    } while (-not $isValid)

    $choice = [int]$choiceRaw

    if ($editMode) {
        Edit-MenuEntry $choice $menuItems[$choice]
        Write-Host "`nPress Enter to return to menu..."
        [void](Read-Host)
        continue
    }

    if ($choice -eq $exitIndex) {
        Write-Host "`n👋 Exiting."
        break
    }
    elseif ($choice -eq $configIndex) {
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