[CmdletBinding()]
param(
    [Parameter(Mandatory,
        HelpMessage='Enter the name of the existing collection you want to use for testing')]
    [ValidateScript({[bool](Get-CMCollection -Name $_)})]
    [string]
    $MyTestCollection,

    [Parameter(Mandatory,
        HelpMessage='You need to choose whether you want to capture LLDP or CDP')]
    [ValidateSet('CDP', 'LLDP')]
    [string]
    $DiscoveryProtocolType
)

$DiscoveryScript = {
    # If you set $EnableTranscript to $true, two files will be created in $env:TEMP
    # PowerShell_transcript.COMPUTERNAME.xxxxxxxx.yyyyMMddHHmmss.txt
    # DiscoveryProtocolData.txt
    $EnableTranscript = $false

    if ($EnableTranscript) {
        Start-Transcript -OutputDirectory $env:TEMP | Out-Null
    }

    $Name = 'PSDiscoveryProtocol'

    Get-CimInstance -ClassName $Name | Remove-CimInstance -ErrorAction SilentlyContinue

    $Class = New-Object System.Management.ManagementClass ('root\cimv2', [String]::Empty, $null)
    $Class['__CLASS'] = $Name

    $Class.Qualifiers.Add('Static', $true)
    $Class.Properties.Add('Device', [System.Management.CimType]::String, $false)
    $Class.Properties.Add('Port', [System.Management.CimType]::String, $false)
    $Class.Properties.Add('VLAN', [System.Management.CimType]::UInt16, $false)
    $Class.Properties.Add('LastUpdate', [System.Management.CimType]::DateTime, $false)
    $Class.Properties['Device'].Qualifiers.Add('Key', $true)
    $Class.Properties['Port'].Qualifiers.Add('Key', $true)
    $Class.Put() | Out-Null

    if ('NuGet' -notin (Get-PackageProvider).Name) {
        Install-PackageProvider -Name NuGet -Force | Out-Null
    }

    if ('PSDiscoveryProtocol' -notin (Get-InstalledModule).Name) {
        Install-Module -Name PSDiscoveryProtocol -Repository PSGallery -Confirm:$false -Force | Out-Null
    }

    $DiscoveryProtocolData = Invoke-DiscoveryProtocolCapture -Type $DiscoveryProtocolType | Get-DiscoveryProtocolData

    if ($EnableTranscript) {
        $DiscoveryProtocolData | ConvertTo-Json | Out-File $env:TEMP\DiscoveryProtocolData.txt
    }

    $DiscoveryProtocolData | ForEach-Object {
        New-CimInstance -ClassName $Name -Property @{
            Device     = $_.Device
            Port       = $_.Port
            VLAN       = $_.VLAN
            LastUpdate = Get-Date
        } | Out-Null
    }

    if ($EnableTranscript) {
        Stop-Transcript | Out-Null
    }

    Write-Output 'Success'
}

$Name = 'PSDiscoveryProtocol'
$ConfigurationItem = New-CMConfigurationItem -Name $Name -CreationType WindowsOS
$ConfigurationItem | Add-CMComplianceSettingScript -Name $Name -DiscoveryScriptLanguage PowerShell -DataType String -DiscoveryScriptText $DiscoveryScript.ToString().Replace('$DiscoveryProtocolType', $DiscoveryProtocolType) -NoRule -Is64Bit:$true | Out-Null
$Setting = Get-CMComplianceSetting -Name $Name
$Rule = New-CMComplianceRuleValue -ExpectedValue Success -ExpressionOperator IsEquals -RuleName $Name -InputObject $Setting
$ConfigurationItem | Add-CMComplianceSettingRule -Rule $Rule | Out-Null
$Baseline = New-CMBaseline -Name $Name
$Baseline | Set-CMBaseline -AddOSConfigurationItem $ConfigurationItem.CI_ID
$null = New-CMBaselineDeployment -Name $Name -CollectionName $MyTestCollection
$Expression = 'select SMS_R_System.Name, SMS_G_System_PSDISCOVERYPROTOCOL.Device, SMS_G_System_PSDISCOVERYPROTOCOL.Port, SMS_G_System_PSDISCOVERYPROTOCOL.VLAN, SMS_G_System_PSDISCOVERYPROTOCOL.LastUpdate from  SMS_R_System inner join SMS_G_System_PSDISCOVERYPROTOCOL on SMS_G_System_PSDISCOVERYPROTOCOL.ResourceID = SMS_R_System.ResourceId order by SMS_R_System.Name'
$null = New-CMQuery -Name $Name -Expression $Expression -TargetClassName SMS_R_System

Write-Output 'Finished'
