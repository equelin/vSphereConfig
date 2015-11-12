Function Get-JSONFromESXi {
  [OutputType([VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])]
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost,
    [Parameter(Mandatory=$True,HelpMessage="Enter the path and name of the JSON file")]
    [String]$JsonFile
  )
  #List of property we want to retrieve
  $ListPropertiesvSwitchs = @("Name","MTU","Nic")
  $ListPropertiesPortgroups = @("Name","VirtualSwitchName","VLanId")
  $ListPropertiesVmkernels = @("Name","DhcpEnabled","IP","SubnetMask","VMotionEnabled","PortGroupName")
  $ListPropertiesNicTeaming = @("ActiveNic","StandbyNic","UnusedNic","IsFailoverOrderInherited")
  $ListJsonArray = @("NTP","SSH","vSwitchs","PortGroups","Vmkernels")

  #Variables initialisation
  $json = [ordered]@{}
  $NTP = @{}
  $SSH = @{}
  $HostNetwork = @{}

  foreach ($JsonArray in $ListJsonArray) {
    $json.($JsonArray) = @{}
  }

  #Get the informations
  $VMHostNtpServer = $VMHost | Get-VMHostNtpServer
  $VMHostNtpServerPolicy = $VMHost | Get-VMHostService | Where-Object {$_.Key -eq 'ntpd'} | Select-Object -Property Policy
  $VMHostSSHServerPolicy = $VMHost | Get-VMHostService | Where-Object {$_.Key -eq 'TSM-SSH'} | Select-Object -Property Policy
  $VMHostSSHSuppressShellWarning = Get-AdvancedSetting -Entity $VMHost.Name -Name 'UserVars.SuppressShellWarning'
  $VMHostNetwork = $VMHost | Get-VMHostNetwork

  $NTP.VMHostNtpServer = $VMHostNtpServer
  $NTP.Policy = $VMHostNtpServerPolicy.Policy

  $SSH.Policy = $VMHostSSHServerPolicy.Policy
  $SSH.SuppressShellWarning = $VMHostSSHSuppressShellWarning.Value

  $HostNetwork.DomainName = $VMHostNetwork.DomainName
  $HostNetwork.SearchDomain = $VMHostNetwork.SearchDomain
  $HostNetwork.DnsAddress = $VMHostNetwork.DnsAddress

  ###################

  $json.VMHostNetwork = $HostNetwork
  $json.NTP = $NTP
  $json.SSH = $SSH
  $json.vSwitchs = $VMHost | Get-VirtualSwitch | GetVirtualSwitchsArray -ListPropertiesvSwitchs $ListPropertiesvSwitchs -ListPropertiesNicTeaming $ListPropertiesNicTeaming
  $json.Portgroups = Get-View -Server $VMHost.Name -ViewType Network | Select-Object -Property Name | GetPortgroupsArray -ListPropertiesPortgroups $ListPropertiesPortgroups -ListPropertiesNicTeaming $ListPropertiesNicTeaming
  $json.Vmkernels = $VMHost | Get-VMHostNetworkAdapter -VMkernel | GetVmkernelsArray -ListPropertiesVmkernels $ListPropertiesVmkernels -ListPropertiesNicTeaming $ListPropertiesNicTeaming


  $json | ConvertTo-Json -Depth 3 | Set-Content $JsonFile

  Write-Output $VMHost | Out-Null
}

Function Set-JSONtoESXi {
  [CmdletBinding()]
  [OutputType([VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl])]
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost,
    [Parameter(Mandatory=$True,HelpMessage="Enter the path to a json file")]
    [ValidateScript({If(Test-Path $_) {$true} else {Throw "Invalid path given: $_"}})]
    [String]$JsonFile
  )

  Begin {
    #Get the content of the file
    $ESXiConfig = Get-Content -Raw -Path $JsonFile | ConvertFrom-Json
  }
  Process {

    #Configure Host Network
    If ($ESXiConfig.VMHostNetwork.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure Host Network" -ForegroundColor Blue
      $ESXiConfig.VMHostNetwork | setVMHostNetwork -VMHost $VMHost
    }

    #Configure NTP
    If ($ESXiConfig.NTP.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure NTP" -ForegroundColor Blue
      $ESXiConfig.NTP | setNTP -VMHost $VMHost
    }

    #Configure SSH
    If ($ESXiConfig.SSH.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure SSH" -ForegroundColor Blue
      $ESXiConfig.SSH | setSSH -VMHost $VMHost
    }

    #Configure vSwitchs
    If ($ESXiConfig.vSwitchs.Count -gt 0) {
      Write-Host "Configure vSwitchs" -ForegroundColor Blue
      $ESXiConfig.vSwitchs | SetvSwitchs -VMHost $VMHost
    }

    #Configure Portgroups
    If ($ESXiConfig.Portgroups.Count -gt 0) {
      Write-Host "Configure Portgroups" -ForegroundColor Blue
      $ESXiConfig.Portgroups | SetPortgroups -VMHost $VMHost
    }

    #Configure Vmkernels
    If ($ESXiConfig.Vmkernels.Count -gt 0) {
      Write-Host "Configure Vmkernels" -ForegroundColor Blue
      $ESXiConfig.Vmkernels | SetVmkernels -VMHost $VMHost
    }
    Write-Output $VMHost
  }
}
