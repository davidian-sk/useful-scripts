# --- Check/Install Posh-SSH Module ---
# This part needs to run as Admin the first time
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH module not found. Attempting to install..."
    try {
        # Install for all users. Using -Scope CurrentUser is also fine if not admin.
        Install-Module -Name Posh-SSH -Scope AllUsers -Force -SkipPublisherCheck -Confirm:$false
        Write-Host "Posh-SSH installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Posh-SSH module. Please run 'Install-Module -Name Posh-SSH' manually from an Admin PowerShell."
        return # Stop the script
    }
}
Import-Module Posh-SSH

# --- Configuration ---
$serversFile = "$PSScriptRoot\servers.txt" # Looks for servers.txt in the same folder as the .ps1 script
$user = "david.smidke"
$sshDir = "$env:USERPROFILE\.ssh"
# --- End of Configuration ---


# --- Select Public Key ---
$pubKeys = Get-ChildItem -Path $sshDir -Filter "*.pub"

if ($pubKeys.Count -eq 0) {
    Write-Warning "No .pub files found in your .ssh directory ($sshDir)."
    # Fallback: Ask user to provide the path manually
    while (-not (Test-Path $keyFile)) {
        $keyFile = Read-Host "Please enter the full path to your public key file (e.g., C:\Users\YourName\.ssh\id_ed25519.pub)"
    }
}
else {
    # --- THIS IS THE FIXED LINE ---
    Write-Host "Found the following public keys in ${sshDir}:" -ForegroundColor Green
    
    # List all found .pub files
    for ($i = 0; $i -lt $pubKeys.Count; $i++) {
        Write-Host "  [$($i+1)] $($pubKeys[$i].Name)"
    }

    # Loop until user provides a valid number
    $choice = 0
    while ($choice -lt 1 -or $choice -gt $pubKeys.Count) {
        $input = Read-Host "Please select a key to use (enter a number 1-$($pubKeys.Count))"
        # Try to convert input to a number
        [int]::TryParse($input, [ref]$choice) | Out-Null
        
        if ($choice -lt 1 -or $choice -gt $pubKeys.Count) {
            Write-Warning "Invalid selection. Please enter a number between 1 and $($pubKeys.Count)."
        }
    }
    
    # Set the chosen key file path
    $keyFile = $pubKeys[$choice - 1].FullName
    Write-Host "Using key: $keyFile" -ForegroundColor Cyan
}


# --- Validate Server List Path ---
while (-not (Test-Path $serversFile)) {
    Write-Warning "Server list file not found at: $serversFile"
    Write-Warning "Please make sure 'servers.txt' is in the same folder as this script."
    $serversFile = Read-Host "Or, enter the full path to your servers.txt file"
}

# --- Read Files (now that paths are validated) ---
try {
    $pubKey = Get-Content -Path $keyFile -Raw
    Write-Host "Successfully loaded key file from $keyFile" -ForegroundColor Cyan
}
catch {
    Write-Error "Error: Could not read public key file at '$keyFile'. Check permissions."
    return
}

try {
    $ipAddresses = Get-Content -Path $serversFile
    Write-Host "Successfully loaded server list from $serversFile" -ForegroundColor Cyan
}
catch {
    Write-Error "Error: Could not read server list file at '$serversFile'. Check permissions."
    return
}

# 1. Get the password ONCE and store it securely
$credential = Get-Credential -UserName $user -Message "Enter the password for '$user' (will be used for all servers):"

# Remote command (same as before)
$remoteCommand = "umask 077; mkdir -p .ssh; echo '$pubKey' >> .ssh/authorized_keys; chmod 700 .ssh; chmod 600 .ssh/authorized_keys"

# Loop through each IP
foreach ($ip in $ipAddresses) {
    $ip = $ip.Trim()
    
    if (-not [string]::IsNullOrWhiteSpace($ip)) {
        Write-Host "Connecting to $ip..."
        $session = $null # Clear session variable
        
        try {
            # 2. Create a new SSH session using the saved credential
            # -AcceptKey auto-accepts the server's host key. 
            
            $session = New-SSHSession -ComputerName $ip -Credential $credential -AcceptKey -ErrorAction Stop
            
            if ($session) {
                Write-Host "Successfully connected! Copying key..."
                
                # 3. Run the command in the established session
                Invoke-SSHCommand -SSHSession $session -Command $remoteCommand
                
                Write-Host "Successfully copied key to $ip!" -ForegroundColor Green
            }
        }
        catch {
            Write-Error "Failed to connect or copy key to $ip. Error: $($_.Exception.Message)"
            Write-Warning "This could be a wrong password or the server might be offline."
        }
        finally {
            # 4. Clean up and close the session
            if ($session) {
                Remove-SSHSession -SSHSession $session
            }
        }
        Write-Host "--------------------------------"
    }
}

Write-Host "All done!"
