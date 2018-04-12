# Sleep time between each connection test (seconds)
$SleepTime = 10
# Number of echo requests to send per test
$PingCount = 2
# Main loop sleep/screen refresh (seconds)
$MainLoopSleep = 1

# Destination to test (comment out to use default gateway)
$DestinationHost = "internetbeacon.msedge.net"

# Scriptblock to run on dropout
$1stScriptBlock = {
    Write-Host
    Write-Host "ScriptBlock 1 triggered" -ForegroundColor Red
    Start-Process notepad -Wait
}

# Scriptblock to run on 2nd consecutive failed test (i.e. after 1st)
$2ndScriptBlock = {
    Write-Host
    Write-Host "ScriptBlock 2 triggered" -ForegroundColor Red
    Start-Process notepad -Wait
}

# Scriptblock to run on 3nd consecutive failed test (i.e. after 2nd)
$3rdScriptBlock = {
    Write-Host
    Write-Host "ScriptBlock 3 triggered" -ForegroundColor Red
    Start-Process notepad -Wait
}

# Function - Ping using specific interface
Function Ping-BySourceIP {
    [CmdletBinding(DefaultParameterSetName="RegularPing",
                    PositionalBinding=$True,
                    HelpUri="https://github.com/BoonMeister/Ping-BySourceIP")]
    [OutputType("System.String")]
    [OutputType("System.Boolean")]
    [OutputType("System.Management.Automation.PSCustomObject")]
    Param(
        [Parameter(Mandatory=$True,ValueFromPipeline=$True,Position=0)]
        [ValidatePattern("^[0-9a-fA-F:][0-9a-fA-F:.]+[0-9a-fA-F]$")]
        [ValidateNotNullOrEmpty()]
        [String]$Source,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False,Position=1)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False,Position=1)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False,Position=1)]
        [Parameter(ParameterSetName="Regularv6Ping",Mandatory=$True,Position=1)]
        [Parameter(ParameterSetName="Quietv6Ping",Mandatory=$True,Position=1)]
        [Parameter(ParameterSetName="Detailedv6Ping",Mandatory=$True,Position=1)]
        [ValidatePattern("^[0-9a-zA-Z:][0-9a-zA-Z:.-]+[0-9a-zA-Z]$")]
        [ValidateNotNullOrEmpty()]
        [String]$Destination = "internetbeacon.msedge.net",
        [Parameter(Mandatory=$False,Position=2)]
        [ValidateRange(1,4294967295)]
        [Int]$Count = 2,
        [Parameter(Mandatory=$False,Position=3)]
        [ValidateRange(0,65500)]
        [Int]$Size = 32,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Switch]$NoFrag = $False,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Parameter(ParameterSetName="Regularv6Ping",Mandatory=$False)]
        [Parameter(ParameterSetName="Detailedv6Ping",Mandatory=$False)]
        [Switch]$ResolveIP = $False,
        [Parameter(ParameterSetName="Regularv6Ping",Mandatory=$True)]
        [Parameter(ParameterSetName="Quietv6Ping",Mandatory=$True)]
        [Parameter(ParameterSetName="Detailedv6Ping",Mandatory=$True)]
        [Switch]$ForceIPv6 = $False,
        [Parameter(ParameterSetName="QuietPing",Mandatory=$True)]
        [Parameter(ParameterSetName="Quietv6Ping",Mandatory=$True)]
        [Switch]$Quiet = $False,
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$True)]
        [Parameter(ParameterSetName="Detailedv6Ping",Mandatory=$True)]
        [Switch]$Detailed = $False
    )
    Begin {
        # Effectively Start-Process with stdout redirection and better window suppression
        Function Get-ProcessOutput {
            Param(
                [Parameter(Mandatory=$True)]
                [String]$Command,
                [String]$ArgList,
                [Switch]$NoWindow = $False,
                [Switch]$UseShell = $False,
                [Switch]$WaitForOutput = $False
            )
            $ProcInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcInfo.CreateNoWindow = $NoWindow
            $ProcInfo.FileName = $Command
            $ProcInfo.RedirectStandardError = $True
            $ProcInfo.RedirectStandardOutput = $True
            $ProcInfo.UseShellExecute = $UseShell
            $ProcInfo.Arguments = $ArgList
            $ProcObject = New-Object System.Diagnostics.Process
            $ProcObject.StartInfo = $ProcInfo
            $Null = $ProcObject.Start()
            If ($WaitForOutput) {
                $Output = $ProcObject.StandardOutput.ReadToEnd()
                $ProcObject.WaitForExit()
                $Output
            }
            Else {
                Do {
                    $ProcObject.StandardOutput.ReadLine()
                } Until ($ProcObject.HasExited)
                $ProcObject.StandardOutput.ReadToEnd()
                $ProcObject.WaitForExit()
            }
        }
    }
    Process {
        $MainCommand = "ping.exe"
        If ($ResolveIP) {$ProcArgs = "-a -n $Count -l $Size"}
        Else {$ProcArgs = "-n $Count -l $Size"}
        If ($NoFrag) {$ProcArgs += " -f"}
        If ($ForceIPv6) {$ProcArgs += " -S $Source -6 $Destination"}
        Else {$ProcArgs += " -S $Source -4 $Destination"}
        If ($Quiet -or $Detailed) {
            $FirstLineRegEx,$LatencyRegEx,$ReturnedCount,$LineCount = "bytes of data:","Average = ",0,0
            $PingResults = (Get-ProcessOutput -Command $MainCommand -ArgList $ProcArgs -NoWindow -WaitForOutput) -split "\r\n"
            If ($PingResults.Count -gt 2) {
                $ResultTable = @()
                $PacketResults = (($PingResults | Select-String $FirstLineRegEx -Context (0,$Count)) -split "\r\n")[1..$Count].Trim()
                Foreach ($Line in $PacketResults) {
                    $LineCount += 1
                    If ($Line -match "^Reply from .+(time=|time<)") {$PacketTest = $True}
                    Elseif ($Line -match "timed out|host unreachable|General failure|transmit failed|needs to be fragmented") {$PacketTest = $False}
                    Else {Throw "Regex failed to match on packet number $LineCount. The data was: '$Line'"}
                    If ($PacketTest) {$ReturnedCount += 1}
                    $ResultTable += $PacketTest
                }
                $PercentValue,$SentCount,$SizeVar = [Int]($ReturnedCount/$Count*100),$Count,$Size
                If ($ResultTable -contains $True) {$Result = $True}
                Else {$Result = $False}
            }
            Else {$SentCount,$PercentValue,$Result = 0,0,$False}
            If ($Quiet) {$Result}
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
                If (!$ForceIPv6) {$NoFragVar = $NoFrag}
                $ResultObj = New-Object PsObject
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Result" -Value $Result
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Sent" -Value $SentCount
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Received" -Value $ReturnedCount
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Percent" -Value $PercentValue
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Size" -Value $SizeVar
                $ResultObj | Add-Member -MemberType NoteProperty -Name "NoFrag" -Value $NoFragVar
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Source" -Value $SourceStr
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $DestStr
                $ResultObj | Add-Member -MemberType NoteProperty -Name "MinTime" -Value $MinTime
                $ResultObj | Add-Member -MemberType NoteProperty -Name "MaxTime" -Value $MaxTime
                $ResultObj | Add-Member -MemberType NoteProperty -Name "AvgTime" -Value $AvgTime
                $ResultObj | Add-Member -MemberType NoteProperty -Name "Text" -Value $PingResults
                $ResultObj
            }
        }
        Elseif (($Source -ne "") -and ($Source -ne $Null)) {Get-ProcessOutput -Command $MainCommand -ArgList $ProcArgs -NoWindow}
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
            $InterfaceIndex = $ActiveAdapters[$Index].InterfaceIndex
            $InterfaceGUID = $ActiveAdapters[$Index].GUID
        }
        # Only 1 active connection
        Else {
            $MacAddress = $ActiveAdapters.MACAddress
            $InterfaceName = $ActiveAdapters.Name
            $InterfaceIndex = $ActiveAdapters.InterfaceIndex
            $InterfaceGUID = $ActiveAdapters.GUID
        }
        $LastTestOK = $True
        $1stSBTriggered = $False
        $2ndSBTriggered = $False
        $OverallTestCounter = 0
        $DropOutCounter = 0
        $SuccessfulTestCounter = 0
        Write-Host
        Write-Host "Starting monitoring, one moment..."
        $MonitorStart = Get-Date
        $LastTestTime = Get-Date
        # Start monitoring loop
        Do {
            # Update IP address & default gateway at start or after dropout
            If (($OverallTestCounter -eq 0) -or (!$LastTestOK)) {
                $AdapterConfig = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where {$_.MACAddress -eq $MacAddress}
                Try {
                    If ($AdapterConfig.IPAddress.Count -gt 1) {[String]$SourceIP = $AdapterConfig.IPAddress}
                    Else {[String]$SourceIP = $AdapterConfig.IPAddress}
                    $DefaultGateway = $AdapterConfig.DefaultIPGateway
                }
                Catch {Throw "Could not retrieve the IP address or default gateway for the interface:`n$InterfaceName"}
                If ($DestinationHost) {$TestDestination = $DestinationHost}
                Else {$TestDestination = $DefaultGateway}
            }
            $CurrentTime = Get-Date
            $ElapsedTime = $CurrentTime-$MonitorStart
            # Test at start, on failure or after waiting for $SleepTime to pass
            If ((($CurrentTime-$LastTestTime).Seconds -gt $SleepTime) -or !$LastTestOK -or ($OverallTestCounter -eq 0)) {
                $TestResult = Ping-BySourceIP -Source $SourceIP -Destination $TestDestination -Count $PingCount -Detailed
                $OverallTestCounter += 1
                If ($TestResult.Result -eq $True) {
                    $SuccessfulTestCounter += 1
                    $LastTestOK = $True
                    $LastTestText = "OK"
                    $Colour = "Green"
                    $LatencyText = $TestResult.AvgTime
                    # Reset scriptblock flags
                    $1stSBTriggered = $False
                    $2ndSBTriggered = $False
                }
                Else {
                    If ($LastTestOK) {$DropOutCounter += 1}
                    $LastTestOK = $False
                    $LastTestText = "FAILED"
                    $Colour = "Red"
                    $LatencyText = "N/A"
                }
                $SuccessRate = ($SuccessfulTestCounter/$OverallTestCounter*100).ToString("0.0") + "%"
                $LastTestTime = Get-Date
            }
            $NextTestSecs = (($LastTestTime.AddSeconds($SleepTime))-$CurrentTime).Seconds
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
            Write-Host "Last test latency avg (ms): $LatencyText"
            Write-Host "Next test (s): $NextTestSecs"
            Write-Host
            Write-Host "Total dropouts detected: $DropOutCounter"
            Write-Host "Total tests: $OverallTestCounter"
            Write-Host "Successful tests: $SuccessfulTestCounter"
            Write-Host "Success rate: $SuccessRate"
            Write-Host
            Write-Host "Press F5 to stop monitoring"
            If (($TestResult.Result -eq $False) -and ($2ndSBTriggered)) {
                # Reset scriptblock flags
                $2ndSBTriggered = $False
                $1stSBTriggered = $False
                Invoke-Command -ScriptBlock $3rdScriptBlock
            }
            Elseif (($TestResult.Result -eq $False) -and ($1stSBTriggered)) {
                $2ndSBTriggered = $True
                Invoke-Command -ScriptBlock $2ndScriptBlock
            }
            Elseif ($TestResult.Result -eq $False) {
                $1stSBTriggered = $True
                Invoke-Command -ScriptBlock $1stScriptBlock
            }
            Start-Sleep -Seconds $MainLoopSleep
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
