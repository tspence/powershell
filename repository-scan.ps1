$totalVulnerabilities = 0
$testsPassed = 0
$testsFailed = 0
$numProjects = 0
$projectsWithVulnerabilities = 0
$unableToBuild = 0
$packageConfig = 0
$deprecatedProjects = 0
$totalErrors = 0
$totalWarnings = 0
$totalTests = 0

# Figure out the filename for today's output
$now = Get-Date
$today = Get-Date -format yyyy-MM-dd
$folder = ".." | Resolve-Path
$outFileName = Join-Path -Path $folder -ChildPath "security.$($today).txt"
$csvFileName = Join-Path -Path $folder -ChildPath "security.$($today).csv"

# Clear out files and write headers
Write-Output "Repository scan began on $($now)." | Tee-Object -FilePath $outFileName
Write-Output "Type,Location,Build Status,Vulnerabilities,Warnings,Errors,Tests Failed,Tests Passed" | Out-File -FilePath $csvFileName

# Identify all NPM projects, who should each be identified by a file named package.json
$files = Get-ChildItem -Path "." -Recurse -Filter "package.json"
foreach ($file in $files) {

    # Is this package.json file within a larger package.json project?
    $isChildOfLargerProject = 0
    $testPath = $file.Directory
    while (1 -eq 1) {
        $testPath = Join-Path -Path $testPath -ChildPath ".." | Resolve-Path
        $testPathString = Convert-Path $testPath
        if ($testPathString.Length -lt 4) {
            break
        }
        $testPackageFile = Join-Path -Path $testPath -ChildPath "package.json"
        $exists = Test-Path -Path $testPackageFile -PathType leaf
        if ($exists) {
            $isChildOfLargerProject = 1
            break
        }
    }

    # Only test this if it is a standalone project
    if ($isChildOfLargerProject -eq 0) {
        Push-Location $file.Directory
        $npmInstall = & npm clean-install 2>&1
        Pop-Location

        # Check for projects that can't run npm install
        $numProjects++
        if ($npmInstall -like "*npm ERR!*") {
            Write-Output "Unable to run npm install on $($file.Directory)." | Tee-Object -Append -FilePath $outFileName
            $unableToBuild++
            Write-Output "NodeJS,$($file.Directory),DOES NOT COMPILE,n/a,0,0,0,0" | Out-File -Append -FilePath $csvFileName
        } else {
            # Okay, this project can build, we should be able to do an npm audit
            Push-Location $file.Directory
            $npmAudit = & npm audit --json | ConvertFrom-Json
            Pop-Location
            $vulnerabilities = $npmAudit.metadata.vulnerabilities.moderate + $npmAudit.metadata.vulnerabilities.high + $npmAudit.metadata.vulnerabilities.critical
            Write-Output "Found $($npmAudit.metadata.vulnerabilities.critical) critical / $($npmAudit.metadata.vulnerabilities.high) high / $($npmAudit.metadata.vulnerabilities.moderate) moderate vulnerabilities in $($file.Directory)." | Tee-Object -Append -FilePath $outFileName
            $totalVulnerabilities += $vulnerabilities
            $projectsWithVulnerabilities++
            Write-Output "NodeJS,$($file.Directory),OK,$($vulnerabilities),0,0,0,0" | Out-File -Append -FilePath $csvFileName
        }
    }
}
# Identify all solution files in the solution
$files = Get-ChildItem -Path "." -Recurse -Filter "*.sln"
foreach ($file in $files) {
    if ($file.FullName -like "*\node_modules\*") {
        # It's a solution within a node module - ignore it
    } else {

        # Build this solution using warnings-as-errors
        $build = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" $file.FullName 2>&1

        # Scan for something obvious
        # To view the entire output: Write-Output "Capture group: $($match.Matches.groups[0].value)"
        $simpleResults = select-string "(?m)     (\d+) Warning\(s\)     (\d+) Error\(s\)" -InputObject $build
        $warningsThisSolution = 0
        $errorsThisSolution = 0
        foreach ($match in $simpleResults) {
            $numErrors = $match.Matches.groups[2].value
            $numWarnings = $match.Matches.groups[1].value
            if ($numErrors -gt 0) {
                Write-Output "Found $($match.Matches.groups[1].value) warnings and $($match.Matches.groups[2].value) errors in $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            } elseif ($numWarnings -gt 0) {
                Write-Output "Found $($match.Matches.groups[1].value) warnings and $($match.Matches.groups[2].value) errors in $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            }
            $totalWarnings += $numWarnings
            $totalErrors += $numErrors
            $warningsThisSolution += $numWarnings
            $errorsThisSolution += $numErrors
        }

        # What type of response did we get?
        $numProjects++
        if ($build -like "*Build FAILED.*") {
            Write-Output "ERROR: Unable to build $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            $unableToBuild++
            Write-Output "Solution,$($file.FullName),OK,0,$($warningsThisSolution),$($errorsThisSolution),0,0" | Out-File -Append -FilePath $csvFileName
        } elseif ($errorsThisSolution -gt 0) {
            Write-Output "ERROR: Unable to build $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            $unableToBuild++
            Write-Output "Solution,$($file.FullName),OK,0,$($warningsThisSolution),$($errorsThisSolution),0,0" | Out-File -Append -FilePath $csvFileName
        } elseif ($warningsThisSolution -gt 0) {
            Write-Output "WARNING: The solution $($file.FullName) needs fixes before we can enable /warnaserror" | Tee-Object -Append -FilePath $outFileName
            $numWarningSolutions++
            Write-Output "Solution,$($file.FullName),OK,0,$($warningsThisSolution),$($errorsThisSolution),0,0" | Out-File -Append -FilePath $csvFileName
        } elseif ($build -like "*Build succeeded.*") {
            Write-Output "Solution,$($file.FullName),OK,0,0,0,0,0" | Out-File -Append -FilePath $csvFileName
        } else {
            Write-Output "Unknown build result for $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            $unableToBuild++
            Write-Output "Solution,$($file.FullName),UNKNOWN,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
        }
    }
}


# Identify all CSPROJ files in the solution and scan for security
$files = Get-ChildItem -Path "." -Recurse -Filter "*.csproj"
foreach ($file in $files) {

    # Execute dotnet vulnerability scan and capture output
    $packagelist = & dotnet list $file.FullName package --vulnerable 2>&1

    # Check type of response
    $numProjects++
    if ($packagelist -like "*has no vulnerable packages given the current sources*") {
        Write-Output "DotNet,$($file.FullName),OK,0,0,0,0,0" | Out-File -Append -FilePath $csvFileName
    } elseif ($packagelist -like "*uses package.config for NuGet packages*") {
        Write-Output "WARNING: $($file.FullName) uses package.config." | Tee-Object -Append -FilePath $outFileName
        $packageConfig++
        Write-Output "DotNet,$($file.FullName),USES PACKAGE.CONFIG,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    } elseif ($packagelist -like "*Unable to read a package reference from the project*") {
        Write-Output "ERROR: $($file.FullName) cannot be verified because it cannot be restored/built." | Tee-Object -Append -FilePath $outFileName
        $unableToBuild++
        Write-Output "DotNet,$($file.FullName),UNABLE TO RESTORE,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    } elseif ($packagelist -like "*Microsoft.WebApplication.targets"" was not found*") {
        Write-Output "ERROR: $($file.FullName) cannot be built because it is an out of support WebForms app." | Tee-Object -Append -FilePath $outFileName
        $deprecatedProjects++
        Write-Output "DotNet,$($file.FullName),WEBFORMS,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    } elseif ($packagelist -like "*Microsoft.Silverlight.CSharp.targets"" was not found*") {
        Write-Output "ERROR: $($file.FullName) cannot be built because it is an out of support Silverlight app." | Tee-Object -Append -FilePath $outFileName
        $deprecatedProjects++
        Write-Output "DotNet,$($file.FullName),SILVERLIGHT,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    } elseif ($packagelist -like "*has the following vulnerable packages*") {
        Write-Output "ERROR: $($file.FullName) has security vulnerabilities." | Tee-Object -Append -FilePath $outFileName
        $projectsWithVulnerabilities++
        Write-Output "DotNet,$($file.FullName),OK,1,0,0,0,0" | Out-File -Append -FilePath $csvFileName
    } else {
        Write-Output "Unknown vulnerability scan for $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
        $unableToBuild++
        Write-Output "DotNet,$($file.FullName),UNKNOWN,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    }
}

# Identify all CSPROJ files with test in their name and try to run them as VS Console Tests
$files = Get-ChildItem -Path "." -Recurse -Filter "*.test.csproj"
foreach ($file in $files) {

    # Compile and test the project using VSTest console
    $build = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" $file.FullName 2>&1
    if ($build -like "*Build succeeded.*") {
        # No action, all is well
    } else {
        Write-Output "ERROR: $($file.FullName) cannot be built." | Tee-Object -Append -FilePath $outFileName
        $unableToBuild++
        Write-Output "Test,$($file.FullName),UNABLE TO BUILD,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
        continue
    }

    # Find this particular DLL file somewhere within its build folder
    $dlls = Get-ChildItem -Path "$($file.Directory)/bin" -Recurse -Filter "*.test.dll"
    foreach ($dll in $dlls) {
        $testRunner = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe" $dll.FullName 2>&1

        # Check for passed tests first
        $simpleResults = select-string "(?m)\s+Passed: (\d+)" -InputObject $testRunner
        $passedThisProject = 0
        foreach ($match in $simpleResults) {
            $passed = $match.Matches.groups[1].value
            $totalTests += $passed
            $testsPassed += $passed
            $passedThisProject += $passed
        }
        
        # Check for passed only
        $simpleResults = select-string "(?m)\s+Failed: (\d+)" -InputObject $testRunner
        $failedThisProject = 0
        foreach ($match in $simpleResults) {
            $failed = $match.Matches.groups[1].value
            if ($failed -gt 0) {
                Write-Output "ERROR: Test project $($dll.FullName) has $($failed) failing tests."
            }
            $totalTests += $failed
            $testsFailed += $failed
            $failedThisProject += $failed
        }

        # Accumulate test log results for failure scanning
        $allresults = $allresults + $testRunner
    }

    # Check type of response
    if ($failedThisProject -gt 0) {
        Write-Output "ERROR: $($file.FullName) failed some tests." | Tee-Object -Append -FilePath $outFileName
        Write-Output "Test,$($file.FullName),OK,0,0,0,$($failedThisProject),$($passedThisProject)" | Out-File -Append -FilePath $csvFileName
    } elseif ($passedThisProject -gt 0) {
        Write-Output "Test,$($file.FullName),OK,0,0,0,$($failedThisProject),$($passedThisProject)" | Out-File -Append -FilePath $csvFileName
    } else {
        Write-Output "Unknown test results for $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
        Write-Output "Test,$($file.FullName),UNKNOWN,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
    }
}

# Print summary to console and to file
$now = Get-Date
Write-Output "Repository scan finished $($now)." | Tee-Object -Append -FilePath $outFileName
Write-Output "*******************************************************" | Tee-Object -Append -FilePath $outFileName
Write-Output "Checked $($numProjects) C# and NPM projects." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($unableToBuild) projects that could not be built." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($projectsWithVulnerabilities) projects that contained $($totalVulnerabilities) total security vulnerabilities." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($packageConfig) C# projects using outdated package.config files." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($deprecatedProjects) C# projects using deprecated WebForms or SilverLight." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($totalErrors) errors and $($totalWarnings) warnings in C# solutions." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($numWarningSolutions) C# solutions that need fixes before they can use /warnaserror." | Tee-Object -Append -FilePath $outFileName
Write-Output "Found $($totalTests) tests with $($testsPassed) passing and $($testsFailed) failing." | Tee-Object -Append -FilePath $outFileName
