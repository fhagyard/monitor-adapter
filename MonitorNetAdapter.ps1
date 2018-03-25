Function Ping-BySourceIP {
    [CmdletBinding(DefaultParameterSetName="RegularPing")]
    Param(
        [Parameter(ParameterSetName="RegularPing",Mandatory=$True)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$True)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$True)]
        [String]$Source,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$True)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$True)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$True)]
        [String]$Destination,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Int]$Count = 2,
        [Parameter(ParameterSetName="RegularPing",Mandatory=$False)]
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [ValidateRange(0,65500)]
        [Int]$Size = 32,
        [Parameter(ParameterSetName="QuietPing",Mandatory=$False)]
        [Switch]$Quiet = $False,
        [Parameter(ParameterSetName="DetailedPing",Mandatory=$False)]
        [Switch]$Detailed = $False
    )
    $MainCommand = "ping -n $Count -l $Size -S $Source $Destination"
    If ($Quiet -or $Detailed) {
        $BoolScript = {
            $ReturnedCount = 0
            If ($PingResults.Count -gt 1) {
                $ResultTable = @()
                $FailureStrings = @(
                    "Request timed out"
                    "Destination host unreachable"
                    "General failure"
                    "could not find host"
                    "not a valid address"
                )
                $PacketResults = (($PingResults | Select-String "bytes of data:" -Context (0,$Count)) -split "\r\n")[1..$Count]
                Foreach ($Line in $PacketResults) {
                    $Line = $Line.ToString()
                    If (($Line -match "Reply from") -and (($Line -match "time=") -or ($Line -match "time<"))) {$PacketTest = $True}
                    Else {
                        $PacketTest = $True
                        Foreach ($String in $FailureStrings) {
                            If ($Line -match $String) {
                                $PacketTest = $False
                                Break
                            }
                        }
                    }
                    If ($PacketTest) {$ReturnedCount += 1}
                    $ResultTable += $PacketTest
                }
                If ($ResultTable -contains $True) {$Result = $True}
                Else {$Result = $False}
            }
            Else {$Result = $False}
            Return $Result,$ReturnedCount
        }
        $PingResults = Invoke-Expression -Command $MainCommand
        $ConnectionTest = Invoke-Command -ScriptBlock $BoolScript
        If ($Quiet) {
            Return $ConnectionTest[0]
        }
        Elseif ($Detailed) {
            $ResultObj = New-Object PsObject
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Result" -Value $ConnectionTest[0]
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Sent" -Value $Count
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Received" -Value $ConnectionTest[1]
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Percent" -Value ([Int]($ConnectionTest[1]/$Count*100))
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Size" -Value $Size
            If (($ConnectionTest[0]) -and ($PingResults | Select-String "Average = " -Quiet)) {
                $Times = (($PingResults | Select-String "Average = ").ToString() -split ",").Trim()
                $MinTime = ($Times[0] -split "=")[1].Trim() -replace "ms",""
                $MaxTime = ($Times[1] -split "=")[1].Trim() -replace "ms",""
                $AvgTime = ($Times[2] -split "=")[1].Trim() -replace "ms",""
            }
            $ResultObj | Add-Member -MemberType NoteProperty -Name "MinTime" -Value $MinTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "MaxTime" -Value $MaxTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "AvgTime" -Value $AvgTime
            $ResultObj | Add-Member -MemberType NoteProperty -Name "Text" -Value $PingResults
            Return $ResultObj
        }
    }
    Else {Invoke-Expression -Command $MainCommand}
}
