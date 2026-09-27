$ErrorActionPreference = 'Stop'
$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$template = Join-Path $folder 'Battery_Diagnostic.html'
$report = Join-Path $folder 'Battery_Report.html'
$tempReport = Join-Path $env:TEMP ("BatteryReport_" + [guid]::NewGuid().ToString('N') + '.html')

function First-Number($values) {
    foreach ($v in @($values)) {
        if ($null -ne $v) {
            $n = 0.0
            if ([double]::TryParse(([string]$v).Replace(',','').Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
                if ($n -gt 0) { return $n }
            }
        }
    }
    return $null
}

function Get-ReportValue([string]$html, [string[]]$labels) {
    foreach ($label in $labels) {
        $pattern = '(?is)' + [regex]::Escape($label) + '.*?([0-9][0-9,]*)\s*mWh'
        $m = [regex]::Match($html, $pattern)
        if ($m.Success) { return First-Number @($m.Groups[1].Value) }
    }
    return $null
}

function Get-ReportText([string]$html, [string[]]$labels) {
    foreach ($label in $labels) {
        $pattern = '(?is)' + [regex]::Escape($label) + '.*?<td[^>]*>\s*([^<]+?)\s*</td>'
        $m = [regex]::Match($html, $pattern)
        if ($m.Success) { return ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)).Trim() }
    }
    return $null
}

