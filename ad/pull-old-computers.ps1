# used to pull computer onto a csv for auditing using the lastlogondate field with in AD

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
$computers = get-adcomputer -filter {
    enabled -eq $true
    -and operatingsystem -like 'Windows 1*'
    -and lastlogondate -lt $date
} -properties *

$computers | sort-object lastlogondate | select-object name,operatingsystem,lastlogondate
