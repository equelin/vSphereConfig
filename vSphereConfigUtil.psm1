## functions that are used by the module, but not published for end-user consumption
function GetVirtualSwitchsArray {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [PSObject]$vSwitch,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesvSwitchs,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesNicTeaming
  )
  Begin{}
  Process{
    $Hashtable = @{}
    $NicTeaming = Get-NicTeamingPolicy -VirtualSwitch $vSwitch | Select-Object -Property $ListPropertiesNicTeaming
    $vSwitch = $vSwitch | Select-Object -Property $ListPropertiesvSwitchs
    ForEach ($vSwitchProperty in $vSwitch.PSObject.Properties) {
      $Hashtable.($vSwitchProperty.Name) = $vSwitchProperty.Value
    }
    ForEach ($NicTeamingProperty in $NicTeaming.PSObject.Properties) {
      $Hashtable.($NicTeamingProperty.Name) = $NicTeamingProperty.Value
    }
    Write-Output $Hashtable
  }
}

function GetPortgroupsArray {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$PortgroupName,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesPortgroups,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesNicTeaming
  )
  Begin{}
  Process{
    $Hashtable = @{}
    $VirtualPortGroup = Get-VirtualPortGroup -Name $PortgroupName.Name
    $NicTeaming = Get-NicTeamingPolicy -VirtualPortGroup $VirtualPortGroup | Select-Object -Property $ListPropertiesNicTeaming
    $VirtualPortGroup = $VirtualPortGroup | Select-Object -Property $ListPropertiesPortgroups
    ForEach ($PortgroupProperty in $VirtualPortGroup.PSObject.Properties) {
      $Hashtable.($PortgroupProperty.Name) = $PortgroupProperty.Value
    }
    ForEach ($NicTeamingProperty in $NicTeaming.PSObject.Properties) {
      $Hashtable.($NicTeamingProperty.Name) = $NicTeamingProperty.Value
    }
    Write-Output $Hashtable
  }
}

function GetVmkernelsArray {
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [PSObject]$Vmkernel,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesVmkernels,
    [Parameter(Mandatory=$true)]
    [array]$ListPropertiesNicTeaming
  )
  Begin{}
  Process{
    $Hashtable = @{}
    $VirtualPortGroup = Get-VirtualPortGroup -Name $Vmkernel.PortGroupName
    $NicTeaming = Get-NicTeamingPolicy -VirtualPortGroup $VirtualPortGroup | Select-Object -Property $ListPropertiesNicTeaming
    $Vmkernel = $Vmkernel | Select-Object -Property $ListPropertiesVmkernels

    $Hashtable.VirtualSwitchName = $VirtualPortGroup.VirtualSwitchName
    $Hashtable.VLanId = $VirtualPortGroup.VLanId

    ForEach ($VmkernelProperty in $Vmkernel.PSObject.Properties) {
      $Hashtable.($VmkernelProperty.Name) = $VmkernelProperty.Value
    }
    ForEach ($NicTeamingProperty in $NicTeaming.PSObject.Properties) {
      $Hashtable.($NicTeamingProperty.Name) = $NicTeamingProperty.Value
    }
    Write-Output $Hashtable
  }
}

function setVMHostNetwork {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$VMHostNetwork,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    Get-VMHostNetwork -VMHost $VMHost | Set-VMHostNetwork -DomainName $VMHostNetwork.DomainName -DnsAddress $VMHostNetwork.DnsAddress -SearchDomain $VMHostNetwork.SearchDomain | Out-Null
  }
}

function setNTP {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$NTP,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    Write-Host "*** Configuring Time" -ForegroundColor Cyan
    $VMHost | %{(Get-View $_.ExtensionData.configManager.DateTimeSystem).UpdateDateTime((Get-Date -format u)) }

    If ($NTP.VMHostNtpServer.Count -gt 0) {
      Write-Host "*** Configuring NTP Servers" -ForegroundColor Cyan
      $VMHost | Add-VMHostNTPServer -NtpServer $NTP.VMHostNtpServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host "*** Configuring NTP Client Policy" -ForegroundColor Cyan
    $VMHost | Get-VMHostService | where{$_.Key -eq "ntpd"} | Set-VMHostService -policy $NTP.Policy -Confirm:$false | Out-Null

    Write-Host "*** Restarting NTP Client" -ForegroundColor Cyan
    $VMHost | Get-VMHostService | where{$_.Key -eq "ntpd"} | Restart-VMHostService -Confirm:$false | Out-Null
  }
}

function setSSH {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$SSH,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    Write-Host "*** Configure SSH warning" -ForegroundColor Cyan
    $VMHost | Get-AdvancedSetting -Name 'UserVars.SuppressShellWarning' | Set-AdvancedSetting -Value $SSH.SuppressShellWarning -Confirm:$false | Out-Null

    Write-Host "*** Configuring SSH activation policy" -ForegroundColor Cyan
    $VMHost | Get-VMHostService | where{$_.Key -eq "TSM-SSH"} | Set-VMHostService -policy $SSH.Policy -Confirm:$false | Out-Null

    If (($SSH.Policy -eq "on") -or ($SSH.Policy -eq "Automatic")) {
      Write-Host "*** Configure SSH service startup" -ForegroundColor Cyan
      $VMHost | Get-VMHostService | where{$_.Key -eq "TSM-SSH"} | Start-VMHostService -Confirm:$false | Out-Null
    }
  }
}

