#Requires -RunAsAdministrator

param (
    [Parameter(Mandatory = $False, ValueFromPipeline = $True, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [PSObject]$SingleHost
)

<#
.SYNOPSIS
This script automates agent deployment for NAS Cumulative Fix

.DESCRIPTION
This script was written by Alexander Gerasimov <alexander.gerasimov@veeam.com> 2020
Tested on Veeam Backup & Replication v10 and PowerShell v5

Change history:
v0.2 Added new paths
v0.3 Added Join-Paths and moved $Date so all the backed up agents will have the same time in the name
v0.4 Added Exit in the Default switch in Copy-Agents just in case :)
v0.5 Added -SingleHost mode
v0.6 Now -SingleHost mode accepts pipeline input and only Get-VBRServer -Local or -Windows objects
v0.7 Added some $null checks cause not all Veeam B&R installations have Windows hosts

.INPUTS
Script runs either without parameters or in a -SingleHost mode that requires you to input an ip address or a domain name.

.EXAMPLE
./agent_uploader.ps1
Get-VBRLocalhost | .\agent_uploader.ps1
Get-VBRServer -Type Local | .\agent_uploader.ps1
Get-VBRServer -Name 172.17.249.137 | .\agent_uploader.ps1

.NOTES
    This script must be started on the Veeam B&R server under Domain Administrator privileges.

    Account that is used to run the script must have direct access to all machines added into Veeam as Windows Backup Proxies or Repositories
    
    If you get the error message 'The script cannot be run because the following snap-ins that are specified by the "#requires" statements
of the script are missing: VeeamPSSnapIn.' then you've already updated the agents and need to run Veeam B&R console once. 
 
    Another possibility if you run this script multiple times is that you got into PoweShell glitch. If that's the case 
running Add-PSSnapin VeeamPSSnapin in a new PS console should be enough.

    If host is unavailable, sometimes Test-Path might get stuck on checking the availability of the path. Simply hit Enter to keep it running forward.
#>

function Get-PSVersion {
    $PSVersionTable.PSVersion
}

function Test-Veeam {
    try {
        $VeeamService = Get-Service -DisplayName "Veeam Backup Service" -ErrorAction Stop
    }
    catch {
        Write-Host "Please run this script on the Veeam B&R server!" -BackgroundColor Red -ForegroundColor Black
        Write-Log("Veeam Backup Service was not found")
        Exit
    }
    Write-Log("Veeam Backup Service was found")
    try {
        $Snapin = Get-PSSnapin -Registered -Name "VeeamPSSnapIn" -ErrorAction Stop
    }
    catch {
        Write-Host "Veeam PowerShell Snap-in is not installed!" -BackgroundColor Red -ForegroundColor Black
        Write-Log("Veeam PS Snap-in was not found")
        Exit
    }
    Write-Log("Veeam PS Snap-in was found")
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $LogFile = "C:\ProgramData\Veeam\Backup\AgentDeployer.log"
    $Date = Get-Date -Format "[dd.MM.yyyy HH:mm:ss]"

    if ($Message -eq "`n") {
        Add-Content $LogFile "`n"
        Return
    }

    Add-Content $LogFile "$Date $Message"
}

$Agents = @(
    "win64\VeeamAgent.exe"
    "win32\VeeamAgent.exe"
    "lin\veeamagent64"
    "lin\veeamagent"
)

function Test-AgentFiles {
    foreach ($Agent in $Agents) {
        if ((Test-Path $Agent) -eq $false) {
            Write-Host "$Agent was not found" -BackgroundColor Red -ForegroundColor Black
            Write-Log("$Agent was not found")
            Exit
        }
        Write-Host "$Agent was found"
        Write-Log("$Agent was found")
    
        $MD5Hash = Get-FileHash -Algorithm MD5 $Agent
        Write-Log("$Agent MD5: $($MD5Hash.Hash)")
    }
    Write-Host "All new agent files were detected"
    Write-Log("All new agent files were detected")
}

$WindowsPaths = @(
    "c$\Program Files (x86)\Veeam\Backup Transport\x64\VeeamAgent.exe"
    "c$\Program Files (x86)\Veeam\Backup Transport\x86\VeeamAgent.exe"
    "c$\Program Files (x86)\Veeam\Backup Transport\GuestInteraction\VSS\sql\VeeamAgent.exe"
)

$LinuxMountPaths = @(
    "c$\Program Files\Common Files\Veeam\Backup and Replication\Mount Service\VeeamAgent"
    "c$\Program Files\Common Files\Veeam\Backup and Replication\Mount Service\VeeamAgent64"
)

$LinuxVeeamPaths = @(
    "c$\Program Files\Veeam\Backup and Replication\Backup\VeeamAgent"
    "c$\Program Files\Veeam\Backup and Replication\Backup\VeeamAgent64"
)

$VeeamAdditionalPaths = @(
    "c$\Program Files\Veeam\Backup and Replication\Backup\VSS\sql\VeeamAgent.exe"
    "c$\Program Files\Veeam\Backup and Replication\Backup\WinAgent\VeeamAgent.exe"
    "c$\Program Files\Veeam\Backup and Replication\Backup Catalog\WinAgent\VeeamAgent.exe"
    "c$\Program Files\Veeam\Backup and Replication\Enterprise Manager\WinAgent\VeeamAgent.exe"
)

function Join-Paths {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WinHost,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $Path = Join-Path $WinHost $Path
    $FullPath = "\\$Path"
    return $FullPath
}

function Copy-Agents {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSObject]$Hosts,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSObject]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action
    )
    foreach ($WinHost in $Hosts) {
        foreach ($Path in $Paths) {
            
            $FullPath = Join-Paths $WinHost $Path

            switch ($Action) {
                "backup" {
                    Write-Host "Checking $FullPath availability..." -ForegroundColor Yellow
                    if ((Test-Path $FullPath) -eq $false) {
                        Write-Host "$FullPath was not found for backup" -BackgroundColor Red -ForegroundColor Black
                        Write-Log("$FullPath was not found for backup")
                    }
                    else {
                        try {
                            Copy-Item $FullPath "$($FullPath)_$StartDate" -ErrorAction Stop
                        }
                        catch {
                            Write-Host "$FullPath was not backed up" -BackgroundColor Red -ForegroundColor Black
                            Write-Log("$FullPath was not backed up")
                        }
                        Write-Host "$FullPath was backed up"
                        Write-Log("$FullPath was backed up")
                    }
                }
                "deploy" {
                    Write-Host "Checking $FullPath availability..." -ForegroundColor Yellow
                    if ((Test-Path $FullPath) -eq $false) {
                        Write-Host "$FullPath was not found" -BackgroundColor Red -ForegroundColor Black
                        Write-Log("$FullPath was not found")
                    }
                    else {
                        Write-Host "Updating $FullPath..." -BackgroundColor White -ForegroundColor Black
                        switch -Wildcard ($FullPath) {
                            "*x64\VeeamAgent.exe" {
                                $Agent = $Agents[0]
                            }
                            "*x86\VeeamAgent.exe" {
                                $Agent = $Agents[1]
                            }
                            "*VeeamAgent64" {
                                $Agent = $Agents[2]
                            }
                            "*VeeamAgent" {
                                $Agent = $Agents[3]
                            }
                            "*sql\VeeamAgent.exe" {
                                $Agent = $Agents[1]
                            }
                            "*WinAgent\VeeamAgent.exe" {
                                $Agent = $Agents[1]
                            }
                        }
                        try {
                            Copy-Item $Agent $FullPath -ErrorAction Stop
                        }
                        catch {
                            Write-Host "$FullPath was not updated" -BackgroundColor Red -ForegroundColor Black
                            Write-Log("$FullPath was not updated")
                        }
                        Write-Host "Done" -BackgroundColor White -ForegroundColor Green
                        Write-Log("$FullPath was updated successfully")
                    }
                }
                Default {
                    Write-Log("This is totally unhandled exception")
                    Exit
                }
            }
        }
    }
}