try {
    if (-not (Test-Path -LiteralPath $template)) { throw 'Battery_Diagnostic.html was not found. Keep all files together.' }

    # -----------------------------
    # 1. Query WMI/CIM first
    # -----------------------------
    $static = @(Get-CimInstance -Namespace 'root/WMI' -ClassName 'BatteryStaticData' -ErrorAction SilentlyContinue)
    $fullObj = @(Get-CimInstance -Namespace 'root/WMI' -ClassName 'BatteryFullChargedCapacity' -ErrorAction SilentlyContinue)
    $cycleObj = @(Get-CimInstance -Namespace 'root/WMI' -ClassName 'BatteryCycleCount' -ErrorAction SilentlyContinue)
    $statusObj = @(Get-CimInstance -Namespace 'root/WMI' -ClassName 'BatteryStatus' -ErrorAction SilentlyContinue)
    $winBattery = @(Get-CimInstance -ClassName 'Win32_Battery' -ErrorAction SilentlyContinue)

    $s = $static | Select-Object -First 1
    $b = $winBattery | Select-Object -First 1

    $design = First-Number @(
        ($static | ForEach-Object { $_.DesignedCapacity })
    )
    $full = First-Number @(
        ($fullObj | ForEach-Object { $_.FullChargedCapacity })
        ($static | ForEach-Object { $_.FullChargedCapacity })
    )
    $cycles = First-Number @(
        ($cycleObj | ForEach-Object { $_.CycleCount })
    )
    $remaining = First-Number @(
        ($statusObj | ForEach-Object { $_.RemainingCapacity })
    )

    # -----------------------------
    # 2. IMPORTANT FALLBACK:
    # Generate Microsoft's batteryreport and read Design/Full Capacity.
    # This is much more reliable on laptops where BatteryStaticData is empty.
    # -----------------------------
    $reportHtml = $null
    try {
        & powercfg.exe /batteryreport /output "$tempReport" | Out-Null
        if (Test-Path -LiteralPath $tempReport) {
            $reportHtml = [IO.File]::ReadAllText($tempReport)
        }
    } catch { }

    if ($reportHtml) {
        if (-not $design) {
            $design = Get-ReportValue $reportHtml @('DESIGN CAPACITY','DESIGN CAPACITY')
        }
        if (-not $full) {
            $full = Get-ReportValue $reportHtml @('FULL CHARGE CAPACITY','FULL CHARGE CAPACITY')
        }
        if (-not $cycles) {
            $cycles = First-Number @(
                (Get-ReportText $reportHtml @('CYCLE COUNT','CYCLE COUNT'))
            )
        }
    }

    # -----------------------------
    # 3. Additional fallback from Win32_Battery
    # -----------------------------
    if (-not $currentCharge -and $b -and $null -ne $b.EstimatedChargeRemaining) {
        $currentCharge = [int]$b.EstimatedChargeRemaining
    }
    if (-not $currentCharge -and $remaining -and $full) {
        $currentCharge = [math]::Round(($remaining / $full) * 100, 0)
    }

    $health = if ($design -and $full) { [math]::Round(($full / $design) * 100, 1) } else { $null }
    $loss = if ($health -ne $null) { [math]::Round([math]::Max(0, 100 - $health), 1) } else { $null }

    # Battery status
    $charging = $false
    $discharging = $false
    if ($b) {
        if ($b.BatteryStatus -eq 2) { $charging = $true }
        if ($b.BatteryStatus -eq 1) { $discharging = $true }
    }
    foreach ($st in @($statusObj)) {
        if ($st.Charging -eq $true) { $charging = $true }
        if ($st.Discharging -eq $true) { $discharging = $true }
    }
    $powerStatus = if ($charging) { 'Charging' } elseif ($discharging) { 'Discharging' } elseif ($b) { 'Connected / Not charging' } else { 'Not available' }

    $chemistryCode = if ($s) { $s.Chemistry } else { $null }
    $chemistry = switch ([int]$chemistryCode) {
        1 { 'Other' }; 2 { 'Unknown' }; 3 { 'Lead Acid' }; 4 { 'Nickel Cadmium' }
        5 { 'Nickel Metal Hydride' }; 6 { 'Lithium-ion' }; 7 { 'Zinc air' }; 8 { 'Lithium Polymer' }
        default { if ($chemistryCode) { [string]$chemistryCode } else { 'N/A' } }
    }

    $cs = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName 'Win32_BIOS' -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction SilentlyContinue

    $manufacturer = if ($s -and $s.ManufacturerName) { $s.ManufacturerName } elseif ($b -and $b.Name) { $b.Name } else { 'N/A' }
    $batteryName = if ($s -and $s.DeviceName) { $s.DeviceName } elseif ($b -and $b.Name) { $b.Name } else { 'N/A' }
    $serial = if ($s -and $s.SerialNumber) { $s.SerialNumber } elseif ($b -and $b.DeviceID) { $b.DeviceID } else { 'N/A' }
    $designVoltage = if ($s -and $s.DesignedVoltage) { $s.DesignedVoltage } elseif ($b -and $b.DesignVoltage) { $b.DesignVoltage } else { $null }

    $data = [ordered]@{
        computerName = $env:COMPUTERNAME
        manufacturer = $manufacturer
        systemProductName = if ($cs -and $cs.Model) { $cs.Model } else { 'Unknown laptop' }
        batteryName = $batteryName
        serialNumber = $serial
        chemistry = $chemistry
        designCapacity = $design
        fullChargeCapacity = $full
        cycleCount = $cycles
        currentCharge = $currentCharge
        powerStatus = $powerStatus
        designVoltage = $designVoltage
        bios = if ($bios -and $bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { 'N/A' }
        osBuild = if ($os -and $os.BuildNumber) { $os.BuildNumber } else { 'N/A' }
        dataSource = if ($design -and $full) { 'Windows battery data + battery report fallback' } else { 'Windows battery data' }
        reportTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }

    $json = $data | ConvertTo-Json -Compress
    $html = [IO.File]::ReadAllText($template)
    $html = $html.Replace('__BATTERY_DATA__', $json)
    [IO.File]::WriteAllText($report, $html, (New-Object System.Text.UTF8Encoding($false)))

    if (Test-Path -LiteralPath $tempReport) { Remove-Item -LiteralPath $tempReport -Force -ErrorAction SilentlyContinue }
    Start-Process $report
    exit 0
}
catch {
    if (Test-Path -LiteralPath $tempReport) { Remove-Item -LiteralPath $tempReport -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    Write-Host 'Battery Diagnostic Error:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
