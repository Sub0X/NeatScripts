#Requires -RunAsAdministrator

$showHelp = $false
$Directory = "$env:USERPROFILE\.ssh\keys"
$Username = $env:USERNAME

for ($i = 0; $i -lt $args.Count; $i++) {
    switch -regex ($args[$i]) {
        '^(-|--)(h|help)$' { $showHelp = $true }
        '^(-|--)(d|directory)$' { 
            $Directory = $args[++$i]
            if (-not $Directory) { 
                Write-Error "Directory parameter requires a value."
                exit 1
            }
        }
        '^(-|--)(u|username)$' { 
            $Username = $args[++$i]
            if (-not $Username) { 
                Write-Error "Username parameter requires a value."
                exit 1
            }
        }
    }
}

if ($showHelp) {
    Write-Host @"
Usage: .\refreshPerms.ps1 [-d <path>] [-u <user>] [-h]

    -d, -directory   The full path to the SSH key directory.
                     Default: `"$Directory`"

    -u, -username    The username to grant FullControl.
                     Default: current user (`"$env:USERNAME`")

    -h, -help        Display this help message and exit.
"@
    exit
}


# If the user explicitly passed a different Directory or Username, let them know:
if ($PSBoundParameters.ContainsKey('Directory')) {
    Write-Host "Using custom directory: '$Directory' (instead of default `$env:USERPROFILE\.ssh`)."
}
if ($PSBoundParameters.ContainsKey('Username') -and $Username -ne $env:USERNAME) {
    Write-Host "Overriding default user. Permissions will be granted to '$Username' instead of current user '$env:USERNAME'."
}

# Fix variable name inconsistencies - use the parameter names throughout
$KeyDirectory = $Directory
$TargetUser = $Username

Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host "WARNING: This script will RECURSIVELY change permissions for FILES" -ForegroundColor Yellow
Write-Host "         within the directory (and its subdirectories):" -ForegroundColor Yellow
Write-Host "         $KeyDirectory" -ForegroundColor Cyan
Write-Host
Write-Host "         It is intended for SSH private key files." -ForegroundColor Yellow
Write-Host "         Applying this to other types of files could have unintended" -ForegroundColor Yellow
Write-Host "         consequences or break application functionality." -ForegroundColor Yellow
Write-Host
Write-Host "         Permissions will be set to allow Full Control for:" -ForegroundColor Yellow
Write-Host "         - User: $TargetUser" -ForegroundColor Cyan
Write-Host "         - SYSTEM" -ForegroundColor Cyan
Write-Host "         - Administrators" -ForegroundColor Cyan
Write-Host "         And will attempt to remove access for Everyone, Authenticated Users," -ForegroundColor Yellow
Write-Host "         and Users." -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host

$confirmation = Read-Host "Are you absolutely sure you want to continue? (Yes/No)"

if ($confirmation.ToLower() -notin @('y', 'yes')) {
    Write-Host "Operation cancelled by user." -ForegroundColor Green
    exit
}

Write-Host "Proceeding with permission changes..." -ForegroundColor Green
Write-Host

if (-not (Test-Path $KeyDirectory)) {
    Write-Error "The specified KeyDirectory does not exist: $KeyDirectory"
    exit 1
}

# Get all files recursively, excluding directories and reparse points (symlinks)
$filesToProcess = Get-ChildItem -Path $KeyDirectory -Recurse -File | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

if ($filesToProcess.Count -eq 0) {
    Write-Host "No files found to process in $KeyDirectory." -ForegroundColor Yellow
    exit
}

foreach ($file in $filesToProcess) {
    Write-Host "-----------------------------------------"
    Write-Host "Processing File: $($file.FullName)" -ForegroundColor White

    try {
        Write-Host "  - Creating new ACL for $($file.FullName)..."
        # Create a new, clean FileSecurity object. This object will not have any inherited ACEs.
        $newAcl = New-Object System.Security.AccessControl.FileSecurity

        # Set the owner to the target user. This is good practice.
        # The script needs to run as Administrator to set the owner if it's not the current user.
        try {
            $ownerAccount = New-Object System.Security.Principal.NTAccount($TargetUser)
            $newAcl.SetOwner($ownerAccount)
            Write-Host "    - Owner set to $TargetUser"
        } catch {
            Write-Warning "    - Could not set owner to $TargetUser for $($file.FullName). Error: $($_.Exception.Message)"
            Write-Warning "    - This might be okay if permissions are set correctly by an Administrator."
        }
        
        # Define the access rules we want to apply
        $ruleUser = New-Object System.Security.AccessControl.FileSystemAccessRule($TargetUser, "FullControl", "Allow")
        $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
        $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "Allow")

        # Add these rules to the new ACL.
        # Using SetAccessRule ensures these are the defined rules for these identities.
        $newAcl.SetAccessRule($ruleUser)
        $newAcl.SetAccessRule($ruleSystem)
        $newAcl.SetAccessRule($ruleAdmins)
        Write-Host "    - Access rules for $TargetUser, SYSTEM, Administrators prepared."

        # Explicitly disable inheritance on this new ACL.
        # $true = isProtected (disables inheritance)
        # $false = preserveInheritance (removes any ACEs that would have been inherited - for a new object, this is clean)
        $newAcl.SetAccessRuleProtection($true, $false)
        Write-Host "    - Inheritance disabled on new ACL."
        
        # Apply this newly constructed ACL to the file.
        # This completely replaces the old ACL on the file.
        Set-Acl -Path $file.FullName -AclObject $newAcl
        Write-Host "  Permissions successfully and exclusively set for: $($file.FullName)" -ForegroundColor Green

    } catch {
        Write-Error "Failed to set permissions for: $($file.FullName). Error: $($_.Exception.Message)"
        Write-Error "Details: $($_.Exception.ToString())" # More detailed error
    }
}

Write-Host "-----------------------------------------"
Write-Host
Write-Host "Permission script finished." -ForegroundColor Green
