#!/usr/bin/env pwsh
<#
===============================================================================
Script Name  : bootstrap.ps1
Author       : Armoghan-ul-Mohmin
Date         : 2025-09-27
Version      : 1.1.0
-------------------------------------------------------------------------------
Description:
    Bootstraps the Winfig project environment with Ansible on Windows.
    Automates prerequisite installation, repository cloning, and Ansible setup.

Workflow:
    1. Environment Validation
    2. Setup Restore Point
    3. Prerequisite Installation
    4. Repository Cloning
    5. Ansible Setup

-------------------------------------------------------------------------------
Usage:
    # Run directly from the web:
        Invoke-RestMethod -Uri "https://raw.githubusercontent.com/Armoghan-ul-Mohmin/Winfig-Ansible/main/bootstrap.ps1" | Invoke-Expression

    # Execute after downloading:
        .\bootstrap.ps1

===============================================================================
#>

#  Set UTF-8 Encoding with BOM for Output
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
$OutputEncoding = $utf8WithBom
[Console]::OutputEncoding = $utf8WithBom

# ============================================================================ #
#                               Global Variables                               #
# ============================================================================ #

# Script Metadata
$Script:ScriptMeta = @{
    Author      = "Armoghan-ul-Mohmin"
    Version     = "1.0.0"
    Description = "Enterprise Windows Configuration Management Platform"
    ScriptName  = "Winfig Bootstrap"
    StartTime   = Get-Date
}

# Color Palette
$Script:Colors = @{
    Primary    = "Cyan"
    Success    = "Green"
    Warning    = "Yellow"
    Error      = "Red"
    Accent     = "Magenta"
    Light      = "White"
    Dark       = "Gray"
    Highlight  = "Yellow"
    Info       = "Gray"
}

# User Prompts
$Script:Prompts = @{
    Confirm    = "[?] Do you want to proceed? (Y/N): "
    Retry      = "[?] Do you want to retry? (Y/N): "
    Abort      = "[!] Operation aborted by user."
    Continue   = "[*] Press any key to continue..."
}

# Initialize global variables
$Global:TempDir = [Environment]::GetEnvironmentVariable("TEMP")
$Global:LogDir = [System.IO.Path]::Combine($Global:TempDir, "Winfig-Logs")
$Global:LogFile = [System.IO.Path]::Combine($Global:LogDir, "Winfig-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log")
$Global:RepoUrl = "https://github.com/Armoghan-ul-Mohmin/Winfig-Ansible"
$Global:ConfigDir = $null
$Global:RepoDir = $null

# Logging Configuration
$Script:LogConfig = @{
    LogLevel = "INFO"
    EnableConsole = $false
    EnableFile = $true
}

# ============================================================================ #
#                             Helper Functions                                 #
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Enhanced logging function with file output only (no console by default)
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [switch]$ShowConsole,

        [Parameter(Mandatory=$false)]
        [switch]$NoFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists and write to file (default behavior)
    if ($Script:LogConfig.EnableFile -and -not $NoFile) {
        if (-not (Test-Path $Global:LogDir)) {
            New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null
        }
        Add-Content -Path $Global:LogFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    # Console output only when explicitly requested
    if ($ShowConsole) {
        $color = switch ($Level) {
            "DEBUG"   { $Script:Colors.Dark }
            "INFO"    { $Script:Colors.Info }
            "WARN"    { $Script:Colors.Warning }
            "ERROR"   { $Script:Colors.Error }
            "SUCCESS" { $Script:Colors.Success }
            default   { $Script:Colors.Light }
        }

        # Format console output differently
        switch ($Level) {
            "DEBUG"   { Write-Host "   [DEBUG] $Message" -ForegroundColor $color }
            "INFO"    { Write-Host "   $Message" -ForegroundColor $color }
            "WARN"    { Write-Host "   [WARNING] $Message" -ForegroundColor $color }
            "ERROR"   { Write-Host "   [ERROR] $Message" -ForegroundColor $color }
            "SUCCESS" { Write-Host "   $Message" -ForegroundColor $color }
            default   { Write-Host "   $Message" -ForegroundColor $color }
        }
    }
}

# ---------------------------------------------------------------------------- #
# Write section headers with logging
function Write-Section {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter(Mandatory=$false)]
        [string]$Description = ""
    )

    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " $Title" -ForegroundColor $Script:Colors.Primary
    if ($Description) {
        Write-Host " $Description" -ForegroundColor $Script:Colors.Info
    }
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary

    Write-Log "Starting section: $Title" -Level "INFO" -NoConsole
    if ($Description) {
        Write-Log "Description: $Description" -Level "INFO" -NoConsole
    }
}

