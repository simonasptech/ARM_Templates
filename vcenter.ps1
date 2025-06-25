# PowerCLI Script: Download ESXi SSL Certificates and Configure Syslog over SSL  
  
# Variables - SET THESE ACCORDING TO YOUR ENVIRONMENT  
$vCenterServer    = "vcenter.example.com"  
$SyslogTargetHost = "syslog.example.net:6514"  # Use FQDN/IP:Port  
  
# Path for storing downloaded PEM files  
$CertDownloadPath = "c:\temp\ESXi_Certs"  
New-Item -Path $CertDownloadPath -ItemType Directory -Force | Out-Null  
$creds = get-credential -Message "Enter vCenter credentials"  
# Connect to vCenter  
Connect-VIServer -Server $vCenterServer
  
# Get all ESXi hosts in the vCenter  
$VMHosts = Get-VMHost  
  
foreach ($VMHost in $VMHosts) {  
    Write-Host "`nProcessing host:" $VMHost.Name -ForegroundColor Cyan  
  
        # 1. Download SSL Certificate and save as CRT (PEM format)  
    $ESXHostFQDN = $VMHost.Name  
    $CertCRTPath = Join-Path $CertDownloadPath "$ESXHostFQDN.crt"  
  
    try {  
        # Use .NET X509Certificate2 to grab the cert over TCP/443  
        $tcpClient = New-Object System.Net.Sockets.TcpClient($ESXHostFQDN, 443)  
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, ({ $true }))  
        $sslStream.AuthenticateAsClient($ESXHostFQDN)  
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate  
        $pem = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----"  
        Set-Content -Path $CertCRTPath -Value $pem  
        $sslStream.Close()  
        $tcpClient.Close()  
        Write-Host "  SSL certificate saved to: $CertCRTPath" -ForegroundColor Green  
    } catch {  
        Write-Warning "  Failed to retrieve SSL certificate for $ESXHostFQDN"  
    } 
  
    # # 2. Get current syslog server targets  
    # $SyslogConfig = Get-VMHostAdvancedConfiguration -VMHost $VMHost -Name "Syslog.global.logHost"  
    # $CurrentSyslogTargets = @()  
    # if ($SyslogConfig.'Syslog.global.logHost') {  
    #     $CurrentSyslogTargets = $SyslogConfig.'Syslog.global.logHost' -split ','  
    # }  
  
    # # 3. Prepare new syslog target (over SSL - use 'tls://host:port')  
    # $NewSyslogTarget = "tls://$SyslogTargetHost"  
  
    # # 4. Append to list if not already present  
    # if ($CurrentSyslogTargets -notcontains $NewSyslogTarget) {  
    #     $AllSyslogTargets = $CurrentSyslogTargets + $NewSyslogTarget  
    #     $SyslogTargetsStr = ($AllSyslogTargets | Where-Object {$_ -ne ""}) -join ","  
    #     Set-VMHostAdvancedConfiguration -VMHost $VMHost -Name "Syslog.global.logHost" -Value $SyslogTargetsStr  
    #     Write-Host "  Syslog server list updated: $SyslogTargetsStr" -ForegroundColor Green  
    # } else {  
    #     Write-Host "  Syslog target $NewSyslogTarget already present" -ForegroundColor Yellow  
    # }  
  
    # # 5. Enable syslog firewall rule  
    # Get-VMHostFirewallException -VMHost $VMHost | Where-Object {$_.Name -eq "syslog"} | Set-VMHostFirewallException -Enabled:$true  
    # Write-Host "  Syslog firewall rule enabled" -ForegroundColor Green  
  
    # # 6. Restart hostd (restarts syslog service as part of management agent restart)  
    # $esxcli = Get-EsxCli -VMHost $VMHost -V2  
    # $esxcli.system.syslog.reload.Invoke()  
    # Write-Host "  Syslog service reloaded" -ForegroundColor Green  
}  
  
# Disconnect vCenter session  
Disconnect-VIServer -Server $vCenterServer -Confirm:$false  
  
Write-Host "`nAll done." -ForegroundColor Cyan  