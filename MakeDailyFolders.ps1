<#
.SYNOPSIS
    Creates a clean, human-readable annual folder structure containing only business days, Monday to Friday.

.DESCRIPTION
    Generates:

    RootFolder\
    └── 2024\
        └── 2024-01 Jan\
            └── 2024-01-01 Mon\
            └── 2024-01-02 Tue\
            └── ...

    Features:
    - Business days only, Monday to Friday
    - Correctly handles leap years
    - Uses invariant English abbreviations: Jan, Feb, Mon, Tue, etc.
    - Culture-independent date creation
    - Optional public holiday exclusion
    - Supports -WhatIf preview mode

.PARAMETER RootFolder
    Path to the root output directory. Accepts relative or absolute paths.
    Defaults to "Annual" in the current working directory.

.PARAMETER StartYear
    First year to generate folders for. Accepts 1-9999.

.PARAMETER EndYear
    Last year to generate folders for. Must be >= StartYear. Accepts 1-9999.

.PARAMETER Holidays
    Optional array of [datetime] values representing public holidays to exclude.
    Time components are ignored; only the date portion is matched.

.EXAMPLE
    New-AnnualFolderStructure -StartYear 2025 -EndYear 2026

.EXAMPLE
    $holidays = [datetime[]]@("2025-12-25", "2026-01-01", "2026-07-04")
    New-AnnualFolderStructure -StartYear 2025 -EndYear 2026 -Holidays $holidays

.EXAMPLE
    New-AnnualFolderStructure -StartYear 2024 -EndYear 2025 -WhatIf

.NOTES
    Version : 1.3.0
    Author  : mvm

    Version History:
    1.0.0 - Initial release. Nested loops (year > month > day). Business days only.
    1.1.0 - Added -WhatIf support via SupportsShouldProcess.
            Added Write-Progress per year.
            Added dot-source guard for interactive block.
    1.2.0 - Replaced triple nested loop with single linear date walk (AddDays).
            New-Item -Force now creates intermediate year/month folders implicitly.
            Added -Holidays parameter with HashSet for O(1) lookup.
            Replaced exit with return in interactive error paths.
    1.3.0 - Moved $businessDayFolderCount++ before ShouldProcess so -WhatIf
            returns an accurate preview count rather than zero.
            Extracted $isWeekend and $isHoliday as named booleans.
            Added cross-check (StartYear > EndYear) to interactive block.
            Added per-parameter .PARAMETER help.
#>

# =============================================================================
# HOW TO USE THIS SCRIPT
# =============================================================================
#
# There are three ways to run it:
#
# 1. RUN DIRECTLY (interactive prompts)
#    Just execute the script. It will ask for root folder, years, and WhatIf.
#
#       .\New-AnnualFolderStructure.ps1
#
# 2. DOT-SOURCE, THEN CALL (use the function in your own scripts or profile)
#    Dot-sourcing loads the function without triggering the interactive block.
#
#       . .\New-AnnualFolderStructure.ps1
#
#       # Basic: create folders for one year in the default "Annual" folder
#       New-AnnualFolderStructure -StartYear 2025 -EndYear 2025
#
#       # Custom root folder and multi-year range
#       New-AnnualFolderStructure -RootFolder 'C:\Work\Calendar' -StartYear 2025 -EndYear 2027
#
#       # Preview only — no folders created; returns accurate count
#       New-AnnualFolderStructure -StartYear 2025 -EndYear 2025 -WhatIf
#
#       # Exclude public holidays
#       $holidays = [datetime[]]@('2025-01-01', '2025-12-25', '2025-12-26')
#       New-AnnualFolderStructure -StartYear 2025 -EndYear 2025 -Holidays $holidays
#
#       # Capture the folder count
#       $count = New-AnnualFolderStructure -StartYear 2025 -EndYear 2026
#       Write-Host "$count business day folders processed."
#
# 3. GET HELP
#       Get-Help .\New-AnnualFolderStructure.ps1 -Full
#
# =============================================================================