function Get-WindowsHosts {
    Write-Host "Getting all Windows servers added into Veeam B&R..." -NoNewline -BackgroundColor White -ForegroundColor Black
    try {
        $WindowsHosts = $(Get-VBRServer -Type Windows -ErrorAction Stop).Name
    }
    catch {
        Write-Host "Windows hosts added into Veeam B&R were not collected!" -BackgroundColor Red -ForegroundColor Black
        Write-Log("Get-VBRServer -Type Windows failed")
        Exit
    }
    Write-Host "Done" -BackgroundColor White -ForegroundColor Green
    if ($WindowsHosts) {
        Write-Log("List of all Windows hosts added into Veeam:")
        foreach ($WinHost in $WindowsHosts) {
            Write-Log("     $WinHost")
        }
        return $WindowsHosts
    }
    else {
        Write-Host "No Windows hosts were detected"
        Write-Log("No Windows hosts were detected")
    }
}

function Get-VeeamServer {
    Write-Host "Getting Veeam server name..." -NoNewline -BackgroundColor White -ForegroundColor Black
    try {
        $VeeamServer = $(Get-VBRLocalhost -ErrorAction Stop).Name 
    }
    catch {
        Write-Host "Veeam B&R server name was not collected! You might need to open a new PowerShell window." -BackgroundColor Red -ForegroundColor Black
        Write-Log("Get-VBRLocalhost failed")
        Exit
    }
    Write-Host "Done" -BackgroundColor White -ForegroundColor Green
    Write-Log("Veeam server is:")
    Write-Log("     $VeeamServer")
    return $VeeamServer
}

