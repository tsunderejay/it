Get-Content -Path "$PSScriptRoot\secrets.json" | ConvertFrom-Json | Select-Object -ExpandProperty drives | ForEach-Object {
    $out = subst.exe "$($_.letter):" "$($_.path)"
    if ($out -eq "Drive already SUBSTED")
    {
        Write-Host "Drive $($_.letter) already mounted ($($_.path))"
    } else
    {
        Write-Host "Drive $($_.letter) mounted successfully ($($_.path))"
    }
}
