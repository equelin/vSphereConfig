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
    #Get Existing configuration of the Host
    Write-Host "Retrieving existing configuration of the Host" -ForegroundColor Blue
    Get-VMHost | Get-JSONFromESXi -JsonFile .\temp.json

    #Get the content of the base file
    $ESXiConfigBase = Get-Content -Raw -Path .\temp.json | ConvertFrom-Json

    #Get the content of the reference file
    $ESXiConfigReference = Get-Content -Raw -Path $JsonFile | ConvertFrom-Json
  }
  Process {

    #Configure Host Network
    If ($ESXiConfigReference.VMHostNetwork.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure Host Network" -ForegroundColor Blue
      $ESXiConfigReference.VMHostNetwork | setVMHostNetwork -VMHost $VMHost
    }

    #Configure NTP
    If ($ESXiConfigReference.NTP.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure NTP" -ForegroundColor Blue
      $ESXiConfigReference.NTP | setNTP -VMHost $VMHost
    }

    #Configure SSH
    If ($ESXiConfigReference.SSH.PSObject.Properties.Count -gt 0) {
      Write-Host "Configure SSH" -ForegroundColor Blue
      $ESXiConfigReference.SSH | setSSH -VMHost $VMHost
    }

    #Configure vSwitchs
    If ($ESXiConfigReference.vSwitchs.Count -gt 0) {
      Write-Host "Configure vSwitchs" -ForegroundColor Blue

      $items = "vSwitchs"
      $key= "Name"

      #Compare source/base vSwitchs to the reference vSwitchs
      Foreach ($itemBase in $ESXiConfigBase.$items) {
          If ($ESXiConfigReference.$items.$key -contains $itemBase.$key) {
            Write-Host "=== $($items) $($itemBase.$key)" -ForegroundColor Yellow
            $itemBase | SetvSwitchs -VMHost $VMHost
          } Else {
            Write-Host "--- $($items) $($itemBase.$key)" -ForegroundColor Red
            $itemBase | RemovevSwitchs -VMHost $VMHost
          }
      }
      #Compare reference vSwitchs to the source/base vSwitchs
      Foreach ($itemRef in $ESXiConfigReference.$items) {
          If (!($ESXiConfigBase.$items.$key -contains $itemRef.$key)) {
            Write-Host "+++ $($items) $($itemRef.$key)" -ForegroundColor Green
            $itemRef | CreatevSwitchs -VMHost $VMHost
          }
      }
    }

    #Configure Portgroups
    If ($ESXiConfigReference.Portgroups.Count -gt 0) {
      Write-Host "Configure Portgroups" -ForegroundColor Blue
      $ESXiConfigReference.Portgroups | SetPortgroups -VMHost $VMHost
    }

    #Configure Vmkernels
    If ($ESXiConfigReference.Vmkernels.Count -gt 0) {
      Write-Host "Configure Vmkernels" -ForegroundColor Blue
      $ESXiConfigReference.Vmkernels | SetVmkernels -VMHost $VMHost
    }
    Write-Output $VMHost | Out-Null
  }
}
