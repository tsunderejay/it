# . ./sophos-lib.ps1
# this will dot source the file

function Get-SCCliPath
{
    $sophosPath = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Sophos\Connect\sccli.exe"
    if ($sophosPath -and (Test-Path $sophosPath))
    {
        $sophosPath
    } else
    {
        Write-Error "Sophos Connect not found"
    }
}

function Parse-CLIOutput
{
    param (
        [Parameter(Mandatory=$true)]
        [string]$output
    )

    # Find the index of "Received JSON from the server:"
    $startIndex = $output.IndexOf("Received JSON from the server:")

    if ($startIndex -eq -1)
    {
        Write-Warning "Could not find 'Received JSON from the server:' in output"
        return $null
    }

    # Extract everything after the key phrase
    $keyPhrase = "Received JSON from the server:"
    $jsonStartIndex = $startIndex + $keyPhrase.Length
    $remainingText = $output.Substring($jsonStartIndex).Trim()

    # Find the start of JSON (either { or [)
    $jsonStart = -1
    for ($i = 0; $i -lt $remainingText.Length; $i++)
    {
        if ($remainingText[$i] -eq '{' -or $remainingText[$i] -eq '[')
        {
            $jsonStart = $i
            break
        }
    }

    if ($jsonStart -eq -1)
    {
        Write-Warning "Could not find JSON start in output after key phrase"
        return $null
    }

    # Extract JSON by counting braces/brackets to handle multiline JSON
    $jsonText = $remainingText.Substring($jsonStart)
    $openChar = $jsonText[0]
    $closeChar = if ($openChar -eq '{')
    { '}'
    } else
    { ']'
    }

    $depth = 0
    $jsonEnd = -1
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $jsonText.Length; $i++)
    {
        $char = $jsonText[$i]

        if ($escaped)
        {
            $escaped = $false
            continue
        }

        if ($char -eq '\')
        {
            $escaped = $true
            continue
        }

        if ($char -eq '"')
        {
            $inString = -not $inString
            continue
        }

        if (-not $inString)
        {
            if ($char -eq $openChar)
            {
                $depth++
            } elseif ($char -eq $closeChar)
            {
                $depth--
                if ($depth -eq 0)
                {
                    $jsonEnd = $i
                    break
                }
            }
        }
    }

    if ($jsonEnd -eq -1)
    {
        Write-Warning "Could not find complete JSON in output"
        return $remainingText.Trim()
    }

    return $jsonText.Substring(0, $jsonEnd + 1) | ConvertFrom-Json
}

function Get-SCList
{
    $output = & (Get-SCCliPath) list -d -V
    $parsedJson = Parse-CLIOutput [string]$output
    return $parsedJson.connections
}

function Find-SCConnection
{
    param(
        [Parameter(Mandatory=$true)]
        [string]$Identifier
    )

    $connections = Get-SCList

    # Try to find connection by name first
    $connection = $connections | Where-Object { $_.name -eq $Identifier }

    # If not found, try to find by display name
    if (-not $connection)
    {
        $connection = $connections | Where-Object { $_.display_name -eq $Identifier }
    }

    return $connection
}

function Get-SCConnected
{
    Get-SCList | Where-Object { $_.vpn_state -eq "3" }
}

function Get-SCActiveConnections
{
    # Returns connections that are either connecting (state 1) or connected (state 3)
    Get-SCList | Where-Object { $_.vpn_state -eq "1" -or $_.vpn_state -eq "3" }
}