function Stop-VeeamService {
    $Confirmation = Read-Host "Do you agree to stop Veeam Backup Service? [y/n]"
    switch ($Confirmation) {
        "y" {
            Write-Host "Trying to stop Veeam Backup Service.." -NoNewline -BackgroundColor White -ForegroundColor Black
            try {
                Stop-Service -DisplayName "Veeam Backup Service" -ErrorAction Stop
            }
            catch {
                Write-Host "Please run this script one more time, Veeam Backup Service hadn't been stopped!" -BackgroundColor Red -ForegroundColor Black
                Write-Log("Veeam Backup Service was not stopped")
                Exit
            }
            Write-Log("Veeam Backup Service was stopped")
            Write-Host "Done" -BackgroundColor White -ForegroundColor Green
        }
        "n" {
            Write-Host "Veeam Backup Service must be stopped in order to finish deployment process" -BackgroundColor Red -ForegroundColor Black
            Exit
        }
        Default {
            Write-Host "Please choose either of options!" -BackgroundColor Red -ForegroundColor Black
            Exit
        }
    }
}

function Update-VeeamServer {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSObject]$VeeamServer
    )
    Copy-Agents $VeeamServer $WindowsPaths backup
    Copy-Agents $VeeamServer $LinuxMountPaths backup
    Copy-Agents $VeeamServer $LinuxVeeamPaths backup
    Copy-Agents $VeeamServer $VeeamAdditionalPaths backup

    Copy-Agents $VeeamServer $WindowsPaths deploy
    Copy-Agents $VeeamServer $LinuxMountPaths deploy
    Copy-Agents $VeeamServer $LinuxVeeamPaths deploy
    Copy-Agents $VeeamServer $VeeamAdditionalPaths deploy
}

function Update-WindowsHosts {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSObject]$WindowsHosts
    )
    # Should be kinda bulletproof version of if($WindowsHosts) even though it looks not so dapper
    # More on that https://docs.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-null?view=powershell-7.1
    if ($null -ne $WindowsHosts) {
        Copy-Agents $WindowsHosts $WindowsPaths backup
        Copy-Agents $WindowsHosts $LinuxMountPaths backup
        
        Copy-Agents $WindowsHosts $WindowsPaths deploy
        Copy-Agents $WindowsHosts $LinuxMountPaths deploy
    }
    else {
        Write-Log("Update-WindowsHosts was passed with null somehow")
    }
}

Write-Log("`n")

Test-Veeam
Test-AgentFiles

Add-PSSnapin VeeamPSSnapin

Write-Host "Starting script execution" -BackgroundColor White -ForegroundColor Black
Write-Log("Starting script execution")

$PSVersion = Get-PSVersion
Write-Log("PowerShell version: $PSVersion")

# Getting the date here to have the same date when renaming the agents during backup
$StartDate = Get-Date -Format "ddMMyyyy_HHmmss"

if ($PSBoundParameters.ContainsKey('SingleHost')) {
        Write-Host "Processing in SingleHost mode" -BackgroundColor White -ForegroundColor Black
        Write-Log("Processing in SingleHost mode")

        if ($SingleHost.Type -eq "Local") {
            $VeeamServer = $SingleHost.Name
            Write-Log("$SingleHost acts as a Veeam server")
        }
        elseif ($SingleHost.Type -eq "Windows") {
            $WindowsHosts = $SingleHost.Name
            Write-Log("$SingleHost is not Veeam server")
        }
        else {
            Write-Host "Script accepts only CHosts with Local or Windows types" -BackgroundColor Red -ForegroundColor Black
        }
}
else {
    $VeeamServer = Get-VeeamServer
    $WindowsHosts = Get-WindowsHosts
}

Stop-VeeamService

#If script was started without any parameters we will process all the Windows servers added into Veeam B&R including Veeam itself

if ($VeeamServer) {
    Update-VeeamServer $VeeamServer
}

if ($WindowsHosts) {
    Update-WindowsHosts $WindowsHosts
}

Write-Log("Agent deployment complete")
Write-Host "All done. Please start Veeam Backup Service manually and run Veeam Console once" -ForegroundColor Green