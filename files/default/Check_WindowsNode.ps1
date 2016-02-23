param(
[string]$memory_units = "none"
)

##############################################################
#
#  Created On:  09/03/2015
#  Author:  Jamin Shanti
#  Purpose: Check Windows Nodes
#
###############################################################
## program : powershell   arguments : -noprofile -executionpolicy bypass -command "& {C:\Check_WindowsNode.ps1 >> C:\Check_WindowsNode_Log.log 2>&1}"

import-module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

$ErrorActionPreference = 'Stop'


### Function that validates units passed. Default value of  Megabytes is used###
function parse-units {
	param ([string]$mem_units,
		[long]$mem_unit_div)
	$units = New-Object psobject
	switch ($memory_units.ToLower())
					{
						"bytes" 	{ 	$mem_units = "Bytes"; $mem_unit_div = 1}
						"kilobytes" { 	$mem_units = "Kilobytes"; $mem_unit_div = 1kb}
						"megabytes" { 	$mem_units = "Megabytes"; $mem_unit_div = 1mb}
						"gigabytes" {	$mem_units = "Gigabytes"; $mem_unit_div = 1gb}
						default 	{ 	$mem_units = "Megabytes"; $mem_unit_div = 1mb}
					}
	Add-Member -InputObject $units -Name "mem_units" -MemberType NoteProperty -Value $mem_units
 	Add-Member -InputObject $units -Name "mem_unit_div" -MemberType NoteProperty -Value $mem_unit_div
	return $units
}




### Function that gets memory stats using WMI###
function get-memory {

begin {}
process {
			$mem = New-Object psobject
			$units = parse-units
 			[long]$mem_avail_wmi = (get-WmiObject Win32_OperatingSystem | select -expandproperty FreePhysicalMemory) * 1kb
 			[long]$total_phy_mem_wmi = get-WmiObject Win32_ComputerSystem |  select -expandproperty TotalPhysicalMemory
 			[long]$mem_used_wmi = $total_phy_mem_wmi - $mem_avail_wmi
 			Add-Member -InputObject $mem -Name "mem_avail_wmi" -MemberType NoteProperty -Value $mem_avail_wmi
 			Add-Member -InputObject $mem -Name "total_phy_mem_wmi" -MemberType NoteProperty -Value $total_phy_mem_wmi
 			Add-Member -InputObject $mem -Name "mem_used_wmi" -MemberType NoteProperty -Value $mem_used_wmi
 			Add-Member -InputObject $mem -Name "mem_units" -MemberType NoteProperty -Value $units.mem_units
 			Add-Member -InputObject $mem -Name "mem_unit_div" -MemberType NoteProperty -Value $units.mem_unit_div
 			return $mem
 		}
 end{}
 }

### Function that gets disk stats using WMI###
function get-diskmetrics {

begin {}
process {
      $instancesdisks = Get-WMIObject Win32_LogicalDisk -filter "DriveType=3" 
      return $instancesdisks
 		}
 end{}
 }


### Function that gets disk stats using COM###
function get-update-status {

begin {}
process {
      $instanceUpdates = New-Object psobject
      $UpdateSession = New-Object -ComObject Microsoft.Update.Session
      $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
      $SearchResult = $UpdateSearcher.Search("IsHidden=0 and IsInstalled=0 and BrowseOnly=0")
      [Object[]] $Critical = $SearchResult.updates | where { $_.MsrcSeverity -eq "Critical" }
      [Object[]] $Important = $SearchResult.updates | where { $_.MsrcSeverity -eq "Important" }
      Add-Member -InputObject $instanceUpdates -Name "Critical" -MemberType NoteProperty -Value $Critical.count
      Add-Member -InputObject $instanceUpdates -Name "Important" -MemberType NoteProperty -Value $Important.count
      return $instanceUpdates
 		}
 end{}
 }