function Get-SCConnectionList
{
    <#
    .SYNOPSIS
    Lists all available Sophos Connect VPN connections with their names and display names.

    .DESCRIPTION
    This function displays all configured VPN connections in a user-friendly format,
    showing both the connection ID (name) and display name for easy reference.
    #>

    $connections = Get-SCList

    if (-not $connections -or $connections.Count -eq 0)
    {
        Write-Warning "No VPN connections found"
        return
    }

    Write-Host "Available Sophos Connect VPN Connections:" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    foreach ($connection in $connections)
    {
        $status = switch ($connection.vpn_state)
        {
            "0"
            { "Disconnected"
            }
            "1"
            { "Connecting"
            }
            "2"
            { "Connected"
            }
            "3"
            { "Connected"
            }
            "4"
            { "Disconnecting"
            }
            default
            { "Unknown"
            }
        }

        $statusColor = if ($connection.vpn_state -eq "3")
        { "Green"
        } else
        { "Yellow"
        }

        Write-Host "  Connection ID: " -NoNewline
        Write-Host "$($connection.name)" -ForegroundColor Cyan
        Write-Host "  Display Name:  " -NoNewline
        Write-Host "$($connection.display_name)" -ForegroundColor White
        Write-Host "  Status:        " -NoNewline
        Write-Host "$status" -ForegroundColor $statusColor
        Write-Host ""
    }

    Write-Host "You can use either the Connection ID or Display Name with Enable-SCConnection and Disable-SCConnection functions." -ForegroundColor Gray
}

function Disable-SCConnection
{
    <#
    .SYNOPSIS
    Disables (disconnects) a Sophos Connect VPN connection.

    .DESCRIPTION
    This function disconnects from a specified VPN connection. You can specify the connection
    using either the connection ID (name) or the display name. The function will automatically
    find the connection and disconnect from it, then wait for the disconnection to complete.

    .PARAMETER ConnectionId
    The connection identifier. Can be either:
    - Connection ID (name): The internal connection identifier
    - Display Name: The user-friendly display name of the connection

    .PARAMETER TimeoutSeconds
    How long to wait for the disconnection to complete (default: 60 seconds)

    .EXAMPLE
    Disable-SCConnection -ConnectionId "MyVPN"
    Disconnects from a connection with display name "MyVPN"

    .EXAMPLE
    Disable-SCConnection -ConnectionId "connection-123" -TimeoutSeconds 60
    Disconnects from connection "connection-123" with 60 second timeout

    .NOTES
    Use Get-SCConnectionList to see all available connections and their identifiers.
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ConnectionId,   # Can be either the connection name/ID or display name
        [int]$TimeoutSeconds = 60
    )

    $activeConnections = Get-SCActiveConnections
    if (-Not $activeConnections)
    {
        Write-Warning "No active VPN connections to disconnect"
        return
    }

    # Find connection by name or display name
    $connection = Find-SCConnection -Identifier $ConnectionId

    if (-not $connection)
    {
        Write-Warning "Connection '$ConnectionId' not found"
        return
    }

    $actualConnectionId = $connection.name
    $displayName = $connection.display_name

    # Show current state before disconnecting
    $currentState = switch ($connection.vpn_state)
    {
        "1"
        { "connecting"
        }
        "3"
        { "connected"
        }
        default
        { "active"
        }
    }

    Write-Host "Disconnecting $currentState connection: '$displayName'"

    Write-Host "Disconnecting '$displayName' ($actualConnectionId)..." -ForegroundColor Yellow

    $output = & (Get-SCCliPath) disable -n $actualConnectionId

    # Wait for connection to reach disconnected state (0) regardless of initial output
    $elapsed = 0
    do
    {
        Start-Sleep -Seconds 1
        $elapsed++
        $currentConnection = Get-SCList | Where-Object { $_.name -eq $actualConnectionId }
        Write-Host "." -NoNewline -ForegroundColor Gray
    } while ($currentConnection -and $currentConnection.vpn_state -ne "0" -and $elapsed -lt $TimeoutSeconds)

    Write-Host ""  # New line after dots

    # Check final state
    $finalConnection = Get-SCList | Where-Object { $_.name -eq $actualConnectionId }
    if ($finalConnection -and $finalConnection.vpn_state -eq "0")
    {
        Write-Host "Connection '$displayName' ($actualConnectionId) disconnected" -ForegroundColor Green
    } elseif ($elapsed -ge $TimeoutSeconds)
    {
        Write-Warning "Timeout waiting for disconnection of '$displayName' ($actualConnectionId)"
    } else
    {
        Write-Warning "Failed to disable connection '$displayName' ($actualConnectionId)"
    }
}