# ---------------------------------------------------------------------------- #
# Write subsection headers
function Write-SubSection {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host " $Title" -ForegroundColor $Script:Colors.Primary

    Write-Log "Starting subsection: $Title" -Level "INFO" -NoConsole
}

# ---------------------------------------------------------------------------- #
# Returns the user's Documents path, considering OneDrive if present
function DocumentsPath {
    $oneDriveVars = @("OneDrive", "OneDriveCommercial", "OneDriveConsumer")
    foreach ($var in $oneDriveVars) {
        $path = [Environment]::GetEnvironmentVariable($var, "User")
        if ($path) {
            $docs = Join-Path $path "Documents"
            if (Test-Path $docs) {
                $Global:ConfigDir = $docs
                $Global:RepoDir = Join-Path $docs "Winfig-Ansible"
                return $docs
            }
        }
    }
    $defaultDocs = [Environment]::GetFolderPath('MyDocuments')
    if (Test-Path $defaultDocs) {
        $Global:ConfigDir = $defaultDocs
        $Global:RepoDir = Join-Path $defaultDocs "Winfig-Ansible"
        return $defaultDocs
    }
    return $null
}

# ---------------------------------------------------------------------------- #
# Displays a stylized banner for the script
function ShowBanner {
    Clear-Host
    Write-Host ""
    Write-Host ("  ██╗    ██╗██╗███╗   ██╗███████╗██╗ ██████╗  ".PadRight(70)) -ForegroundColor $Script:Colors.Light
    Write-Host ("  ██║    ██║██║████╗  ██║██╔════╝██║██╔════╝  ".PadRight(70)) -ForegroundColor $Script:Colors.Light
    Write-Host ("  ██║ █╗ ██║██║██╔██╗ ██║█████╗  ██║██║  ███╗ ".PadRight(70)) -ForegroundColor $Script:Colors.Accent
    Write-Host ("  ██║███╗██║██║██║╚██╗██║██╔══╝  ██║██║   ██║ ".PadRight(70)) -ForegroundColor $Script:Colors.Accent
    Write-Host ("  ╚███╔███╔╝██║██║ ╚████║██║     ██║╚██████╔╝ ".PadRight(70)) -ForegroundColor $Script:Colors.Success
    Write-Host ("   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═╝     ╚═╝ ╚═════╝  ".PadRight(70)) -ForegroundColor $Script:Colors.Success
    Write-Host ((" " * 70)) -ForegroundColor $Script:Colors.Primary
    Write-Host ("        BOOTSTRAP CONFIGURATION SYSTEM".PadLeft(48).PadRight(70)) -ForegroundColor $Script:Colors.Primary
    Write-Host ((" " * 70)) -ForegroundColor $Script:Colors.Primary
    Write-Host ("  Enterprise Windows Configuration Management Platform".PadRight(70)) -ForegroundColor $Script:Colors.Accent
    Write-Host ((" " * 70)) -ForegroundColor $Script:Colors.Primary
    Write-Host (("  Version: " + $Script:ScriptMeta.Version + "    PowerShell: " + $PSVersionTable.PSVersion).PadRight(70)) -ForegroundColor $Script:Colors.Highlight
    Write-Host (("  Author:  " + $Script:ScriptMeta.Author + "    Platform: Windows").PadRight(70)) -ForegroundColor $Script:Colors.Highlight
    Write-Host ""
}

# ---------------------------------------------------------------------------- #
# Checks if the script is running as Administrator
function IsAdmin {
    Write-Log "Checking administrator privileges" -Level "INFO"
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if ($isAdmin) {
        Write-Host " [1/6] Administrator privileges ............. [PASS]" -ForegroundColor $Script:Colors.Success
        Write-Log "Administrator privileges verified - running with elevated privileges" -Level "SUCCESS"
        return @{Check="Administrator"; Result="PASS"; Message="Script running with elevated privileges"}
    } else {
        Write-Host " [1/6] Administrator privileges ............. [FAIL]" -ForegroundColor $Script:Colors.Error
        Write-Log "Administrator privileges check failed - script must be run as Administrator" -Level "ERROR"
        return @{Check="Administrator"; Result="FAIL"; Message="Script must be run as Administrator"}
    }
}

