# PSDiscoveryProtocol and SCCM HW Inventory

![alt text](https://raw.githubusercontent.com/lahell/PSDiscoveryProtocol-SCCM-HWInventory/master/images/psdiscoveryprotocol.png "PSDiscoveryProtocol in Resource Explorer")

This is a proof of concept to demonstrate how to add information about the network device on the other end of your computer's wired connection to the SCCM Hardware Inventory.

Switches and other network devices can send advertisements containing information such as system name, port id, IP address, model number etc.

Our goal is to use [PSDiscoveryProtocol](https://github.com/lahell/PSDiscoveryProtocol) to capture those advertisements, and store information from them in a new CIM class. The CIM class can then be included in the SCCM Hardware Inventory.

## Computer Requirements
* Windows 10
* WinRM and PowerShell Remoting must be enabled
* Windows PowerShell 5.1 or later
* PSDiscoveryProtocol

## Network Device Requirements
* CDP or LLDP must be enabled

## Check for advertisements
Some network admins disable CDP and LLDP as a security measure. Before we do anything in SCCM we need to check if our network device is actually sending advertisements.

### Install PSDiscoveryProtocol
```PowerShell
Install-Module PSDiscoveryProtocol
Import-Module PSDiscoveryProtocol
```
### Test PSDiscoveryProtocol
```PowerShell
Invoke-DiscoveryProtocolCapture -Type CDP | Get-DiscoveryProtocolData
Invoke-DiscoveryProtocolCapture -Type LLDP | Get-DiscoveryProtocolData
```
    
The information returned by the commands above is what we have to work with when creating our new CIM class.

## Setup PSDiscoveryProtocol Baseline

The script [Install-PSDiscoveryProtocolBaseline.ps1](https://github.com/lahell/PSDiscoveryProtocol-SCCM-HWInventory/blob/master/Install-PSDiscoveryProtocolBaseline.ps1) will do most of the heavy lifting for us. You should always read through and try to understand it before you run anything you find online.

The script in the Configuration Item will install the package provider NuGet and the PSDiscoveryProtocol module. If you decide to deploy PSDiscoveryProtocol using a package in SCCM or some other way, you can remove this from the script:
```PowerShell
if ('NuGet' -notin (Get-PackageProvider).Name) {
    Install-PackageProvider -Name NuGet -Force | Out-Null
}

if ('PSDiscoveryProtocol' -notin (Get-InstalledModule).Name) {
    Install-Module -Name PSDiscoveryProtocol -Repository PSGallery -Confirm:$false -Force | Out-Null
}
```

1. Download **[Install-PSDiscoveryProtocolBaseline.ps1](https://raw.githubusercontent.com/lahell/PSDiscoveryProtocol-SCCM-HWInventory/master/Install-PSDiscoveryProtocolBaseline.ps1)**.
2. Start **Configuration Manager Console** and click on the dropdown menu in the top left corner.
3. Click **Connect via Windows PowerShell ISE**.
4. Press **F5** to run the script. Prompt should change to `PS SITECODE:\>`
5. Open **Install-PSDiscoveryProtocolBaseline.ps1** in **Windows PowerShell ISE**.
6. Press **F5** to run the script.
7. You will be prompted for `MyTestCollection`. Type the name of your collection. This collection must already exist.
8. You will be prompted for `DiscoveryProtocolType`. Type `CDP` or `LLDP`.
9. Wait for the script to finish.
10. Go back to **Configuration Manager Console**.
11. Navigate to **\Assets and Compliance\Overview\Compliance Settings\Configuration Items**.
12. Right click **PSDiscoveryProtocol** and click **Properties**.
13. Click **Supported Platforms** and unselect everything but Windows 10. Click OK.
14. Run **Download Computer Policy** on your test collection.
15. [Trigger baseline evaluation](#trigger-psdiscoveryprotocol-baseline-evaluation) on computers in your test collection.
16. Go to **\Administration\Overview\Client Settings**.
17. Right click **Default Client Settings** and click **Properties**.
18. Click **Hardware Inventory** and **Set Classes...** then click **Add...** and **Connect...**.
19. Connect to one of the computers where the baseline succeded, then find and select **PSDiscoveryProtocol** in the list of inventory classes.
20. Run **Collect Hardware Inventory** on your test collection.

The report named **PSDiscoveryProtocol** under **\Monitoring\Overview\Queries** should soon start to fill up.

If you want to check the contents of your new class you can run the following on one of the computers in the test collection:

```PowerShell
Get-CimInstance -ClassName PSDiscoveryProtocol
```

### Trigger PSDiscoveryProtocol Baseline Evaluation
```PowerShell
$Parameters = @{
    ComputerName = $env:COMPUTERNAME
    Namespace    = 'root\ccm\dcm'
    Class        = 'SMS_DesiredConfiguration'
}
$Baseline = Get-CimInstance @Parameters -Filter 'DisplayName="PSDiscoveryProtocol"'

if ($Baseline) {
    $Arguments = @{
        Name    = $Baseline.Name
        Version = $Baseline.Version
    }
    Invoke-CimMethod @Parameters -MethodName TriggerEvaluation -Arguments $Arguments
}
```

## Known issues
### Compliance error 0x87d00321
This means the script timed out. Maximum execution time for a script is 60 seconds. CDP packets are advertised every 60 seconds by default and PSDiscoveryProtcol will capture for 62 seconds just to make sure we don't miss out on a packet. You have several options to fix this issue:
* Change CDP advertisement interval to something lower than 60 seconds.
* Increase maximum execution time for scripts.
* Decrease duration for PSDiscoveryProtocol.