### Function that gets disk stats using AWSSDK###
function get-instance-info {

begin {}
process {
			$instance = New-Object psobject
 			$instanceId = (wget -Uri http://169.254.169.254/latest/meta-data/instance-id).Content
 			$region = (wget -Uri http://169.254.169.254/latest/meta-data/placement/availability-zone).Content
 			$region = $region.Substring(0,$region.Length-1)
 			$instanceName = (Get-EC2Tag -Region $region | ` Where-Object {$_.ResourceId -eq $instanceId -and $_.Key -eq 'Name'}).Value
            Add-Member -InputObject $instance -Name "instanceId" -MemberType NoteProperty -Value $instanceId
            Add-Member -InputObject $instance -Name "region" -MemberType NoteProperty -Value $region
 			Add-Member -InputObject $instance -Name "instanceName" -MemberType NoteProperty -Value $instanceName	
 			return $instance
 		}
 end{}
 }
 
 ### Function that writes CW metrics using AWSSDK###
function write-CWMetrics {
    param ([string]$dimension1Name,
            $dimension1Value,
            [string]$dimension2Name,
            $dimension2Value,
            [string]$metricName,
            $metricUnit,
            $metricValue)
begin {}
process {
        #Create dimensions
        $dimensions = New-Object System.Collections.ArrayList
        $dimension1 = New-Object -TypeName Amazon.CloudWatch.Model.Dimension
        $dimension2 = New-Object -TypeName Amazon.CloudWatch.Model.Dimension

         
        $dimension1.Name = $dimension1Name
        $dimension1.Value = $dimension1Value
        $dimension2.Name = $dimension2Name
        $dimension2.Value = $dimension2Value
         
        $dat = New-Object Amazon.CloudWatch.Model.MetricDatum
        $dat.Timestamp = (Get-Date).ToUniversalTime() 
        $dat.MetricName = $metricName
        $dat.Unit = $metricUnit
        $dat.Value = $metricValue
        $dat.Dimensions.Add($dimension1)
        $dat.Dimensions.Add($dimension2)
        "Writing Metric $($dat.MetricName)..."
        Write-CWMetricData -Namespace "System/Windows" -MetricData $dat	
 		}
 end{}
 }
 

$instanceMemory = get-memory
$disklist = get-diskmetrics
$instanceinfo = get-instance-info
$updatestatus = get-update-status

# Try/Catch if Mcafee isn't installed.
Try
 {
$AVDatVersion = (Get-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\McAfee\AVEngine).AVDatVersion 
 }
 Catch [system.exception]
 {
  $AVDatVersion = 0000
 }

Set-DefaultAWSRegion -Region $instanceinfo.region

"InstanceId    : $($instanceinfo.instanceId)"
"region    : $($instanceinfo.region)"
"InstanceName    : $($instanceinfo.instanceName)"

foreach ($diskobj in $disklist){
          [long]$FullDiskSpace = [long]$diskobj.size - [long]$diskobj.FreeSpace
					$percent_disk_util = 100 * ([long]$FullDiskSpace/[long]$diskobj.size)
					
					"DiskPrecentFill    : $($percent_disk_util)"					
}
[long]$FullMemSpace = [long]$instanceMemory.total_phy_mem_wmi - [long]$instanceMemory.mem_avail_wmi
$percent_mem_util = 100 * ([long]$FullMemSpace/[long]$instanceMemory.total_phy_mem_wmi)


"MemoryPrecentFill    : $($percent_mem_util)"		
"Critical Updates Count : $($updatestatus.Critical)"
"Important Updates Count : $($updatestatus.Important)"			

"Writing Metrics..."
write-CWMetrics -dimension1Name "InstanceId" -dimension1Value $instanceinfo.instanceId -dimension2Name "InstanceName"  -dimension2Value $instanceinfo.instanceName -metricName "MemoryUtilization" -metricUnit "Percent" -metricValue $percent_mem_util
write-CWMetrics -dimension1Name "InstanceId" -dimension1Value $instanceinfo.instanceId -dimension2Name "InstanceName"  -dimension2Value $instanceinfo.instanceName -metricName "SystemUpdatesCritical" -metricUnit "Count" -metricValue $updatestatus.Critical
write-CWMetrics -dimension1Name "InstanceId" -dimension1Value $instanceinfo.instanceId -dimension2Name "InstanceName"  -dimension2Value $instanceinfo.instanceName -metricName "SystemUpdatesImportant" -metricUnit "Count" -metricValue $updatestatus.Important
write-CWMetrics -dimension1Name "InstanceId" -dimension1Value $instanceinfo.instanceId -dimension2Name "InstanceName"  -dimension2Value $instanceinfo.instanceName -metricName "AVDatVersion" -metricUnit "Count" -metricValue $AVDatVersion


foreach ($diskobj in $disklist){
          [long]$FullDiskSpace = [long]$diskobj.size - [long]$diskobj.FreeSpace
					$percent_disk_util = 100 * ([long]$FullDiskSpace/[long]$diskobj.size)
          write-CWMetrics -dimension1Name "Drive-Letter" -dimension1Value $diskobj.deviceid -dimension2Name "InstanceId"  -dimension2Value $instanceinfo.instanceId  -metricName "VolumeUtilization" -metricUnit "Percent" -metricValue $percent_disk_util
}