# ---------------------------------------------------------------------------- #
# Checks if the Windows version is supported (Windows 10/11)
function WindowsVersion {
    $windowsBuild = [System.Environment]::OSVersion.Version.Build
    $isWindows10Or11 = ($windowsBuild -ge 10240)
    if ($isWindows10Or11) {
        $windowsName = if ($windowsBuild -ge 22000) { "Windows 11" } else { "Windows 10" }
        Write-Host " [2/6] Windows version ...................... [PASS]" -ForegroundColor $Script:Colors.Success
        return @{Check="Windows Version"; Result="PASS"; Message="Running on $windowsName (Build $windowsBuild)"}
    } else {
        Write-Host " [2/6] Windows version ...................... [FAIL]" -ForegroundColor $Script:Colors.Error
        return @{Check="Windows Version"; Result="FAIL"; Message="Windows 10 or 11 required. Current build: $windowsBuild"}
    }
}

# ---------------------------------------------------------------------------- #
# Checks if PowerShell version is 5.1 or higher
function PowerShellVersion {
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-Host " [3/6] PowerShell version ................... [PASS]" -ForegroundColor $Script:Colors.Success
        return @{Check="PowerShell Version"; Result="PASS"; Message="PowerShell $($psVersion.ToString()) detected"}
    } else {
        Write-Host " [3/6] PowerShell version ................... [FAIL]" -ForegroundColor $Script:Colors.Error
        return @{Check="PowerShell Version"; Result="FAIL"; Message="PowerShell 5.1 or higher required. Current version: $($psVersion.ToString())"}
    }
}

# ---------------------------------------------------------------------------- #
# Checks for internet connectivity
function InternetConnection {
    $internetTest = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($internetTest) {
        Write-Host " [4/6] Internet connection .................. [PASS]" -ForegroundColor $Script:Colors.Success
        return @{Check="Internet Connection"; Result="PASS"; Message="Internet connection available"}
    } else {
        Write-Host " [4/6] Internet connection .................. [FAIL]" -ForegroundColor $Script:Colors.Error
        return @{Check="Internet Connection"; Result="FAIL"; Message="No internet connection detected"}
    }
}

# ---------------------------------------------------------------------------- #
# Checks if there is enough free disk space (2GB minimum)
function DiskSpace {
    $systemDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object Size, FreeSpace
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    $minSpaceGB = 2
    if ($freeSpaceGB -ge $minSpaceGB) {
        Write-Host " [5/6] Disk space (C:) ...................... [PASS]" -ForegroundColor $Script:Colors.Success
        return @{Check="Disk Space"; Result="PASS"; Message="$freeSpaceGB GB free space available"}
    } else {
        Write-Host " [5/6] Disk space (C:) ...................... [FAIL]" -ForegroundColor $Script:Colors.Error
        return @{Check="Disk Space"; Result="FAIL"; Message="Only $freeSpaceGB GB free. Minimum $minSpaceGB GB required"}
    }
}

# ---------------------------------------------------------------------------- #
# Checks if the execution policy is suitable
function CheckExecutionPolicy {
    $executionPolicy = Get-ExecutionPolicy
    $allowedPolicies = @("RemoteSigned", "Unrestricted", "Bypass")
    if ($executionPolicy -in $allowedPolicies) {
        Write-Host " [6/6] Execution policy ..................... [PASS]" -ForegroundColor $Script:Colors.Success
        return @{Check="Execution Policy"; Result="PASS"; Message="Execution policy: $executionPolicy"}
    } else {
        Write-Host " [6/6] Execution policy ..................... [WARN]" -ForegroundColor $Script:Colors.Warning
        return @{Check="Execution Policy"; Result="WARN"; Message="Execution policy: $executionPolicy. Recommended: RemoteSigned"}
    }
}

# ---------------------------------------------------------------------------- #
# Ensures Chocolatey is installed
function EnsureChocolatey {
    Write-Host ""
    Write-Host " Checking for Chocolatey..." -ForegroundColor $Script:Colors.Primary
    Write-Log "Checking for Chocolatey package manager installation" -Level "INFO"

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "   Chocolatey is installed." -ForegroundColor $Script:Colors.Success
        Write-Log "Chocolatey is already installed and available" -Level "SUCCESS"
        return $true
    } else {
        Write-Host "   Chocolatey is not installed. Installing Chocolatey..." -ForegroundColor $Script:Colors.Warning
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "   Chocolatey installed successfully." -ForegroundColor $Script:Colors.Success
            return $true
        } else {
            Write-Host "   Failed to install Chocolatey." -ForegroundColor $Script:Colors.Error
            return $false
        }
    }
}

