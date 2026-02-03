# i used this script to create matching OUs across multiple sites at my current job

# check we are running from a domain controller
if ((Get-WmiObject -Class Win32_OperatingSystem).ProductType -eq 2)
{
    Write-Host "running from a domain controller"
} else
{
    Write-Host "not running from a domain controller"
    exit
}

$schoolName = Read-Host "Enter the school name (no special characters)"
$schoolDN = "OU=$schoolName"

$domainDN = (Get-ADDomain).DistinguishedName
$mainDN = "$schoolDN,$domainDN"

# Define the OU structure
$ouPaths = @(
    "OU=Users,$mainDN",
    "OU=Workstations,$mainDN",
    "OU=Groups,$mainDN",
    "OU=Servers,$mainDN"

    "OU=Staff,OU=Users,$mainDN"
    "OU=Sync,OU=Users,$mainDN"

    "OU=Leavers,OU=Staff,OU=Users,$mainDN"

    "OU=Pupil,OU=Sync,OU=Users,$mainDN"
    "OU=Staff,OU=Sync,OU=Users,$mainDN"

    "OU=Leavers,OU=Pupil,OU=Sync,OU=Users,$mainDN"
    "OU=Leavers,OU=Staff,OU=Sync,OU=Users,$mainDN"

    "OU=Staff,OU=Workstations,$mainDN"
    "OU=Pupil,OU=Workstations,$mainDN"
    "OU=Disabled,OU=Workstations,$mainDN"
)

$rootOU = "OU=$schoolName,$domainDN"
if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$rootOU)" -ErrorAction SilentlyContinue))
{
    New-ADOrganizationalUnit -Name $schoolName -Path $domainDN -ProtectedFromAccidentalDeletion $false
}

foreach ($ou in $ouPaths)
{
    if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$ou)" -ErrorAction SilentlyContinue))
    {
        $ouName = ($ou.Split(",")[0] -replace "OU=","")
        $ouPath = $ou.Substring($ou.IndexOf(",")+1)
        New-ADOrganizationalUnit -Name $ouName -Path $ouPath -ProtectedFromAccidentalDeletion $false
    }
}

Write-Host "OU structure created for $schoolName in domain $domainDN."