function Enable-SCConnection
{
    <#
    .SYNOPSIS
    Enables (connects to) a Sophos Connect VPN connection.

    .DESCRIPTION
    This function connects to a specified VPN connection. You can specify the connection
    using either the connection ID (name) or the display name. If another VPN is already
    connected, you can use the -Force parameter to disconnect it first. The function waits
    for the connection to be fully established before returning.

    .PARAMETER ConnectionId
    The connection identifier. Can be either:
    - Connection ID (name): The internal connection identifier
    - Display Name: The user-friendly display name of the connection

    .PARAMETER Force
    If specified, will automatically disconnect any existing VPN connection before
    connecting to the specified one.

    .PARAMETER TimeoutSeconds
    How long to wait for the connection to be established (default: 60 seconds)

    .EXAMPLE
    Enable-SCConnection -ConnectionId "MyVPN"
    Connects to a connection with display name "MyVPN"

    .EXAMPLE
    Enable-SCConnection -ConnectionId "connection-123" -Force -TimeoutSeconds 60
    Connects to connection "connection-123" with 60 second timeout, disconnecting any existing connection first

    .NOTES
    Use Get-SCConnectionList to see all available connections and their identifiers.
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$ConnectionId,   # Can be either the connection name/ID or display name
        [switch]$Force,
        [int]$TimeoutSeconds = 60
    )

    # Find connection by name or display name
    $connection = Find-SCConnection -Identifier $ConnectionId

    if (-not $connection)
    {
        Write-Warning "Connection '$ConnectionId' not found"
        return
    }

    $actualConnectionId = $connection.name
    $displayName = $connection.display_name

    $activeConnections = Get-SCActiveConnections
    if ($activeConnections)
    {
        Write-Warning "Already have active VPN connection(s)"
        if ($Force)
        {
            # Disconnect all active connections
            foreach ($activeConnection in $activeConnections)
            {
                Write-Host "Disconnecting active connection: $($activeConnection.display_name)"
                Disable-SCConnection -ConnectionId $activeConnection.name
            }
        } else
        {
            Write-Warning "Use -Force to disconnect existing connection(s)"
            return
        }
    }

    Write-Host "Connecting to '$displayName' ($actualConnectionId)..." -ForegroundColor Yellow

    $output = & (Get-SCCliPath) enable -n $actualConnectionId

    # Wait for connection to reach connected state (3) regardless of initial output
    $elapsed = 0
    do
    {
        Start-Sleep -Seconds 1
        $elapsed++
        $currentConnection = Get-SCList | Where-Object { $_.name -eq $actualConnectionId }
        Write-Host "." -NoNewline -ForegroundColor Gray
    } while ($currentConnection -and $currentConnection.vpn_state -ne "3" -and $elapsed -lt $TimeoutSeconds)

    Write-Host ""  # New line after dots

    # Check final state
    $finalConnection = Get-SCList | Where-Object { $_.name -eq $actualConnectionId }
    if ($finalConnection -and $finalConnection.vpn_state -eq "3")
    {
        Write-Host "Connection '$displayName' ($actualConnectionId) established" -ForegroundColor Green
    } elseif ($elapsed -ge $TimeoutSeconds)
    {
        Write-Warning "Timeout waiting for connection to '$displayName' ($actualConnectionId)"
    } else
    {
        Write-Warning "Failed to enable connection '$displayName' ($actualConnectionId)"
    }
}