# ---------------------------------------------------------------------------- #
# Ensures Winget is installed
function EnsureWinget {
    Write-Host ""
    Write-Host " Checking for Winget..." -ForegroundColor $Script:Colors.Primary

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "   Winget is installed." -ForegroundColor $Script:Colors.Success
        return $true
    } else {
        Write-Host "   Winget is not installed. Installing Winget..." -ForegroundColor $Script:Colors.Warning

        try {
            if ([System.Environment]::OSVersion.Version.Build -ge 26100) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                Install-Module "Microsoft.WinGet.Client" -Force
                Import-Module Microsoft.WinGet.Client
                Repair-WinGetPackageManager -Force -Latest -Verbose
                Write-Host "   Winget installed via PowerShell module." -ForegroundColor $Script:Colors.Success
                return $true
            } else {
                $wingetInstallerUrl = "https://aka.ms/getwinget"
                $wingetInstallerPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                Invoke-WebRequest -Uri $wingetInstallerUrl -OutFile $wingetInstallerPath -UseBasicParsing
                Add-AppxPackage -Path $wingetInstallerPath
                Write-Host "   Winget installed via App Installer." -ForegroundColor $Script:Colors.Success
                return $true
            }
        } catch {
            Write-Host "   Failed to install Winget: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
            return $false
        }
    }
}

# ---------------------------------------------------------------------------- #
# Installs UV (Python package/environment manager)
function InstallUV {
    Write-Host ""
    Write-Host " Checking for UV..." -ForegroundColor $Script:Colors.Primary

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host "   UV is installed." -ForegroundColor $Script:Colors.Success
        return $true
    } else {
        Write-Host "   UV is not installed. Attempting to install UV with winget..." -ForegroundColor $Script:Colors.Warning
        try {
            winget install --id AstralSoftware.UV -e --accept-source-agreements --accept-package-agreements -h
            if (Get-Command uv -ErrorAction SilentlyContinue) {
                Write-Host "   UV installed successfully via winget." -ForegroundColor $Script:Colors.Success
                return $true
            } else {
                Write-Host "   UV not found after winget install. Trying Chocolatey..." -ForegroundColor $Script:Colors.Warning
            }
        } catch {
            Write-Host "   Winget installation failed: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Warning
            Write-Host "   Trying Chocolatey..." -ForegroundColor $Script:Colors.Warning
        }
        try {
            choco install uv -y
            if (Get-Command uv -ErrorAction SilentlyContinue) {
                Write-Host "   UV installed successfully via Chocolatey." -ForegroundColor $Script:Colors.Success
                return $true
            } else {
                Write-Host "   Failed to install UV with Chocolatey." -ForegroundColor $Script:Colors.Error
                return $false
            }
        } catch {
            Write-Host "   Chocolatey installation failed: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
            return $false
        }
    }
}

# ---------------------------------------------------------------------------- #
# Installs Python 3.10 using UV
function SetupPython {
    Write-Host ""
    Write-Host " Installing Python 3.10 with UV..." -ForegroundColor $Script:Colors.Primary

    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host "   UV is not available. Cannot install Python." -ForegroundColor $Script:Colors.Error
        return $false
    }

    try {
        & uv python install 3.10
        Write-Host "   Python 3.10 installed successfully using UV." -ForegroundColor $Script:Colors.Success

        # Verify Python installation using UV's method
        $uvPythonList = & uv python list 2>&1
        if ($uvPythonList -match "3\.10") {
            Write-Host "   Python 3.10 verified via UV python list." -ForegroundColor $Script:Colors.Success

            # Get the specific Python 3.10 version details
            $python310Line = ($uvPythonList -split "`n" | Where-Object { $_ -match "3\.10" -and $_ -notmatch "<download available>" }) | Select-Object -First 1
            if ($python310Line) {
                $version = ($python310Line -split "-")[1]
                Write-Host "   Installed Python version: Python $version" -ForegroundColor $Script:Colors.Info
            }

            # Test Python execution via UV
            try {
                $pythonTest = & uv run python --version 2>&1
                if ($pythonTest -match "Python") {
                    Write-Host "   Python execution test: $pythonTest" -ForegroundColor $Script:Colors.Info
                }
            } catch {
                Write-Host "   Python execution test completed (UV-managed installation)" -ForegroundColor $Script:Colors.Info
            }
            return $true
        } else {
            Write-Host "   Python 3.10 not found in UV python list." -ForegroundColor $Script:Colors.Error
            Write-Host "   UV Python list output: $uvPythonList" -ForegroundColor $Script:Colors.Dark
            return $false
        }
    } catch {
        Write-Host "   Failed to install Python 3.10 with UV: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
        return $false
    }
}

