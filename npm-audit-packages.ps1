$totalVulnerabilities = 0
$testsPassed = 0
$testsFailed = 0
$successProjects = 0
$failedProjects = 0
$brokenProjects = 0
$numProjects = 0

# Identify all NPM projects, who should each be identified by a file named package.json
$files = Get-ChildItem -Path "." -Recurse -Filter "package.json"
foreach ($file in $files) {

    # Is this a sub-project within an existing project, or a project on its own?
    if ($file.FullName -like "*node_modules*") {
        # Write-Output "This appears to be a subproject: $($file.FullName)"
    } else {
        Write-Output "Running npm install on project $($file.FullName)..."
        Write-Output "Changing directory to $($file.Directory)."
        Push-Location $file.Directory
        Write-Output "Running npm install in this folder."
        $npmInstall = & npm install 2>&1
        Write-Output "Finished with npm install."
        Pop-Location

        # Scan for vulnerability detection
        $found = 0
        $simpleResults = select-string "(?m)found (\d+) (high severity vulnerabilities|high severity vulnerability|vulnerabilities|vulnerability)" -InputObject $npmInstall
        foreach ($match in $simpleResults) {
            $vulnerabilities = $match.Matches.groups[1].value
            if ($failed -gt 0) {
                Write-Output "ERROR: NPM project $($file.FullName) has $($vulnerabilities) audit vulnerabilities"
            }
            $totalVulnerabilities += $vulnerabilities
            $found = 1
        }

        # Check for audit problems
        if ($found -gt 0) {
            Write-Output "Found $($vulnerabilities) vulnerabilities in $($file.Directory)"
        } elseif ($npmInstall -like "*npm ERR!*") {
            Write-Output "Unable to run npm install on $($file.Directory)."
            $brokenProjects++
        } else {
            Write-Output "No vulnerabilities found?"
            Write-Output $npmInstall
        }

        $numProjects++
    }
}

# Print summary
Write-Output "*******************************************************"
Write-Output "Checked $($numProjects) NPM projects."
Write-Output "Found $($brokenProjects) projects that could not be built."
Write-Output "Found $($totalVulnerabilities) total security vulnerabilities."

