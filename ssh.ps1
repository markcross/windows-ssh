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

foreach ($lineRaw in Get-Content $ConfigFile) {
    $line = $lineRaw.Trim()

    if ($line -match '^\s*\.ssh\s*=\s*"(.*?)"') {
        $sshDir = $Matches[1] -replace '\$env:USERPROFILE', $env:USERPROFILE
        $sshDir = $sshDir.Trim('"')
    }
    elseif ($line -ne "" -and $line -notmatch '^#' -and ($line -match '\.pem' -or $line -match '^id_')) {
        $privateKeys += $line
    }
    elseif ($line -ne "" -and $line -notmatch '^#' -and $line -match '^[^#]+#[^#]+#[^#]+#[^#]+$') {
        $hosts += $line
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
    foreach ($line in $hosts) {
        $parts = $line -split '#'
        if ($parts.Count -eq 4) {
            $items += @{
                Alias    = $parts[0]
                Host     = $parts[1]
                Username = $parts[2]
                Keyname  = $parts[3]
                KeyPath  = "$sshDir\$($parts[3])"
            }
        }
    }
    return $items
}

# --- Main menu loop ---
do {
    Clear-Host
    $menuItems = Build-MenuItems $hosts $sshDir
    $exitIndex = $menuItems.Count
    $configIndex = $exitIndex + 1  # New menu index for config editor

    Write-Host "`n📡 SSH Quick Connect Menu" -ForegroundColor Cyan
    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        $entry = $menuItems[$i]
        Write-Host ("[{0}] {1}@{2} ({3}) [key: {4}]" -f $i, $entry.Username, $entry.Host, $entry.Alias, $entry.Keyname)
    }
    Write-Host ("[{0}] Exit" -f $exitIndex)
    Write-Host ("[{0}] Configure SSH Menu (edit config file)" -f $configIndex)

    do {
        $choiceRaw = Read-Host "`nEnter the number of your choice"
        $isValid = $choiceRaw -match '^\d+$' -and [int]$choiceRaw -ge 0 -and [int]$choiceRaw -le $configIndex
        if (-not $isValid) {
            Write-Host "❌ Invalid choice. Please enter a number between 0 and $configIndex."
        }
    } while (-not $isValid)

    $choice = [int]$choiceRaw

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

    $sshCmd = "ssh -i `"$keyPath`" $user@$targetHost"
    Write-Host "`n🚀 Connecting to $user@$targetHost"
    Write-Host "Running: $sshCmd"

    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", $sshCmd
	# Start-Process wt.exe -ArgumentList "new-tab", "powershell", "-NoExit", "-Command", $sshCmd  # Didn't work to spawn to a tab instead of new window
    
    Write-Host "`nPress Enter to return to menu..."
    [void][System.Console]::ReadLine()
} while ($true)

# I'm currently using Windows Terminal to front WSL 2 Ubuntu. I use it to SSH out to multiple servers.
# I'm now at a point where I'd need to run similar \ identical tasks across multiple servers,
# so I'd like to be able to say Open a new pane and SSH to server Foo, Bar and FooBar.
# I've got the server config stored in .ssh/config and SSH key access sorted.
# 
# https://stackoverflow.com/questions/67381475/windows-terminal-script-opening-panes-and-sshing-to-servers