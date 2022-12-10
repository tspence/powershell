$errors = 0
$warnings = 0
$broken = 0
$numSolutions = 0

# Identify all solution files in the solution
$files = Get-ChildItem -Path "." -Recurse -Filter "*.sln"
foreach ($file in $files) {

    # Build this solution using warnings-as-errors
    Write-Output "Building solution $($file.FullName)..."
    $build = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" /warnaserror $file.FullName 2>&1

    # Scan for something obvious
    # To view the entire output: Write-Output "Capture group: $($match.Matches.groups[0].value)"
    $simpleResults = select-string "(?m)     (\d+) Warning\(s\)     (\d+) Error\(s\)" -InputObject $build
    foreach ($match in $simpleResults) {
        $numErrors = $match.Matches.groups[2].value
        $numWarnings = $match.Matches.groups[1].value
        if ($numErrors -gt 0) {
            Write-Output "Found $($match.Matches.groups[1].value) warnings and $($match.Matches.groups[2].value) errors in $($file.FullName)"
        } elseif ($numWarnings -gt 0) {
            Write-Output "Found $($match.Matches.groups[1].value) warnings and $($match.Matches.groups[2].value) errors in $($file.FullName)"
        }
        $warnings += $numWarnings
        $errors += $numErrors
    }

    # What type of response did we get?
    if ($build -like "*Build succeeded.*") {
        Write-Output "OK"
    } elseif ($build -like "*Build FAILED.*") {
        Write-Output "ERROR: Unable to build $($file.FullName)"
        $broken++
    } else {
        Write-Output "Unknown build result for $($file.FullName)"
        Write-Output $build
    }
    $numSolutions++
}

# Print summary
Write-Output "*******************************************************"
Write-Output "Compiled $($numSolutions) solutions."
if ($errors -gt 0) {
    Write-Error "Found $($errors) errors in solutions"
}
if ($warnings -gt 0) {
    Write-Warning "Found $($warnings) warnings in solutions"
}
if ($broken -gt 0) {
    Write-Error "Found $($broken) broken solutions"
}
