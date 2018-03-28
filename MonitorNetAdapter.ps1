# Sleep time between each connection test (seconds)
$SleepTime = 1
# Number of echo requests to send per test
$PingCount = 2

# Destination to test (comment out to use default gateway)
$DestinationHost = "internetbeacon.msedge.net"

# Scriptblock to run on dropout
$FailureScriptBlock = {
    Write-Host
    Write-Host "Connection is down!" -ForegroundColor Red
    Start-Process notepad.exe -Wait # Do something
}

# Function - Ping using specific interface
Function Ping-BySourceIP {
    [CmdletBinding(DefaultParameterSetName="RegularPing")]
    Param(
        [Parameter(ParameterSetName="RegularPing",Mandatory=$True,ValueFromPipeline=$True)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$True,ValueFromPipeline=$True)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$True,ValueFromPipeline=$True)]
        [ValidatePattern("^((\d{1,2}|1\d\d|2[0-4]\d|25[0-5])\.){3}(\d{1,2}|1\d\d|2[0-4]\d|25[0-5])$")]
        [String]$Source,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [String]$Destination = "internetbeacon.msedge.net",
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [ValidateRange(1,4294967295)]
        [Int]$Count = 2,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [ValidateRange(0,65500)]
        [Int]$Size = 32,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Switch]$NoFrag = $False,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Switch]$ResolveIP = $False,
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Switch]$Quiet = $False,
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Switch]$Detailed = $False
    )
    $MainCommand = "ping"
    If ($ResolveIP) {$MainCommand += " -a"}
    $MainCommand += " -n $Count -l $Size"
    If ($NoFrag) {$MainCommand += " -f"}
    $MainCommand += " -S $Source -4 $Destination"
    If ($Quiet -or $Detailed) {
        $FirstLineRegEx,$LatencyRegEx,$ReturnedCount,$LineCount = "bytes of data:","Average = ",0,0
        $PingResults = Invoke-Expression -Command $MainCommand
        If ($PingResults.Count -gt 1) {
            $ResultTable = @()
            $PacketResults = (($PingResults | Select-String $FirstLineRegEx -Context (0,$Count)) -split "\r\n")[1..$Count].Trim()
            Foreach ($Line in $PacketResults) {
                $LineCount += 1
                If ($Line -match "^Reply from .*(time=|time<)") {$PacketTest = $True}
                Elseif ($Line -match "timed out|host unreachable|General failure|transmit failed|needs to be fragmented") {$PacketTest = $False}
                Else {Throw "Regex failed to match on packet number $LineCount. The data was: '$Line'"}
                If ($PacketTest) {$ReturnedCount += 1}
                $ResultTable += $PacketTest
            }
            $PercentValue,$SentCount = [Int]($ReturnedCount/$Count*100),$Count
            If ($ResultTable -contains $True) {$Result = $True}
            Else {$Result = $False}
        }
        Else {
            $SentCount,$PercentValue,$Result = 0,0,$False
            Remove-Variable -Name Size,NoFrag
        }
        If ($Quiet) {Return $Result}
        Elseif ($Detailed) {
            If ($PingResults | Select-String $FirstLineRegEx -Quiet) {
                $FirstLine = ($PingResults | Select-String $FirstLineRegEx).ToString() -split " from "
                $SourceStr = ($FirstLine[1] -split " ")[0]
                $DestStr = $FirstLine[0] -replace "^Pinging ",""
            }
            Else {$SourceStr,$DestStr = $Source,$Destination}
            If ($Result -and ($PingResults | Select-String $LatencyRegEx -Quiet)) {
                $Times = (($PingResults | Select-String $LatencyRegEx).ToString() -split ",").Trim()
                $MinTime = ($Times[0] -split "=")[1].Trim() -replace "ms",""
                $MaxTime = ($Times[1] -split "=")[1].Trim() -replace "ms",""
                $AvgTime = ($Times[2] -split "=")[1].Trim() -replace "ms",""
            }
            $ResultObj = New-Object PsObject
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Result" -Value $Result
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Sent" -Value $SentCount
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Received" -Value $ReturnedCount
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Percent" -Value $PercentValue
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Size" -Value $Size
            $ResultObj | Add-Member -MemberType NoteProperty -Name "NoFrag" -Value $NoFrag
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Source" -Value $SourceStr
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $DestStr
            $ResultObj | Add-Member -MemberType NoteProperty -Name "MinTime" -Value $MinTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "MaxTime" -Value $MaxTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "AvgTime" -Value $AvgTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Text" -Value $PingResults
            Return $ResultObj
        }
    }
}