function Disconnect-AllSCConnections
{
    <#
    .SYNOPSIS
    Disconnects all active Sophos Connect VPN connections.

    .DESCRIPTION
    This function disconnects all VPN connections that are currently active (either
    connecting or connected). Useful for quickly clearing all VPN connections.

    .PARAMETER Force
    If specified, disconnects all connections without prompting for confirmation.

    .PARAMETER Silent
    If specified, suppresses informational output and only shows warnings/errors.

    .EXAMPLE
    Disconnect-AllSCConnections
    Disconnects all active VPN connections with confirmation prompt

    .EXAMPLE
    Disconnect-AllSCConnections -Force
    Disconnects all active VPN connections without confirmation

    .EXAMPLE
    Disconnect-AllSCConnections -Force -Silent
    Disconnects all active VPN connections silently

    .NOTES
    This function will disconnect connections in both connecting and connected states.
    #>

    param(
        [switch]$Force,
        [switch]$Silent
    )

    $activeConnections = Get-SCActiveConnections

    if (-not $activeConnections)
    {
        if (-not $Silent)
        {
            Write-Host "No active VPN connections to disconnect" -ForegroundColor Green
        }
        return
    }

    if (-not $Silent)
    {
        Write-Host "Found $($activeConnections.Count) active connection(s) to disconnect:" -ForegroundColor Yellow

        foreach ($connection in $activeConnections)
        {
            $state = if ($connection.vpn_state -eq "1")
            { "connecting"
            } else
            { "connected"
            }
            Write-Host "  - $($connection.display_name) ($state)"
        }

        Write-Host ""
    }

    # Confirmation prompt unless Force is specified
    if (-not $Force)
    {
        $confirmation = Read-Host "Are you sure you want to disconnect all active VPN connections? (y/N)"
        if ($confirmation -notmatch '^[Yy]')
        {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
    }

    foreach ($connection in $activeConnections)
    {
        if ($Silent)
        {
            # Call disable with minimal output
            $output = & (Get-SCCliPath) disable -n $connection.name 2>&1
            if ($output -notmatch "was disabled")
            {
                Write-Warning "Failed to disable connection '$($connection.display_name)'"
            }
        } else
        {
            Disable-SCConnection -ConnectionId $connection.name
        }
    }

    if (-not $Silent)
    {
        Write-Host "All active connections have been disconnected" -ForegroundColor Green
    }
}

# Convenient aliases
Set-Alias -Name "sclist" -Value "Get-SCConnectionList"
Set-Alias -Name "scdisconnect" -Value "Disconnect-AllSCConnections"
Set-Alias -Name "scstatus" -Value "Get-SCStatus"
Set-Alias -Name "scconnect" -Value "Enable-SCConnection"
Set-Alias -Name "scon" -Value "Enable-SCConnection"
Set-Alias -Name "scoff" -Value "Disable-SCConnection"
Set-Alias -Name "scmenu" -Value "Show-SCConnectionMenu"
Set-Alias -Name "scwatch" -Value "Watch-SCStatus"

function Get-SCStatus
{
    <#
    .SYNOPSIS
    Shows a quick status summary of Sophos Connect VPN connections.

    .DESCRIPTION
    Displays a brief overview of current VPN connection status, including
    connected and connecting connections.

    .EXAMPLE
    Get-SCStatus
    Shows current VPN status

    .NOTES
    This is a quick way to check VPN status without the full connection list.
    #>

    $activeConnections = Get-SCActiveConnections
    $allConnections = Get-SCList

    if (-not $allConnections)
    {
        Write-Host "No VPN connections configured" -ForegroundColor Red
        return
    }

    Write-Host "Sophos Connect VPN Status" -ForegroundColor Green
    Write-Host "========================" -ForegroundColor Green
    Write-Host "Total Connections: $($allConnections.Count)" -ForegroundColor White

    if ($activeConnections)
    {
        Write-Host "Active Connections: $($activeConnections.Count)" -ForegroundColor Yellow
        foreach ($connection in $activeConnections)
        {
            $state = if ($connection.vpn_state -eq "1")
            { "Connecting"
            } else
            { "Connected"
            }
            $stateColor = if ($connection.vpn_state -eq "3")
            { "Green"
            } else
            { "Yellow"
            }
            Write-Host "  ► $($connection.display_name) - " -NoNewline -ForegroundColor White
            Write-Host "$state" -ForegroundColor $stateColor
        }
    } else
    {
        Write-Host "Active Connections: 0" -ForegroundColor Gray
        Write-Host "  All connections are disconnected" -ForegroundColor Gray
    }
}

function Show-SCConnectionMenu
{
    <#
    .SYNOPSIS
    Shows an interactive menu to select and connect to a VPN connection.

    .DESCRIPTION
    Displays a numbered menu of all available VPN connections for easy selection.
    User can choose a connection by number to connect to it.

    .EXAMPLE
    Show-SCConnectionMenu
    Shows interactive connection menu
    #>

    $connections = Get-SCList

    if (-not $connections -or $connections.Count -eq 0)
    {
        Write-Host "No VPN connections found" -ForegroundColor Red
        return
    }

    Write-Host "Sophos Connect VPN Menu" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green
    Write-Host ""

    for ($i = 0; $i -lt $connections.Count; $i++)
    {
        $connection = $connections[$i]
        $status = if ($connection.vpn_state -eq "3")
        { " [CONNECTED]"
        } elseif ($connection.vpn_state -eq "1")
        { " [CONNECTING]"
        } else
        { ""
        }
        $statusColor = if ($connection.vpn_state -eq "3")
        { "Green"
        } elseif ($connection.vpn_state -eq "1")
        { "Yellow"
        } else
        { "White"
        }

        Write-Host "  $($i + 1). " -NoNewline -ForegroundColor Cyan
        Write-Host "$($connection.display_name)" -NoNewline -ForegroundColor White
        Write-Host "$status" -ForegroundColor $statusColor
    }

    Write-Host ""
    Write-Host "  0. Disconnect all" -ForegroundColor Red
    Write-Host "  q. Quit" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Select connection (1-$($connections.Count), 0 to disconnect all, q to quit)"

    if ($choice -eq "q" -or $choice -eq "Q")
    {
        return
    }

    if ($choice -eq "0")
    {
        Disconnect-AllSCConnections
        return
    }

    $index = $null
    if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $connections.Count)
    {
        $selectedConnection = $connections[$index - 1]
        Write-Host "Connecting to: $($selectedConnection.display_name)" -ForegroundColor Yellow
        Enable-SCConnection -ConnectionId $selectedConnection.name -Force
    } else
    {
        Write-Host "Invalid selection" -ForegroundColor Red
    }
}



