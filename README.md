# PowerShell devops scripts
This repository contains useful PowerShell scripts for devops.

## Security and vulnerability detection
* [security-dotnet-projects.ps1](https://raw.githubusercontent.com/tspence/powershell/main/security-dotnet-projects.ps1) - [Scan all CSPROJ projects](https://medium.com/codex/powershell-scanning-for-dotnet-projects-and-solutions-26d013d7579a) in a folder for out-of-date compiler tools or package security vulnerabilities.
* [security-dotnet-solutions.ps1](https://raw.githubusercontent.com/tspence/powershell/main/security-dotnet-solutions.ps1) - [Scan all SLN solutions](https://medium.com/codex/powershell-scanning-for-dotnet-projects-and-solutions-26d013d7579a) in a folder for deprecated technologies, compiler warnings, or build errors.
* [test-dotnet-projects.ps1](https://raw.githubusercontent.com/tspence/powershell/main/test-dotnet-projects.ps1) - Find and build and test all projects matching `*.test.csproj` and report on passing and failing tests.

## Azure devops scripts
* [azure-devops-repository-size.ps1](https://raw.githubusercontent.com/tspence/powershell/main/azure-devops-repository-size.ps1) - Clone all repositories from Azure Devops and [measure repository size](https://tedspence.com/code-repository-size-with-powershell-4df93e5cdf88).
* [azure-create-task-for-file.ps1](https://raw.githubusercontent.com/tspence/powershell/main/azure-create-task-for-file.ps1) - Create an [Azure Devops ticket](https://medium.com/codex/create-azure-tasks-with-powershell-e1b287bb9153) for each file in a folder.