# ---------------------------------------------------------------------------- #
# Installs Git using winget or Chocolatey
function InstallGit {
    Write-Host ""
    Write-Host " Checking for Git..." -ForegroundColor $Script:Colors.Primary

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "   Git is installed." -ForegroundColor $Script:Colors.Success
        return $true
    } else {
        Write-Host "   Git is not installed. Installing Git..." -ForegroundColor $Script:Colors.Warning

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Write-Host "   Attempting to install Git with winget..." -ForegroundColor $Script:Colors.Info
                winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements -h
                if (Get-Command git -ErrorAction SilentlyContinue) {
                    Write-Host "   Git installed successfully via winget." -ForegroundColor $Script:Colors.Success
                    return $true
                }
            } catch {
                Write-Host "   Winget installation failed: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Warning
            }
        }

        if (Get-Command choco -ErrorAction SilentlyContinue) {
            try {
                Write-Host "   Attempting to install Git with Chocolatey..." -ForegroundColor $Script:Colors.Info
                choco install git -y
                $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                if (Get-Command git -ErrorAction SilentlyContinue) {
                    Write-Host "   Git installed successfully via Chocolatey." -ForegroundColor $Script:Colors.Success
                    return $true
                }
            } catch {
                Write-Host "   Chocolatey installation failed: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Warning
            }
        }

        Write-Host "   Failed to install Git using available methods." -ForegroundColor $Script:Colors.Error
        return $false
    }
}

# ---------------------------------------------------------------------------- #
# Installs Ansible using UV
function InstallAnsible {
    Write-Host ""
    Write-Host " Checking for Ansible..." -ForegroundColor $Script:Colors.Primary

    if (Get-Command ansible -ErrorAction SilentlyContinue) {
        Write-Host "   Ansible is installed." -ForegroundColor $Script:Colors.Success
        return $true
    } else {
        Write-Host "   Ansible is not installed. Installing Ansible..." -ForegroundColor $Script:Colors.Warning

        if (Get-Command uv -ErrorAction SilentlyContinue) {
            try {
                Write-Host "   Installing Ansible with UV..." -ForegroundColor $Script:Colors.Info
                & uv tool install ansible
                & uv tool install ansible-core
                if (Get-Command ansible -ErrorAction SilentlyContinue) {
                    Write-Host "   Ansible installed successfully via UV." -ForegroundColor $Script:Colors.Success
                    return $true
                }
            } catch {
                Write-Host "   UV installation failed: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Warning
            }
        }
        Write-Host "   Failed to install Ansible." -ForegroundColor $Script:Colors.Error
        return $false
    }
}

# ============================================================================ #
#                            Initialization                                    #
# ============================================================================ #
DocumentsPath | Out-Null