function Watch-SCStatus
{
    <#
    .SYNOPSIS
    Continuously monitors VPN connection status.

    .DESCRIPTION
    Displays real-time VPN connection status updates. Useful for monitoring
    connection stability or watching for state changes.

    .PARAMETER RefreshInterval
    How often to refresh the display in seconds (default: 5)

    .EXAMPLE
    Watch-SCStatus
    Monitor status with 5-second refresh

    .EXAMPLE
    Watch-SCStatus -RefreshInterval 2
    Monitor status with 2-second refresh
    #>

    param(
        [int]$RefreshInterval = 5
    )

    Write-Host "Watching Sophos Connect status (Press Ctrl+C to stop)" -ForegroundColor Green
    Write-Host "Refresh interval: $RefreshInterval seconds" -ForegroundColor Gray
    Write-Host ""

    while ($true)
    {
        Clear-Host
        Write-Host "Sophos Connect Status Monitor" -ForegroundColor Green
        Write-Host "============================" -ForegroundColor Green
        Write-Host "Last Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        Write-Host ""

        Get-SCStatus

        Write-Host ""
        Write-Host "Press Ctrl+C to stop monitoring..." -ForegroundColor Gray

        Start-Sleep -Seconds $RefreshInterval
    }
}

# Module initialization message
Write-Host "Sophos Connect PowerShell Library loaded!" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Gray
Write-Host "  scstatus     - Quick status check" -ForegroundColor Cyan
Write-Host "  sclist       - List all connections" -ForegroundColor Cyan
Write-Host "  scmenu       - Interactive connection menu" -ForegroundColor Cyan
Write-Host "  scon <name>  - Connect to VPN" -ForegroundColor Cyan
Write-Host "  scoff <name> - Disconnect from VPN" -ForegroundColor Cyan

Write-Host "  scdisconnect - Disconnect all VPNs" -ForegroundColor Cyan
Write-Host "  scwatch      - Monitor VPN status" -ForegroundColor Cyan

Write-Host "Type 'Get-Help <command>' for more info" -ForegroundColor Gray
