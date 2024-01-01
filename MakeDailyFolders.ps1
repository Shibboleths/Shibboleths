
# ChatGPT generated based on instructions by Mark McCullagh below
#
# Use PowerShell to create a folder called Annual 
# and within that, folders for the years 2024 to 2029 to test several years.
# Within each year's folder generate a folder for each month in the 
# format year hyphen two-digit month space abbreviated month name. 
# Within these monthly folders generate folders for each business day 
# i.e. Monday to Friday. 
# Check for the number of valid days in each month including leap years 
# and Business Day folders should be in the 
# format year hyphen two-digit month hyphen day space Abbreviated Weekday name. 
#
# This is designed to be international & for humans to manually insert 
# files quickly in the relevant place:
# YYYY folder e.g. 2024
# YYYY-MM Mon subfolder e.g. 2024-01 Jan
# YYYY-MM-DD Day sub-subfolder e.g. 2024-01-01 Mon
# Function to determine the number of valid days in a month, considering leap years
function Get-DaysInMonth {
    param (
        [int]$year,
        [int]$month
    )

    $daysInMonth = [System.DateTime]::DaysInMonth($year, $month)
    return $daysInMonth
}

# Function to create folder structure
function Create-FolderStructure {
    param (
        [string]$rootFolder,
        [int]$startYear,
        [int]$endYear
    )

    # Create the "Annual" folder
    New-Item -ItemType Directory -Path $rootFolder -Force

    for ($year = $startYear; $year -le $endYear; $year++) {
        $yearFolder = Join-Path -Path $rootFolder -ChildPath "$year"
        New-Item -ItemType Directory -Path $yearFolder -Force

        for ($month = 1; $month -le 12; $month++) {
            $daysInMonth = Get-DaysInMonth -year $year -month $month
            $monthNumber = "{0:D2}" -f $month
            $monthName = (Get-Culture).DateTimeFormat.GetAbbreviatedMonthName($month)
            $monthFolder = Join-Path -Path $yearFolder -ChildPath "$year-$monthNumber $monthName"
            New-Item -ItemType Directory -Path $monthFolder -Force

            # Loop through business days
            for ($day = 1; $day -le $daysInMonth; $day++) {
                $date = Get-Date "$year-$monthNumber-$day"
                $weekday = $date.DayOfWeek

                # Check if it's a business day (Monday to Friday)
                if ($weekday -ne 'Saturday' -and $weekday -ne 'Sunday') {
                    $dayNumber = "{0:D2}" -f $day
                    $weekdayName = $weekday.ToString().Substring(0, 3)
                    $businessDayFolder = Join-Path -Path $monthFolder -ChildPath "$year-$monthNumber-$dayNumber $weekdayName"
                    New-Item -ItemType Directory -Path $businessDayFolder -Force
                }
            }
        }
    }
}

# Specify the root folder and the range of years
$rootFolder = "Annual"
$startYear = 2024
$endYear = 2029

# Call the function to create the folder structure
Create-FolderStructure -rootFolder $rootFolder -startYear $startYear -endYear $endYear
