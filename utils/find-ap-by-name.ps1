# walk around with this running and it will show which ap you are connected to
# works with meraki APs as they expose a basic API on each AP.

while ($true) {
    $ap = Invoke-WebRequest -UseBasicParsing -Uri "http://10.128.128.126/index.json" | Select-Object -ExpandProperty Content | ConvertFrom-Json
    Write-Host "$($ap.config.node_name) $($ap.config.product_model)"
    Start-Sleep -Milliseconds 500
} 