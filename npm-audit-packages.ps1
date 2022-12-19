$totalVulnerabilities = 0
$testsPassed = 0
$testsFailed = 0
$successProjects = 0
$failedProjects = 0
$brokenProjects = 0
$numProjects = 0

# Figure out the filename for today's output
$now = Get-Date
$today = Get-Date -format yyyy-MM-dd
$outFileName = "..\node.$($today).txt"
$csvFileName = "..\node.$($today).csv"

# Clear out files and write headers
Write-Output "Security scan began on $($now)." | Out-File -FilePath $outFileName
Write-Output "Folder,Build Status,Vulnerabilities" | Out-File -FilePath $csvFileName

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
            Write-Output "Found $($vulnerabilities) vulnerabilities in $($file.Directory)" | Out-File -Append -FilePath $outFileName
            Write-Output "$($file.Directory),OK,$($vulnerabilities)" | Out-File -Append -FilePath $csvFileName
        } elseif ($npmInstall -like "*npm ERR!*") {
            Write-Output "Unable to run npm install on $($file.Directory)."
            Write-Output "Unable to run npm install on $($file.Directory)." | Out-File -Append -FilePath $outFileName
            $brokenProjects++
            Write-Output "$($file.Directory),DOES NOT COMPILE,n/a" | Out-File -Append -FilePath $csvFileName
        } else {
            Write-Output "Unable to parse npm install output for $($file.Directory)."
            Write-Output "Unable to parse npm install output for $($file.Directory)." | Out-File -Append -FilePath $outFileName
            Write-Output $npmInstall
            Write-Output "$($file.Directory),UNKNOWN,n/a" | Out-File -Append -FilePath $csvFileName
        }

        # Write basic facts to our file

        $numProjects++
    }
}

# Print summary
Write-Output "*******************************************************"
Write-Output "Checked $($numProjects) NPM projects."
Write-Output "Found $($brokenProjects) projects that could not be built."
Write-Output "Found $($totalVulnerabilities) total security vulnerabilities."
Write-Output "*******************************************************" | Out-File -Append -FilePath $outFileName
Write-Output "Checked $($numProjects) NPM projects." | Out-File -Append -FilePath $outFileName
Write-Output "Found $($brokenProjects) projects that could not be built." | Out-File -Append -FilePath $outFileName
Write-Output "Found $($totalVulnerabilities) total security vulnerabilities." | Out-File -Append -FilePath $outFileName

