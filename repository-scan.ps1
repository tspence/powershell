###############################################################################
##
## Repository Scanner
##  - Prints out vulnerabilities and issues found with NodeJS, Yarn, and DotNet
##    projects
##  - Identifies all high and critical security vulnerabilities
##  - Attempts to execute tests and reports results
##  - Highlight issues that can prevent builds
##
##  Syntax:
##    ./repository-scan.ps1 [all | csproj | nodejs | sln | test | webforms]
##  
##  csproj   - Check DotNet projects for vulnerabilities
##  nodejs   - Check Yarn and NPM projects for vulnerabilities
##  sln      - Check DotNet solutions
##  test     - Check DotNet test projects
##  webforms - Check for outdated WebForms ASPX pages 
##
###############################################################################

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
$numWarningSolutions = 0
$numWebFormsPages = 0
$appType = ''
$auditData = {}

# Determine scan type
$scanType = $args[0]
if (($scanType -eq "") -or ($null -eq $scanType)) {
    $scanType = "all"
}
Write-Output "Scan type: $($scanType)"

# Figure out the filename for today's output
$now = Get-Date
$today = Get-Date -format yyyy-MM-dd
$folder = ".." | Resolve-Path
$outFileName = Join-Path -Path $folder -ChildPath "security.$($today).txt"
$csvFileName = Join-Path -Path $folder -ChildPath "security.$($today).csv"

# Clear out files and write headers
Write-Output "Repository scan for $($scanType) began on $($now)." | Tee-Object -FilePath $outFileName
Write-Output "Type,Location,Build Status,Vulnerabilities,Warnings,Errors,Tests Failed,Tests Passed" | Out-File -FilePath $csvFileName

# Identify all NPM projects, who should each be identified by a file named package.json
if (($scanType -eq "all") -or ($scanType -eq "nodejs")) {
    $files = Get-ChildItem -Path "." -Recurse -Filter "package.json"
    foreach ($file in $files) {

        # Is this package.json file within a larger package.json project?
        $isChildOfLargerProject = 0
        $testPathString = "$($file.Directory)"
        if ($testPathString -like "*/node_modules/*") {
            continue
        }
        while ($null -ne $testPathString) {
            $testPathString = "$($testPathString)/.."
            $pathExists = Test-Path -Path $testPathString -PathType container
            if (-not ($pathExists)) {
                break
            }
            $testPathString = Convert-Path $testPathString
            if ($testPathString.Length -lt 4) {
                break
            }
            $exists = Test-Path -Path "$($testPathString)/package.json" -PathType leaf
            if ($exists) {
                $isChildOfLargerProject = 1
                break
            }
        }

        # Only test this if it is a standalone project
        if ($isChildOfLargerProject -eq 0) {

            # Check whether this is yarn or npm
            $isYarn = Test-Path -Path "$($file.Directory)\yarn.lock" -PathType leaf
            Push-Location $file.Directory
            if ($isYarn) {
                $npmInstall = & yarn install -f 2>&1
            } else {
                $npmInstall = & npm install -f 2>&1
            }
            Pop-Location

            # Check for projects that can't run npm install
            $numProjects++
            if ($npmInstall -like "*npm ERR!*") {
                Write-Output "Unable to run npm install on $($file.Directory)." | Tee-Object -Append -FilePath $outFileName
                Write-Output $npmInstall
                return
                $unableToBuild++
                Write-Output "NodeJS,$($file.Directory),DOES NOT COMPILE,n/a,0,0,0,0" | Out-File -Append -FilePath $csvFileName
            } else {
                # Okay, this project can build, we should be able to do an npm audit
                Push-Location $file.Directory
                if ($isYarn) {
                    $npmAudit = & yarn audit --json | ConvertFrom-Json
                    $appType = "NodeJS+Yarn"
                    $auditData = $npmAudit.data
                } else {
                    $npmAudit = & npm audit --json | ConvertFrom-Json
                    $appType = "NodeJS"
                    $auditData = $npmaudit.metadata
                }

                # Figure out relevant information about dependency chains
                $packageJson = Get-Content $file | ConvertFrom-Json
                $dependencyNames = $packageJson.dependencies.PSObject.Properties.Name
                $devDependencyNames = $packageJson.devDependencies.PSObject.Properties.Name

                # Print out all high and critical vulnerabilities
                foreach ($item in $npmAudit.vulnerabilities.PSObject.Properties) {
                    if (($item.Value.severity -eq 'high') -or ($item.Value.severity -eq 'critical')) {
                        if ($dependencyNames -contains $item.Name) { 
                            Write-Output "Project $($file.Directory) package $($item.Name) is a direct dependency vulnerability [$($item.Value.severity)]" | Tee-Object -Append -FilePath $outFileName
                        } elseif ($devDependencyNames -contains $item.Name) { 
                            Write-Output "Project $($file.Directory) package $($item.Name) is a development-only vulnerability [$($item.Value.severity)]" | Tee-Object -Append -FilePath $outFileName
                        } else {
                            Write-Output "Project $($file.Directory) package $($item.Name) is an indirect vulnerability [$($item.Value.severity)]" | Tee-Object -Append -FilePath $outFileName
                        }
                    }
                }

                $vulnerabilities = $auditData.vulnerabilities.high + $auditData.vulnerabilities.critical
                Write-Output "Found $($auditData.vulnerabilities.critical) critical / $($auditData.vulnerabilities.high) high vulnerabilities in $($file.Directory)." | Tee-Object -Append -FilePath $outFileName
                Write-Output "$($appType),$($file.Directory),OK,$($vulnerabilities),0,0,0,0" | Out-File -Append -FilePath $csvFileName
                Pop-Location
                $totalVulnerabilities += $vulnerabilities
                $projectsWithVulnerabilities++
            }
        }
    }
}

