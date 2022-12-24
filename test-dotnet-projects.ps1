$totalTests = 0
$testsPassed = 0
$testsFailed = 0
$failedProjects = 0
$unableToBuild = 0
$numProjects = 0

# Identify all CSPROJ files in the solution and scan for security
$files = Get-ChildItem -Path "." -Recurse -Filter "*.test.csproj"
foreach ($file in $files) {

    # Compile and test the project using VSTest console
    Write-Output "Building test project $($file.FullName)..."
    $build = & "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" $file.FullName 2>&1
    if ($build -like "*Build succeeded.*") {
        Write-Output "OK"
    } else {
        Write-Output "ERROR: $($file.FullName) cannot be built."
        $unableToBuild++
        continue
    }

    # Find this particular DLL file somewhere within its build folder
    $dlls = Get-ChildItem -Path "$($file.Directory)/bin" -Recurse -Filter "*.test.dll"
    foreach ($dll in $dlls) {
        Write-Output "Running tests for $($dll.FullName)..."
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
    if ($allresults -like "*Test Run Failed.*") {
        Write-Output "ERROR: $($file.FullName) had $($failedThisProject) failing and $($passedThisProject) passing tests."
    } elseif ($allresults -like "*Test Run Passed.*") {
        Write-Output "OK: $($file.FullName) had $($failedThisProject) failing and $($passedThisProject) passing tests."
    } elseif ($allresults -like "*Test Run Successful.*") {
        Write-Output "OK: $($file.FullName) had $($failedThisProject) failing and $($passedThisProject) passing tests."
    } else {
        Write-Output "Unknown test results for $($file.FullName)"
        Write-Output $allresults
        return
    }
}

# Print summary
Write-Output "*******************************************************"
Write-Output "Checked $($numProjects) projects."
Write-Output "Found $($totalTests) tests with $($testsPassed) passing and $($testsFailed) failing."
if ($failedProjects -gt 0) {
    Write-Output "Found $($failedProjects) projects with failing tests"
}
if ($brokenProjects -gt 0) {
    Write-Output "Found $($brokenProjects) projects that could not be restored / built"
}