function SetvSwitchs {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$vSwitch,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    If ((Get-VirtualSwitch -Name $vSwitch.Name -ErrorAction SilentlyContinue) -eq $null){
      Write-Host "*** Creating Virtual Switch $($vSwitch.Name)" -ForegroundColor Cyan
      If ($vSwitch.Nic -eq $null){
        $VMHost | New-VirtualSwitch -Name $vSwitch.Name -Mtu $vSwitch.Mtu | Out-Null
      } else {
        $VMHost | New-VirtualSwitch -Name $vSwitch.Name -Mtu $vSwitch.Mtu -Nic $vSwitch.Nic | Out-Null
        SetNicTeamingPolicy -Object $vSwitch -Type "vSwitch" -VMHost $VMHost
      }
    }
  }
}

function SetPortgroups {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$Portgroup,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    If ((Get-VirtualPortGroup -Name $portgroup.Name -ErrorAction SilentlyContinue) -eq $null){
      Write-Host "*** Creating Portgroup $($portgroup.Name) with VLAN ID $($portgroup.VlanId)" -ForegroundColor Cyan
      $VMHost | Get-VirtualSwitch -Name $portgroup.VirtualSwitchName | New-VirtualPortGroup -Name $portgroup.Name -VLanId $portgroup.VLanID | Out-Null
      SetNicTeamingPolicy -Object $Portgroup -Type "Portgroup" -VMHost $VMHost
    }
  }
}

function SetVmkernels {
  Param (
    [Parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
    [array]$Vmkernel,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )
  Process {
    If (( Get-VMHostNetworkAdapter -Name $vmkernel.Name -ErrorAction SilentlyContinue) -eq $null){
      Write-Host "*** Creating Vmkernel $($vmkernel.Name)" -ForegroundColor Cyan
      If ($vmkernel.DhcpEnabled) {
        $VMHost | New-VMHostNetworkAdapter -Portgroup $vmkernel.PortGroupName -VirtualSwitch $vmkernel.VirtualSwitchName | Out-Null
      } else {
        $VMHost | New-VMHostNetworkAdapter -Portgroup $vmkernel.PortGroupName -VirtualSwitch $vmkernel.VirtualSwitchName -IP $vmkernel.IP -SubnetMask $vmkernel.SubnetMask | Out-Null
      }
      If ($vmkernel.VMotionEnabled) {
        $VMHost | Get-VMHostNetworkAdapter | where { $_.PortGroupName -eq $vmkernel.PortGroupName } | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-Null
      }
      Write-Host "*** Set VlanID $($vmkernel.VLanID)" -ForegroundColor Cyan
      $VMHost | Get-VirtualPortGroup -Name $vmkernel.PortGroupName | Set-VirtualPortGroup -VLanId $vmkernel.VLanID | Out-Null
      SetNicTeamingPolicy -Object $Vmkernel -Type "Vmkernel" -VMHost $VMHost
    }
  }
}

function SetNicTeamingPolicy {
  Param (
    [Parameter(Mandatory=$true)]
    [array]$Object,
    [Parameter(Mandatory=$true)]
    [string]$Type,
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$VMHost
  )

  If (!($Object.IsFailoverOrderInherited)) {
    switch ($Type) {
      vSwitch {$NicTeamingPolicy = $VMHost | Get-VirtualSwitch -Name $Object.Name | Get-NicTeamingPolicy}
      Portgroup {$NicTeamingPolicy = $VMHost | Get-VirtualPortGroup -Name $Object.Name | Get-NicTeamingPolicy}
      Vmkernel {$NicTeamingPolicy = $VMHost | Get-VirtualPortGroup -Name $Object.PortGroupName | Get-NicTeamingPolicy}
      Default {$NicTeamingPolicy = $null}
    }

    If (!([string]::IsNullOrEmpty($Object.ActiveNic))) {
      Write-Host "*** Set Actives Nics for $($Object.Name)" -ForegroundColor Cyan
      $NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicActive $Object.ActiveNic | Out-Null
    }
    If (!([string]::IsNullOrEmpty($Object.StandbyNic))) {
      Write-Host "*** Set Standby Nics for $($Object.Name)" -ForegroundColor Cyan
      $NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicStandby $Object.StandbyNic | Out-Null
    }
    If (!([string]::IsNullOrEmpty($Object.UnusedNic))) {
      Write-Host "*** Set Unused Nics for $($Object.Name)" -ForegroundColor Cyan
      $NicTeamingPolicy | Set-NicTeamingPolicy -MakeNicUnused $Object.UnusedNic | Out-Null
    }
  }
} ## end function
