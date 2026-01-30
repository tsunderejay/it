# bulk setting up a3 license for students within my work environment
if (-not (Get-MgContext))
{
    Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome
}

# A1 is 'STANDARDWOFFPACK_STUDENT'
# A3 is 'M365EDU_A3_STUUSEBNFT'
$requiredLicense = Get-MgBetaSubscribedSku | Where-Object { $_.SkuPartNumber -eq 'M365EDU_A3_STUUSEBNFT' }

# Get our secret information
$schools = Get-Content ./secrets.json | ConvertFrom-Json
$schools | ForEach-Object {
    $name = $_.name

    Write-Host "Processing $name..."

    $students = Get-MgBetaUser -All -Filter "AccountEnabled eq true and startswith(Department, 'Student, $name')"
    $students | ForEach-Object {
        $id = $_.Id

        $licenses = Get-MgBetaUserLicenseDetail -UserId $id

        $licensesToRemove = $licenses | Where-Object { $_.SkuPartNumber -ne $requiredLicense.SkuPartNumber }
        $licensesToRemove | ForEach-Object {
            Remove-MgBetaUserLicense -UserId $id -SkuId $_.SkuId
        }

        Write-Host "$($licensesToRemove.Count) licenses removed for $($_.DisplayName)"

        if (($licenses | Where-Object { $_.SkuPartNumber -eq $requiredLicense.SkuPartNumber }).Count -eq 0)
        {
            Add-MgBetaUserLicense -UserId $id -SkuId $requiredLicense.SkuId
            Set-MgBetaUser -UserId $id -UsageLocation "GB"
            Write-Host "$($requiredLicense.SkuPartNumber) license added for $($_.DisplayName)"
        } else
        {
            Write-Host "No licenses to change for $($_.DisplayName)"
        }
    }

    Write-Host "Finished processing $name...."
}
