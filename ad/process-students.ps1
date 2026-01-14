# used to create student accounts in bulk to match our internal SOP
# the inputs include a bromcom export and the school name

$csv = .\bromcom.csv
$school = "$(Read-Host -Prompt "School Name") Academy"

if ((Get-ADForest | Measure-Object | Select-Object -ExpandProperty Count) -eq 1) {
	$address = Get-ADForest | select-object -ExpandProperty UPNSuffixes
} else {
	$address = "astrea$(Read-Host -Prompt "UPN code").org"
}

$pwdprefix = @(
    "Cat",
    "Dog",
    "Fish"
)

$sync_ou = Get-ADOrganizationalUnit -filter "Name -eq 'Sync'"
$ou = Get-ADOrganizationalUnit -SearchBase $sync_ou -Filter "Name -eq 'Pupil'"

$users = Import-Csv $csv
$groups = $users | Select-Object -Unique -ExpandProperty 'Tutor Group'
$groups += "Leavers"

# $ou_leaver = Get-ADOrganizationalUnit -SearchBase $ou -Filter "Name -eq '$($groups[-1])'"

$groups | ForEach-Object {
    if ($null -eq (Get-ADOrganizationalUnit -SearchBase $ou -Filter "Name -eq '$($_)'")) {
        New-ADOrganizationalUnit -Name $_ -Path $ou
        Write-Host "[$_] does not exist, creating..."
    } else {
        Write-Host "[$_] already exists, skipping..."
    }
}

$output = @()
$output += $users | ForEach-Object {
    $user_name = $_.'First Name' + " " + $_.'Last Name'
    $user_sam = $user_name -replace " ","."
    $user_sam_trunc = $user_sam[0..19] -join ''
    $user_display = $user_name + " (Student, $school)"

    $user_ou = Get-ADOrganizationalUnit -SearchBase $ou -Filter "Name -eq '$($_.'Tutor Group')'"
    $user_object = Get-ADUser -SearchBase $ou -Filter "SamAccountName -eq '$user_sam_trunc'"

    $user_pwd = "$(Get-Random -InputObject $pwdprefix)$(Get-Random -Minimum 100 -Maximum 999)!"

    if ($null -eq $user_object) {
        $user_params = @{
            Name = $user_name
            GivenName = $_.'First Name'
            Surname = $_.'Last Name'
            SamAccountName = $user_sam_trunc
            UserPrincipalName = "$user_sam@$address"
            DisplayName = $user_display
            Department = "Student, $school"
            Office = $school
            
            AccountPassword = (ConvertTo-SecureString $user_pwd -AsPlainText -Force)
            Enabled = $true
            ChangePasswordAtLogon = $false
        }

        New-ADUser @user_params -Path $user_ou
    }
    else {
        $user_object | Move-ADObject -TargetPath $user_ou
    }

    $user_object = Get-ADUser -SearchBase $ou -Filter "SamAccountName -eq '$user_sam_trunc'"
    $user_object | Set-ADAccountPassword -NewPassword (ConvertTo-SecureString $user_pwd -AsPlainText -Force)
    $user_object | Set-ADUser -Title "Student" -Description $_.'Tutor Group'    

    return @{
        First       = $_.'First Name'
        Last        = $_.'Last Name'
        Username    = $user_sam
        Email       = "$user_sam@$address"
        Password    = $user_pwd
        TutorGroup  = $_.'Tutor Group'
    }
}

$output | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -NoTypeInformation -LiteralPath "$(Get-Date -Format "yyyy-MM-dd") - out.csv"