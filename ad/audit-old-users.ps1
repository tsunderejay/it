# used to pull users onto a csv for auditing using the lastlogondate field with in AD

# check we are running from a domain controller
if ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -eq 2)
{
    Write-Host "running from a domain controller"
} else
{
    Write-Host "not running from a domain controller"
    exit
}

$date = (Get-Date).AddDays(-30)
$users = get-aduser -filter {
    enabled -eq $true
    -and lastlogondate -lt $date
} -properties *

$users | sort-object lastlogondate