# Prompt to start
$ConfirmRetry = ""
$ConfirmStart = ""
Write-Host "This script will monitor a local interface for any network dropouts"
While ("YES","Y","NO","N" -notcontains $ConfirmStart) {
    $ConfirmStart = (Read-Host "Would you like to start?(Y/N)").ToUpper()
}
If ("NO","N" -contains $ConfirmStart) {$ConfirmRetry = "N"}
While ("NO","N" -notcontains $ConfirmRetry) {
    $ActiveAdapters = Get-WmiObject -Class Win32_NetworkAdapter | Where {$_.NetConnectionStatus -eq 2}
    If ($ActiveAdapters) {
        # More than 1 active connection
        If ($ActiveAdapters.Count -gt 1) {
            $IndexRange = 1..($ActiveAdapters.Count)
            Write-Host
            Write-Warning "More than one network adapter with an active connection was detected."
            Write-Host
            Write-Host "Please select the adapter you would like to monitor from the following list:"
            Write-Host
            Foreach ($Number in $IndexRange) {
                $Index = $Number - 1
                Write-Host "$Number)" $ActiveAdapters[$Index].Name
            }
            Write-Host
            $UserChoice = ""
            While ($IndexRange -notcontains $UserChoice) {
                $UserChoice = Read-Host "Please enter the number for your choice"
            }
            $Index = $UserChoice - 1
            $MacAddress = $ActiveAdapters[$Index].MACAddress
            $InterfaceName = $ActiveAdapters[$Index].Name
        }
        # Only 1 active connection
        Else {
            $MacAddress = $ActiveAdapters.MACAddress
            $InterfaceName = $ActiveAdapters.Name
        }
        $AdapterConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where {$_.MACAddress -eq $MacAddress}
        If ($AdapterConfig.IPAddress.Count -gt 1) {$SourceIP = $AdapterConfig.IPAddress[0]}
        Else {$SourceIP = $AdapterConfig.IPAddress}
        $DefaultGateway = $AdapterConfig.DefaultIPGateway
        $LastTestOK = $True
        $OverallTestCounter = 0
        $DropOutCounter = 0
        $SuccessfulTestCounter = 0
        If ($DestinationHost) {$TestDestination = $DestinationHost}
        Else {$TestDestination = $DefaultGateway}
        Write-Host
        Write-Host "Starting monitoring, one moment..."
        $MonitorStart = Get-Date
        # Start monitoring loop
        Do {
            $ElapsedTime = (Get-Date)-$MonitorStart
            $TestResult = Ping-BySourceIP -Source $SourceIP -Destination $TestDestination -Count $PingCount -Detailed
            $OverallTestCounter += 1
            If ($TestResult.Result -eq $True) {
                $SuccessfulTestCounter += 1
                $LastTestOK = $True
                $LastTestText = "OK"
                $Colour = "Green"
            }
            Else {
                If ($LastTestOK) {$DropOutCounter += 1}
                $LastTestOK = $False
                $LastTestText = "FAILED"
                $Colour = "Red"
            }
            $SuccessRate = ($SuccessfulTestCounter/$OverallTestCounter*100).ToString("0.0") + "%"
            Clear-Host
            Write-Host "Start:" $MonitorStart
            Write-Host "Time elapsed (D:H:M:S): " $ElapsedTime.Days ":" $ElapsedTime.Hours ":" $ElapsedTime.Minutes ":" $ElapsedTime.Seconds -Separator ""
            Write-Host
            Write-Host "Interface: $InterfaceName"
            Write-Host "IP Address: $SourceIP"
            Write-Host "Default Gateway: $DefaultGateway"
            Write-Host "Test Destination: $TestDestination"
            Write-Host
            Write-Host "Last test result: " -NoNewline
            Write-Host "$LastTestText" -ForegroundColor $Colour
            Write-Host "Last test latency avg (ms):" $TestResult.Average
            Write-Host
            Write-Host "Total dropouts detected: $DropOutCounter"
            Write-Host "Total tests: $OverallTestCounter"
            Write-Host "Successful tests: $SuccessfulTestCounter"
            Write-Host "Success rate: $SuccessRate"
            Write-Host
            Write-Host "Press F5 to stop monitoring"
            If ($TestResult.Result -eq $False) {Invoke-Command -ScriptBlock $FailureScriptBlock}
            Start-Sleep -Seconds $SleepTime
        } While (!($Host.UI.RawUI.KeyAvailable -and ($Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,IncludeKeyUp").VirtualKeyCode -eq 116)))
        $MonitorEnd = Get-Date
        $TotalTime = $MonitorEnd-$MonitorStart
        Write-Host
        Write-Host "Script stopped!"
        Write-Host
        Write-Host "Start:" $MonitorStart
        Write-Host "Finish:" $MonitorEnd
        Write-Host "Total time (D:H:M:S): " $TotalTime.Days ":" $TotalTime.Hours ":" $TotalTime.Minutes ":" $TotalTime.Seconds -Separator ""
    }
    # No active connections detected
    Else {
        Write-Host
        Write-Warning "No network adapter with an active Internet connection was detected!`nWhen starting this script please ensure there is at least 1 active network connection"
    }
    Write-Host
    $ConfirmRetry = ""
    While ("YES","Y","NO","N" -notcontains $ConfirmRetry) {
        $ConfirmRetry = (Read-Host "Would you like to restart the script?(Y/N)").ToUpper()
    }
}
