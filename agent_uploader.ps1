#Requires -RunAsAdministrator
#Requires -PSSnapin VeeamPSSnapIn

<#
.SYNOPSIS
This script automates agent deployment for NAS Cumulative Fix

.DESCRIPTION
This script was written by Alexander Gerasimov <alexander.gerasimov@veeam.com>, v0.2 @ 3 Dec 2020
Tested on Veeam Backup & Replication v10 and PowerShell v5

Change history:
v0.2 Added new paths
v0.3 Added Join-Paths and move $Date so all the backed up agents will have the same time in the name

.EXAMPLE
./agent_uploader.ps1

.NOTES
    This script must be started on the Veeam B&R server under Domain Administrator privileges.

    Account that is used to run the script must have direct access to all machines added into Veeam as Windows Backup Proxies or Repositories
    
    If you get the error message 'The script cannot be run because the following snap-ins that are specified by the "#requires" statements
of the script are missing: VeeamPSSnapIn.' then you've already updated the agents and need to run Veeam B&R console once. 
 
    Another possibility if you run this script multiple times is that you got into PoweShell glitch. If that's the case 
running Add-PSSnapin VeeamPSSnapin in a new PS console should be enough.
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
    
        $MD5Hash = Get-FileHash -Algorithm MD5 $Agent | Select-Object -ExpandProperty Hash
        Write-Log("$Agent MD5: $MD5Hash")
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
                            Copy-Item $FullPath "$($FullPath)_$Date" -ErrorAction Stop
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
                }
            }
        }
    }
}

function Get-WindowsHosts {
    Write-Host "Getting all Windows servers added into Veeam B&R..." -NoNewline -BackgroundColor White -ForegroundColor Black
    try {
        $WindowsHosts = Get-VBRServer -Type Windows | Select-Object -ExpandProperty Name -ErrorAction Stop
    }
    catch {
        Write-Host "Windows hosts added into Veeam B&R were not collected!" -BackgroundColor Red -ForegroundColor Black
        Write-Log("Get-VBRServer -Type Windows failed")
        Exit
    }
    Write-Host "Done" -BackgroundColor White -ForegroundColor Green
    Write-Log("List of all Windows hosts added into Veeam:")
    foreach ($WinHost in $WindowsHosts) {
        Write-Log("     $WinHost")
    }
    return $WindowsHosts
}

function Get-VeeamServer {
    Write-Host "Getting Veeam server name..." -NoNewline -BackgroundColor White -ForegroundColor Black
    try {
        $VeeamServer = Get-VBRLocalhost | Select-Object -ExpandProperty Name -ErrorAction Stop
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
                Write-Host "Please run this script one more time, Veeam Backup Service hasn't stopped!" -BackgroundColor Red -ForegroundColor Black
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

Write-Log("`n")

Test-Veeam
Test-AgentFiles

Add-PSSnapin VeeamPSSnapin

Write-Host "Starting script execution" -BackgroundColor White -ForegroundColor Black
Write-Log("Starting script execution")

$Date = Get-Date -Format "ddMMyyyy_HHmmss"
$VeeamServer = Get-VeeamServer
$WindowsHosts = Get-WindowsHosts

Stop-VeeamService

$PSVersion = Get-PSVersion
Write-Log("PowerShell version: $PSVersion")

#Processing of agents in Backup Transport, Mount Service and Veeam server's Linux agents on Veeam server

Copy-Agents $VeeamServer $WindowsPaths backup
Copy-Agents $VeeamServer $LinuxMountPaths backup
Copy-Agents $VeeamServer $LinuxVeeamPaths backup
Copy-Agents $VeeamServer $VeeamAdditionalPaths backup

Copy-Agents $VeeamServer $WindowsPaths deploy
Copy-Agents $VeeamServer $LinuxMountPaths deploy
Copy-Agents $VeeamServer $LinuxVeeamPaths deploy
Copy-Agents $VeeamServer $VeeamAdditionalPaths deploy

#Processing of agents in Backup Transport and Mount Service on all Windows servers added into Veeam

Copy-Agents $WindowsHosts $WindowsPaths backup
Copy-Agents $WindowsHosts $LinuxMountPaths backup

Copy-Agents $WindowsHosts $WindowsPaths deploy
Copy-Agents $WindowsHosts $LinuxMountPaths deploy

Write-Log("Agent deployment complete")
Write-Host "All done. Please start Veeam Backup Service manually and run Veeam Console once" -ForegroundColor Green