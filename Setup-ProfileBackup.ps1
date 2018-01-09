# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal( $myWindowsID )
 
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
 
# Check to see if we are currently running "as Administrator"
if ( $myWindowsPrincipal.IsInRole( $adminRole ) ) {

    # We are running "as Administrator" - so change the title and background color to indicate this
    $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)"
    $Host.UI.RawUI.BackgroundColor = "DarkBlue"
    clear-host

}
else {

    # We are not running "as Administrator" - so relaunch as administrator
   
    # Create a new process object that starts PowerShell
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
   
    # Specify the current script path and name as a parameter
    $newProcess.Arguments = "-NoExit $($myInvocation.MyCommand.Definition)";
   
    # Indicate that the process should be elevated
    $newProcess.Verb = "runas";
   
    # Start the new process
    [System.Diagnostics.Process]::Start( $newProcess );
   
    # Exit from the current, unelevated, process
    exit

}

Set-Location -Path $PSScriptRoot

# configuration file containing items to backup
$BackupConfiguration = "$PSScriptRoot\ProfileBackupItems.ini"

if ( -not ( Test-Path -Path $BackupConfiguration ) ) {

    "# place one backup path on each line" | Out-File -FilePath $BackupConfiguration
    "# paths should be relative to %USERPROFILE%" | Out-File -FilePath $BackupConfiguration -Append
    "# lines starting with '#' and blank lines are ignored" | Out-File -FilePath $BackupConfiguration -Append
    "" | Out-File -FilePath $BackupConfiguration -Append

    Start-Process -FilePath notepad.exe -ArgumentList $BackupConfiguration

    exit

}

$BackupItems = Get-Content $BackupConfiguration | Where-Object { $_ -notmatch "(^#|^\s*$)" }

if ( $BackupItems.Count -eq 0 ) {

    Write-Error "Nothing to backup! Please edit '$PSScriptRoot\BackupItems.txt' and add items to backup."

    exit 1
}

foreach ( $Item in $BackupItems ) {

    $BackupExists = [bool]( Test-Path -Path "$PSScriptRoot\$Item" )
    $BackupSymlink = [bool]( ( Get-Item "$PSScriptRoot\$Item" -Force -ErrorAction SilentlyContinue ).Attributes -band [IO.FileAttributes]::ReparsePoint )
    $ProfileExists = [bool]( Test-Path -Path "$env:USERPROFILE\$Item" )
    $ProfileSymlink = [bool]( ( Get-Item "$env:USERPROFILE\$Item" -Force -ErrorAction SilentlyContinue ).Attributes -band [IO.FileAttributes]::ReparsePoint )

    # verify that at least one source exists, if not skip
    if ( ! $BackupExists -and ! $ProfileExists ) {

        [PSCustomObject]@{
            'Item' = $Item;
            'Status' = 'Error';
            'Message' = "Doesn't exist in profile or backup."
        }

        continue

    }

    # if both sources exist, and both are symlinks output a message and skip
    if ( $BackupSymlink -and $ProfileSymlink ) {

        [PSCustomObject]@{
            'Item' = $Item;
            'Status' = 'Error';
            'Message' = "Both profile and backup appear to be a symlink!"
        }

        continue

    }

    # if the profile folder doesn't exist build it
    if ( ! $ProfileExists ) {

        if ( -not ( Test-Path ( Split-Path "$env:USERPROFILE\$Item" ) ) ) {

            New-Item ( Split-Path "$env:USERPROFILE\$Item" ) -ItemType Directory > $null

        }

        # Write-Host "Creating symlink in profile directory to '$Item'."

        New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\$Item" -Target "$PSScriptRoot\$Item" > $null

        [PSCustomObject]@{
            'Item' = $Item;
            'Status' = 'Ok';
            'Message' = "Symlink created in '$env:USERPROFILE' for '$Item'."
        }

        continue

    }

    # if the backup folder doesn't exist, move the source and create a symlink
    if ( ! $BackupExists ) {

        if ( -not ( Test-Path ( Split-Path "$PSScriptRoot\$item" ) ) ) {

            New-Item ( Split-Path "$PSScriptRoot\$Item" ) -ItemType Directory > $null

        }

        try {
        
            Move-Item -Path "$env:USERPROFILE\$Item" -Destination "$PSScriptRoot\$Item" -Force -ErrorAction Stop

        } catch {

            [PSCustomObject]@{
                'Item' = $Item;
                'Status' = 'Error';
                'Message' = "Could not move '$env:USERPROFILE\$Item' to '$PSScriptRoot\$Item'."
            }

            continue

        }
        
        New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\$Item" -Target "$PSScriptRoot\$Item" > $null

        [PSCustomObject]@{
            'Item' = $Item;
            'Status' = 'Ok';
            'Message' = "Moved '$env:USERPROFILE\$Item' to '$PSScriptRoot\$Item' and created a symlink."
        }

        continue

    }

        [PSCustomObject]@{
            'Item' = $Item;
            'Status' = 'Ok';
            'Message' = "Appears to already be configured."
        }
    
}