# Identify all solution files in the solution
if (($scanType -eq "all") -or ($scanType -eq "sln")) {
    $files = Get-ChildItem -Path "." -Recurse -Filter "*.sln"
    foreach ($file in $files) {
        if ($file.FullName -like "*\node_modules\*") {
            # It's a solution within a node module - ignore it
        } else {

            # Build this solution using warnings-as-errors
            $build = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" $file.FullName /t:Clean,Build 2>&1

            # Scan for warnings
            $simpleResults = select-string "\s(\d+) Warning\(s\)" -InputObject $build
            $warningsThisSolution = 0
            foreach ($match in $simpleResults) {
                $numWarnings = $match.Matches.groups[1].value
                $totalWarnings += $numWarnings
                $warningsThisSolution += $numWarnings
            }

            # To view the entire output: Write-Output "Capture group: $($match.Matches.groups[0].value)"
            $simpleResults = select-string "\s(\d+) Error\(s\)" -InputObject $build
            $errorsThisSolution = 0
            foreach ($match in $simpleResults) {
                $numErrors = $match.Matches.groups[1].value
                $totalErrors += $numErrors
                $errorsThisSolution += $numErrors
            }

            # What type of response did we get?
            $numProjects++
            if ($build -like "*Build FAILED.*") {
                Write-Output "ERROR: Unable to build $($file.FullName) because build failed" | Tee-Object -Append -FilePath $outFileName
                $unableToBuild++
                Write-Output "Solution,$($file.FullName),OK,0,$($warningsThisSolution),$($errorsThisSolution),0,0" | Out-File -Append -FilePath $csvFileName
            } elseif ($errorsThisSolution -gt 0) {
                Write-Output "ERROR: Unable to build $($file.FullName) due to errors" | Tee-Object -Append -FilePath $outFileName
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
}

# Identify all CSPROJ files in the solution and scan for security
if (($scanType -eq "all") -or ($scanType -eq "csproj")) {
    $files = Get-ChildItem -Path "." -Recurse -Filter "*.csproj"
    foreach ($file in $files) {
        $numProjects++

        # Execute dotnet vulnerability scan and capture output
        $packagelist = & dotnet list $file.FullName package --vulnerable --format json 
        try {
            $packages = $packagelist | ConvertFrom-Json
            $vulnerabilitiesThisProject = 0
            foreach ($package in $packages.projects.frameworks.topLevelPackages) { 
                foreach ($vulnerability in $package.vulnerabilities) {
                    Write-Output "Project $($file.FullName) package $($package.id) is a vulnerability [$($vulnerability.severity)]" | Tee-Object -Append -FilePath $outFileName
                    $vulnerabilitiesThisProject++
                    $totalVulnerabilities++
                }
            }
            Write-Output "DotNet,$($file.FullName),OK,$($vulnerabilitiesThisProject),0,0,0,0" | Out-File -Append -FilePath $csvFileName

        } catch {
            
            # Regular dotnet package list in JSON didn't work - check text of response
            if ($packagelist -like "*has no vulnerable packages given the current sources*") {
                Write-Output "DotNet,$($file.FullName),OK,0,0,0,0,0" | Out-File -Append -FilePath $csvFileName
            } elseif ($packagelist -like "*uses package.config for NuGet packages*") {
                Write-Output "WARNING: $($file.FullName) uses package.config or an extremely old version of VS tools. Please upgrade it to enable security scans." | Tee-Object -Append -FilePath $outFileName
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
            } else {
                Write-Output "Unknown vulnerability scan for $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
                $unableToBuild++
                Write-Output "DotNet,$($file.FullName),UNKNOWN,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
            }
        }
    }
}

# Identify all CSPROJ files with test in their name and try to run them as VS Console Tests
if (($scanType -eq "all") -or ($scanType -eq "test")) {
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
        $passedThisProject = 0
        $failedThisProject = 0
        $numDlls = 0
        foreach ($dll in $dlls) {
            $testRunner = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe" $dll.FullName 2>&1

            # Check for passed tests first
            $simpleResults = select-string "(?m)\s+Passed: (\d+)" -InputObject $testRunner
            foreach ($match in $simpleResults) {
                $passed = $match.Matches.groups[1].value
                $totalTests += $passed
                $testsPassed += $passed
                $passedThisProject += $passed
            }
            
            # Check for passed only
            $simpleResults = select-string "(?m)\s+Failed: (\d+)" -InputObject $testRunner
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
            $numDlls++
        }

        # Check type of response
        if ($failedThisProject -gt 0) {
            Write-Output "Project $($dll.FullName) has $($numDlls) test DLLs with $($failedThisProject) failing and $($passedThisProject) passing tests." | Tee-Object -Append -FilePath $outFileName
            Write-Output "Test,$($file.FullName),OK,0,0,0,$($failedThisProject),$($passedThisProject)" | Out-File -Append -FilePath $csvFileName
        } elseif ($passedThisProject -gt 0) {
            Write-Output "Test,$($file.FullName),OK,0,0,0,$($failedThisProject),$($passedThisProject)" | Out-File -Append -FilePath $csvFileName
        } else {
            Write-Output "Unknown test results for $($file.FullName)" | Tee-Object -Append -FilePath $outFileName
            Write-Output "Test,$($file.FullName),UNKNOWN,n/a,n/a,n/a,n/a,n/a" | Out-File -Append -FilePath $csvFileName
        }
    }
}

# Identify all CSPROJ files with test in their name and try to run them as VS Console Tests
if (($scanType -eq "all") -or ($scanType -eq "webforms")) {
    $files = Get-ChildItem -Path "." -Recurse -Filter "*.aspx"
    $numWebFormsPages = $files.Length
}

# Print summary to console and to file
$now = Get-Date
Write-Output "Repository scan of type $($scanType) finished $($now)." | Tee-Object -Append -FilePath $outFileName
Write-Output "*******************************************************" | Tee-Object -Append -FilePath $outFileName
Write-Output "Checked $($numProjects) C# and NPM projects." | Tee-Object -Append -FilePath $outFileName
if ($unableToBuild -gt 0) {
    Write-Output "Found $($unableToBuild) projects that could not be built." | Tee-Object -Append -FilePath $outFileName
}
if ($projectsWithVulnerabilities -gt 0) {
    Write-Output "Found $($projectsWithVulnerabilities) projects that contained $($totalVulnerabilities) total security vulnerabilities." | Tee-Object -Append -FilePath $outFileName
}
if ($packageConfig -gt 0) {
    Write-Output "Found $($packageConfig) C# projects using outdated package.config files." | Tee-Object -Append -FilePath $outFileName
}
if ($deprecatedProjects -gt 0) {
    Write-Output "Found $($deprecatedProjects) C# projects using deprecated WebForms or SilverLight." | Tee-Object -Append -FilePath $outFileName
}
if (($totalErrors -gt 0) -or ($totalWarnings -gt 0)) {
    Write-Output "Found $($totalErrors) errors and $($totalWarnings) warnings in C# solutions." | Tee-Object -Append -FilePath $outFileName
}
if ($numWarningSolutions -gt 0) {
    Write-Output "Found $($numWarningSolutions) C# solutions that need fixes before they can use /warnaserror." | Tee-Object -Append -FilePath $outFileName
}
if ($totalTests -gt 0) {
    Write-Output "Found $($totalTests) tests with $($testsPassed) passing and $($testsFailed) failing." | Tee-Object -Append -FilePath $outFileName
}
if ($numWebFormsPages -gt 0) {
    Write-Output "Found $($numWebFormsPages) WebForms pages that need to be retired." | Tee-Object -Append -FilePath $outFileName
}