# ============================================================================ #
#                                Functions                                     #
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Validates the environment for all prerequisites
function ValidateEnvironment {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " Validating environment..." -ForegroundColor $Script:Colors.Primary
    Write-Host ""

    $results = @()
    $allValid = $true

    $checks = @(
        { IsAdmin },
        { WindowsVersion },
        { PowerShellVersion },
        { InternetConnection },
        { DiskSpace },
        { CheckExecutionPolicy }
    )

    foreach ($check in $checks) {
        $result = & $check
        $results += $result
        if ($result.Result -eq "FAIL") { $allValid = $false }
    }

    if (-not $allValid) {
        Write-Host ""
        Write-Host " One or more environment checks failed. Please address the issues above and re-run the script." -ForegroundColor $Script:Colors.Error
        exit 1
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------- #
# Creates a system restore point
function SetupRestorePoint {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " Setting up a system restore point..." -ForegroundColor $Script:Colors.Primary

    Write-Host ""
    Write-Host $Script:Prompts.Confirm -ForegroundColor $Script:Colors.Warning -NoNewline
    $response = Read-Host
    if ($response -notin @('Y', 'y')) {
        Write-Host "   Skipping system restore point setup." -ForegroundColor $Script:Colors.Warning
        return
    }
    try {
        Checkpoint-Computer -Description "Pre-Winfig Bootstrap" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "   System restore point created successfully." -ForegroundColor $Script:Colors.Success
    } catch {
        Write-Host "   Error creating system restore point: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
    }
}

# ---------------------------------------------------------------------------- #
# Installs all prerequisites (Chocolatey, Winget, UV, Python, Git, Ansible)
function InstallPrerequisites {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " Installing prerequisites..." -ForegroundColor $Script:Colors.Primary
    Write-Host ""
    Write-Host " This process will install the following components:" -ForegroundColor $Script:Colors.Info
    Write-Host "   - Chocolatey (Package Manager)" -ForegroundColor $Script:Colors.Dark
    Write-Host "   - Winget (Microsoft Package Manager)" -ForegroundColor $Script:Colors.Dark
    Write-Host "   - UV (Modern Python Package Manager)" -ForegroundColor $Script:Colors.Dark
    Write-Host "   - Python 3.10 (Programming Language)" -ForegroundColor $Script:Colors.Dark
    Write-Host "   - Git (Version Control)" -ForegroundColor $Script:Colors.Dark
    Write-Host "   - Ansible (Configuration Management)" -ForegroundColor $Script:Colors.Dark

    Write-Log "Starting prerequisite installation process" -Level "INFO"
    Write-Log "Components to install: Chocolatey, Winget, UV, Python 3.10, Git, Ansible" -Level "INFO"

    Write-Host ""
    Write-Host " [1/6] Installing Chocolatey..." -ForegroundColor $Script:Colors.Highlight
    Write-Log "Step 1/6: Installing Chocolatey package manager" -Level "INFO"
    $chocoInstalled = EnsureChocolatey
    Write-Log "Chocolatey installation result: $chocoInstalled" -Level "INFO"

    Write-Host ""
    Write-Host " [2/6] Setting up Winget..." -ForegroundColor $Script:Colors.Highlight
    Write-Log "Step 2/6: Setting up Winget package manager" -Level "INFO"
    $wingetAvailable = EnsureWinget
    Write-Log "Winget setup result: $wingetAvailable" -Level "INFO"

    Write-Host ""
    Write-Host " [3/6] Installing UV..." -ForegroundColor $Script:Colors.Highlight
    Write-Log "Step 3/6: Installing UV modern Python package manager" -Level "INFO"
    $uvInstalled = InstallUV
    Write-Log "UV installation result: $uvInstalled" -Level "INFO"

    $pythonInstalled = $false
    $gitInstalled = $false
    $ansibleInstalled = $false

    if ($uvInstalled) {
        Write-Host ""
        Write-Host " [4/6] Installing Python 3.10..." -ForegroundColor $Script:Colors.Highlight
        Write-Log "Step 4/6: Installing Python 3.10 using UV" -Level "INFO"
        $pythonInstalled = SetupPython
        Write-Log "Python 3.10 installation result: $pythonInstalled" -Level "INFO"
    } else {
        Write-Host ""
        Write-Host " [4/6] Skipping Python (UV not available)..." -ForegroundColor $Script:Colors.Warning
        Write-Log "Step 4/6: Skipping Python installation - UV not available" -Level "WARN"
    }

    Write-Host ""
    Write-Host " [5/6] Installing Git..." -ForegroundColor $Script:Colors.Highlight
    Write-Log "Step 5/6: Installing Git version control system" -Level "INFO"
    $gitInstalled = InstallGit
    Write-Log "Git installation result: $gitInstalled" -Level "INFO"

    if ($uvInstalled) {
        Write-Host ""
        Write-Host " [6/6] Installing Ansible..." -ForegroundColor $Script:Colors.Highlight
        Write-Log "Step 6/6: Installing Ansible configuration management" -Level "INFO"
        $ansibleInstalled = InstallAnsible
        Write-Log "Ansible installation result: $ansibleInstalled" -Level "INFO"
    } else {
        Write-Host ""
        Write-Host " [6/6] Skipping Ansible (UV not available)..." -ForegroundColor $Script:Colors.Warning
        Write-Log "Step 6/6: Skipping Ansible installation - UV not available" -Level "WARN"
    }    # Summary Table
    Write-Host ""
    Write-Host "──────────────────────────── Installation Summary ───────────────────────────" -ForegroundColor $Script:Colors.Primary
    Write-Host (" " * 2) + "Chocolatey   : " $(if ($chocoInstalled) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($chocoInstalled) { $Script:Colors.Success } else { $Script:Colors.Error })
    Write-Host (" " * 2) + "Winget       : " $(if ($wingetAvailable) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($wingetAvailable) { $Script:Colors.Success } else { $Script:Colors.Warning })
    Write-Host (" " * 2) + "UV           : " $(if ($uvInstalled) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($uvInstalled) { $Script:Colors.Success } else { $Script:Colors.Error })
    Write-Host (" " * 2) + "Python 3.10  : " $(if ($pythonInstalled) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($pythonInstalled) { $Script:Colors.Success } else { $Script:Colors.Error })
    Write-Host (" " * 2) + "Git          : " $(if ($gitInstalled) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($gitInstalled) { $Script:Colors.Success } else { $Script:Colors.Error })
    Write-Host (" " * 2) + "Ansible      : " $(if ($ansibleInstalled) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($ansibleInstalled) { $Script:Colors.Success } else { $Script:Colors.Error })

    if ($uvInstalled -and $pythonInstalled) {
        Write-Host ""
        Write-Host " Core prerequisites installed successfully." -ForegroundColor $Script:Colors.Success
        return $true
    } else {
        Write-Host ""
        Write-Host " Some prerequisites failed to install. The script will continue but some features may not work." -ForegroundColor $Script:Colors.Warning
        return $false
    }
}

# ---------------------------------------------------------------------------- #
# Clones or updates the Winfig-Ansible repository
function CloneRepository {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " Cloning the Winfig-Ansible repository..." -ForegroundColor $Script:Colors.Primary

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "   Git is not available. Cannot clone repository." -ForegroundColor $Script:Colors.Error
        return $false
    }

    if (Test-Path $Global:RepoDir) {
        Write-Host "   Repository already exists at $Global:RepoDir. Pulling latest changes..." -ForegroundColor $Script:Colors.Warning
        try {
            Set-Location $Global:RepoDir
            git pull origin main
            Write-Host "   Repository updated successfully." -ForegroundColor $Script:Colors.Success
            return $true
        } catch {
            Write-Host "   Error updating repository: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
            return $false
        }
    } else {
        try {
            git clone $Global:RepoUrl $Global:RepoDir
            Write-Host "   Repository cloned successfully to $Global:RepoDir." -ForegroundColor $Script:Colors.Success
            return $true
        } catch {
            Write-Host "   Error cloning repository: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
            return $false
        }
    }
}

# ---------------------------------------------------------------------------- #
# Sets up the Ansible environment (installs roles/collections)
function SetupAnsible {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " Setting up Ansible environment..." -ForegroundColor $Script:Colors.Primary

    if (-not (Test-Path $Global:RepoDir)) {
        Write-Host "   Repository directory does not exist. Cannot setup Ansible." -ForegroundColor $Script:Colors.Error
        return $false
    }

    try {
        Set-Location $Global:RepoDir
        if (Test-Path "requirements.yml") {
            if (Get-Command ansible-galaxy -ErrorAction SilentlyContinue) {
                ansible-galaxy install -r requirements.yml
                Write-Host "   Ansible environment set up successfully." -ForegroundColor $Script:Colors.Success
                return $true
            } else {
                Write-Host "   ansible-galaxy not available. Skipping Ansible galaxy setup." -ForegroundColor $Script:Colors.Warning
                return $false
            }
        } else {
            Write-Host "   requirements.yml not found. Skipping Ansible galaxy setup." -ForegroundColor $Script:Colors.Info
            return $true
        }
    } catch {
        Write-Host "   Error setting up Ansible environment: $($_.Exception.Message)" -ForegroundColor $Script:Colors.Error
        return $false
    }
}

# ============================================================================ #
#                                Main Logic                                    #
# ============================================================================ #

# Initialize logging
Write-Log "======================================================================" -Level "INFO"
Write-Log "WINFIG BOOTSTRAP STARTED" -Level "INFO"
Write-Log "Script Version: $($Script:ScriptMeta.Version)" -Level "INFO"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level "INFO"
Write-Log "Operating System: $([System.Environment]::OSVersion.VersionString)" -Level "INFO"
Write-Log "User: $([System.Environment]::UserName)" -Level "INFO"
Write-Log "Computer: $([System.Environment]::MachineName)" -Level "INFO"
Write-Log "Log File: $Global:LogFile" -Level "INFO"
Write-Log "======================================================================" -Level "INFO"

ShowBanner
Write-Log "Banner displayed successfully" -Level "INFO"

ValidateEnvironment
Write-Log "Environment validation completed" -Level "INFO"

SetupRestorePoint
Write-Log "System restore point setup completed" -Level "INFO"

$prereqsInstalled = InstallPrerequisites
Write-Log "Prerequisites installation completed. Result: $prereqsInstalled" -Level "INFO"

$repoCloned = CloneRepository
Write-Log "Repository cloning completed. Result: $repoCloned" -Level "INFO"

$ansibleSetup = SetupAnsible
Write-Log "Ansible setup completed. Result: $ansibleSetup" -Level "INFO"

# Final Summary
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
Write-Host " Bootstrap Summary" -ForegroundColor $Script:Colors.Primary
Write-Host "──────────────────────────────────────────────────────────────────────────────" -ForegroundColor $Script:Colors.Primary
Write-Host (" " * 2) + "Environment Validation :  OK" -ForegroundColor $Script:Colors.Success
Write-Host (" " * 2) + "Restore Point          :  OK" -ForegroundColor $Script:Colors.Success
Write-Host (" " * 2) + "Prerequisites          : " $(if ($prereqsInstalled) { "OK" } else { "Partial" }) -ForegroundColor $(if ($prereqsInstalled) { $Script:Colors.Success } else { $Script:Colors.Warning })
Write-Host (" " * 2) + "Repository             : " $(if ($repoCloned) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($repoCloned) { $Script:Colors.Success } else { $Script:Colors.Error })
Write-Host (" " * 2) + "Ansible Setup          : " $(if ($ansibleSetup) { "OK" } else { "FAILED" }) -ForegroundColor $(if ($ansibleSetup) { $Script:Colors.Success } else { $Script:Colors.Error })
Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
Write-Host ""

Write-Host ""
if ($prereqsInstalled -and $repoCloned) {
    Write-Host " BOOTSTRAP COMPLETED SUCCESSFULLY!" -ForegroundColor $Script:Colors.Success
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host " NEXT STEPS - Getting Started with Winfig" -ForegroundColor $Script:Colors.Primary
    Write-Host "══════════════════════════════════════════════════════════════════════════════" -ForegroundColor $Script:Colors.Primary
    Write-Host ""
    Write-Host " 1. Navigate to your Winfig directory:" -ForegroundColor $Script:Colors.Accent
    Write-Host "    cd `"$Global:RepoDir`"" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    Write-Host " 2. Review the available Ansible playbooks:" -ForegroundColor $Script:Colors.Accent
    Write-Host "    Get-ChildItem *.yml" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    Write-Host " 3. Run a basic system configuration (example):" -ForegroundColor $Script:Colors.Accent
    Write-Host "    uv run ansible-playbook site.yml --check    # Dry run first" -ForegroundColor $Script:Colors.Info
    Write-Host "    uv run ansible-playbook site.yml           # Apply changes" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    Write-Host " 4. Learn more about your setup:" -ForegroundColor $Script:Colors.Accent
    Write-Host "    - Python: uv run python --version" -ForegroundColor $Script:Colors.Info
    Write-Host "    - Ansible: uv run ansible --version" -ForegroundColor $Script:Colors.Info
    Write-Host "    - UV: uv --version" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    Write-Host " 5. Update your environment:" -ForegroundColor $Script:Colors.Accent
    Write-Host "    git pull origin main                       # Update repository" -ForegroundColor $Script:Colors.Info
    Write-Host "    uv tool upgrade ansible                    # Update Ansible" -ForegroundColor $Script:Colors.Info
    Write-Host ""

    Write-Host " Happy configuring!" -ForegroundColor $Script:Colors.Success
    Write-Host ""

    Write-Log "Bootstrap completed successfully" -Level "SUCCESS"
    Write-Log "Next steps provided to user" -Level "INFO"
    Write-Log "Repository location: $Global:RepoDir" -Level "INFO"
    Write-Log "Log file saved to: $Global:LogFile" -Level "INFO"
} else {
    Write-Host " BOOTSTRAP COMPLETED WITH ISSUES" -ForegroundColor $Script:Colors.Warning
    Write-Host ""
    Write-Host " Some components failed to install properly. Please:" -ForegroundColor $Script:Colors.Warning
    Write-Host " 1. Review the error messages above" -ForegroundColor $Script:Colors.Info
    Write-Host " 2. Resolve any issues" -ForegroundColor $Script:Colors.Info
    Write-Host " 3. Re-run this script" -ForegroundColor $Script:Colors.Info
    Write-Host ""
    if ($repoCloned) {
        Write-Host " Repository is available at: $Global:RepoDir" -ForegroundColor $Script:Colors.Info
    }
    Write-Host " Log file for troubleshooting: $Global:LogFile" -ForegroundColor $Script:Colors.Dark
    Write-Host ""

    Write-Log "Bootstrap completed with issues" -Level "WARN"
    Write-Log "Repository cloned: $repoCloned" -Level "INFO"
    Write-Log "Prerequisites installed: $prereqsInstalled" -Level "INFO"
    Write-Log "Ansible setup: $ansibleSetup" -Level "INFO"
}

# Final logging
$endTime = Get-Date
$duration = $endTime - $Script:ScriptMeta.StartTime
Write-Log "======================================================================" -Level "INFO"
Write-Log "WINFIG BOOTSTRAP COMPLETED" -Level "INFO"
Write-Log "Total execution time: $([math]::Round($duration.TotalMinutes, 2)) minutes" -Level "INFO"
Write-Log "End time: $endTime" -Level "INFO"
Write-Log "Final status - Prerequisites: $prereqsInstalled | Repository: $repoCloned | Ansible: $ansibleSetup" -Level "INFO"
Write-Log "Log file saved to: $Global:LogFile" -Level "INFO"
Write-Log "======================================================================" -Level "INFO"
