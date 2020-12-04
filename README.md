# veeam_agent_updater
A simple PowerShell script for deploying the VeeamAgent hotfixes

This is a simple PowerShell script that can handle VeeamAgent deployment on any number of connected to Veeam Windows servers.

Prerequisites: Domain Administrator rights, must be run on the Veeam B&R server. Tested with B&R v10a and PowerShell v5.

Main scenario: script is started under Domain Administrator on the Veeam B&R server; all Windows machines added into Veeam are browseable via c$; folder structure of agents is saved as is.

Please notice that it is expected to have the following file structure:

lin
    
    veeamagent64
    
    veeamagent

win64
    
    VeeamAgent.exe

win32
    
    VeeamAgent.exe

agent_uploader.ps1