function New-AnnualFolderStructure {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Position = 0)]
        [string]$RootFolder = "Annual",

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 9999)]
        [int]$StartYear,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 9999)]
        [int]$EndYear,

        [datetime[]]$Holidays = @()
    )

    if ($StartYear -gt $EndYear) {
        throw "StartYear cannot be greater than EndYear."
    }

    # Build a fully-qualified test path so Test-Path -IsValid can evaluate the
    # complete path, not just a bare relative segment like "Annual".
    # Test-Path -IsValid rejects illegal characters including control characters,
    # wildcards, and reserved names across platforms.
    $testPath = if ([System.IO.Path]::IsPathRooted($RootFolder)) {
        $RootFolder
    }
    else {
        Join-Path -Path $PWD -ChildPath $RootFolder
    }

    if (-not (Test-Path -LiteralPath $testPath -IsValid)) {
        throw "RootFolder contains invalid characters: '$RootFolder'"
    }

    # Store holidays in a HashSet normalised to midnight.
    # Normalising strips any time component from caller-supplied values,
    # ensuring dates like "2025-12-25 09:00" still match correctly.
    # HashSet gives O(1) lookup vs O(n) for an array.
    $holidaySet = [System.Collections.Generic.HashSet[datetime]]::new()

    foreach ($holiday in $Holidays) {
        $null = $holidaySet.Add($holiday.Date)
    }

    # InvariantCulture produces stable English abbreviations (Jan, Feb, Mon, Tue)
    # regardless of the OS locale, ensuring consistent folder names across machines.
    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    $totalYears             = $EndYear - $StartYear + 1
    $businessDayFolderCount = 0

    # -Force creates the directory if it does not exist and silently succeeds
    # if it already does, making the script safely idempotent.
    if ($PSCmdlet.ShouldProcess($RootFolder, "Create root directory")) {
        $null = New-Item -ItemType Directory -Path $RootFolder -Force
    }

    for ($year = $StartYear; $year -le $EndYear; $year++) {

        $yearIndex = $year - $StartYear + 1

        Write-Progress `
            -Activity "Generating Business Day Folders" `
            -Status "Processing $year ($yearIndex of $totalYears)" `
            -PercentComplete ([math]::Round((($yearIndex - 1) / $totalYears) * 100))

        # Linear date walk: simpler than nested month/day loops, and naturally
        # handles variable month lengths and leap years via the DateTime API.
        $currentDate = [datetime]::new($year, 1, 1)
        $endDate     = [datetime]::new($year, 12, 31)

        while ($currentDate -le $endDate) {

            $isWeekend = $currentDate.DayOfWeek -eq [System.DayOfWeek]::Saturday -or
                         $currentDate.DayOfWeek -eq [System.DayOfWeek]::Sunday

            $isHoliday = $holidaySet.Contains($currentDate.Date)

            if (-not $isWeekend -and -not $isHoliday) {

                $monthAbbr = $culture.DateTimeFormat.GetAbbreviatedMonthName($currentDate.Month)
                $dayAbbr   = $culture.DateTimeFormat.GetAbbreviatedDayName($currentDate.DayOfWeek)

                # Folder name format examples: "2025-03 Mar", "2025-03-17 Mon"
                $yearDir  = $currentDate.Year.ToString()
                $monthDir = '{0}-{1:D2} {2}'       -f $currentDate.Year, $currentDate.Month, $monthAbbr
                $dayDir   = '{0}-{1:D2}-{2:D2} {3}' -f $currentDate.Year, $currentDate.Month, $currentDate.Day, $dayAbbr

                $yearPath  = Join-Path -Path $RootFolder -ChildPath $yearDir
                $monthPath = Join-Path -Path $yearPath   -ChildPath $monthDir
                $dayPath   = Join-Path -Path $monthPath  -ChildPath $dayDir

                # Increment before ShouldProcess so -WhatIf returns an accurate
                # "would process" count rather than zero.
                $businessDayFolderCount++

                if ($PSCmdlet.ShouldProcess($dayPath, "Create business day folder")) {
                    # -Force creates intermediate year and month directories implicitly,
                    # eliminating the need for separate New-Item calls at those levels.
                    $null = New-Item -ItemType Directory -Path $dayPath -Force
                }
            }

            $currentDate = $currentDate.AddDays(1)
        }
    }

    Write-Progress -Activity "Generating Business Day Folders" -Completed

    # Returns the count of business day folders processed (created or already present).
    # Year and month folders are created implicitly and are not included in this count.
    return $businessDayFolderCount
}

# =============================================================================
# Interactive Execution
# Runs only when the script is executed directly, not when dot-sourced.
# Dot-sourcing (. .\New-AnnualFolderStructure.ps1) loads the function silently
# for use in other scripts or profiles without triggering prompts.
# =============================================================================

if ($MyInvocation.InvocationName -ne '.') {

    Clear-Host
    Write-Host "=== Annual Business Day Folder Creator ===" -ForegroundColor Cyan

    $rootInput  = Read-Host "Enter root folder name [Default: Annual]"
    $startInput = Read-Host "Enter start year, e.g. 2025"
    $endInput   = Read-Host "Enter end year, e.g. 2027"
    $confirm    = Read-Host "Run with -WhatIf? Y/N"

    # Declare [int] ref targets explicitly before TryParse.
    # Required under Set-StrictMode -Version Latest, which disallows
    # implicit variable creation. Keeps validation separate so each
    # failure produces a specific, targeted error message.
    [int]$startYear = 0
    [int]$endYear   = 0

    if (-not [int]::TryParse($startInput, [ref]$startYear)) {
        Write-Error "Start year must be a valid number."; return
    }

    if (-not [int]::TryParse($endInput, [ref]$endYear)) {
        Write-Error "End year must be a valid number."; return
    }

    # TryParse succeeds for values like 0 or -1, which [ValidateRange] in the
    # function would reject — but with a cryptic binding error. Catch them here
    # with friendly messages instead.
    if ($startYear -lt 1 -or $startYear -gt 9999) {
        Write-Error "Start year must be between 1 and 9999."; return
    }

    if ($endYear -lt 1 -or $endYear -gt 9999) {
        Write-Error "End year must be between 1 and 9999."; return
    }

    if ($startYear -gt $endYear) {
        Write-Error "Start year cannot be greater than end year."; return
    }

    $rootFolder = if ([string]::IsNullOrWhiteSpace($rootInput)) { "Annual" } else { $rootInput.Trim() }

    # Case-insensitive; -in operator is insensitive by default in PowerShell.
    # Trim() guards against accidental leading/trailing whitespace.
    $whatIf = $confirm.Trim().ToUpper() -in @('Y', 'YES')

    $params = @{
        RootFolder = $rootFolder
        StartYear  = $startYear
        EndYear    = $endYear
    }

    # WhatIf is only added to the splat when true.
    # Passing -WhatIf:$false explicitly is unnecessary and misleading.
    if ($whatIf) {
        $params['WhatIf'] = $true
    }

    $processed = New-AnnualFolderStructure @params

    if ($whatIf) {
        Write-Host "`nPreview complete. No folders were created." -ForegroundColor Yellow
        Write-Host "$processed business day folders would be processed in '$rootFolder' ($startYear-$endYear)." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nDone. $processed business day folders processed in '$rootFolder' ($startYear-$endYear)." -ForegroundColor Green
    }
}
