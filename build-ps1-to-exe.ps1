# Install this with Administration right.
# Install-Module -Name PS2EXE -Scope CurrentUser

# Hướng dẫn 
# Dịch với logo chỉ định
# .\build-ps1-to-exe.ps1 -IconFile ".\icon.ico"
# Dịch với logo mặc đinh là file .ico cùng tên với file .ps1
# .\build-ps1-to-exe.ps1"
# Chạy không có màn hình console
# .\build-ps1-to-exe.ps1 -NoConsole"


<#
.SYNOPSIS
    Quet thu muc hien tai (mac dinh de quy) va chuyen tat ca *.ps1 sang *.exe bang PS2EXE.

.PARAMETER Recurse
    Co de quy vao cac thu muc con (mac dinh: $true).

.PARAMETER OutputDir
    Thu muc xuat cac file .exe (mac dinh: thư mục hiện thời).

.PARAMETER NoConsole
    Dong goi o che do khong console (an cua so console khi chay .exe).

.PARAMETER IconFile
    Duong dan toi file .ico de gan icon cho .exe (tuy chon).
    
#>

[CmdletBinding()]
param(
    [switch]$Recurse = $false,
    [string]$OutputDir = "./",
    [switch]$NoConsole = $false,
    [string]$IconFile
)


# --- Cau hinh encoding UTF-8 ---
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Ensure-PS2EXE {
    Write-Host "Kiem tra module PS2EXE..." -ForegroundColor Cyan
    $module = Get-Module -ListAvailable -Name PS2EXE
    if (-not $module) {
        Write-Host "Chua co PS2EXE. Dang cai dat tu PSGallery..." -ForegroundColor Yellow
        try {
            Install-Module PS2EXE -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
            Write-Host "Cai dat PS2EXE thanh cong." -ForegroundColor Green
        }
        catch {
            Write-Error "Loi khi cai dat PS2EXE: $($_.Exception.Message)"
            throw
        }
    }
    Import-Module PS2EXE -ErrorAction Stop
}

function Convert-One {
    param(
        [Parameter(Mandatory)]
        [string]$InputPs1Path,
        [Parameter(Mandatory)]
        [string]$OutputExePath,
        [switch]$NoConsole,
        [string]$IconFile
    )

    $outDir = Split-Path -Parent $OutputExePath
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "Dang chuyen: $InputPs1Path" -ForegroundColor White
    Write-Host "   -> Xuat ra: $OutputExePath" -ForegroundColor DarkGray

    $invokeParams = @{
        InputFile  = $InputPs1Path
        OutputFile = $OutputExePath
    }
    if ($NoConsole) { $invokeParams.NoConsole = $true }
    if ($IconFile)  { $invokeParams.IconFile  = $IconFile }

    try {
        Invoke-PS2EXE @invokeParams
        Write-Host "Hoan thanh: $OutputExePath" -ForegroundColor Green
    }
    catch {
        Write-Host "Loi khi dong goi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Resolve-OutputPath {
    param(
        [Parameter(Mandatory)]
        [string]$RootDir,
        [Parameter(Mandatory)]
        [string]$OutputDir,
        [Parameter(Mandatory)]
        [string]$Ps1Path
    )
    $relative = Resolve-Path -LiteralPath $Ps1Path | ForEach-Object {
        $_.Path.Substring($RootDir.Length).TrimStart('\','/')
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Ps1Path)
    $relativeDir = Split-Path -Parent $relative

    $targetDir = Join-Path -Path $OutputDir -ChildPath $relativeDir
    return (Join-Path -Path $targetDir -ChildPath ($baseName + ".exe"))
}

# --- Bat dau ---
$root = (Get-Location).Path
Write-Host "Thu muc goc: $root" -ForegroundColor Cyan
Write-Host "Thu muc xuat: $OutputDir" -ForegroundColor Cyan
if ($NoConsole) { Write-Host "Che do NoConsole: BAT" -ForegroundColor Cyan }
if ($IconFile)  { Write-Host "Icon mac dinh: $IconFile" -ForegroundColor Cyan }

$logPath = Join-Path $root "build-ps1-to-exe.log"
Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null

try {
    Ensure-PS2EXE

    $searchParams = @{
        Path   = $root
        Filter = "*.ps1"
        File   = $true
    }
    if ($Recurse) { $searchParams.Recurse = $true }

    $ps1Files = Get-ChildItem @searchParams

    # Luon bo qua chinh script nay
    $self = $MyInvocation.MyCommand.Path
    if ($self) {
        $ps1Files = $ps1Files | Where-Object { $_.FullName -ne $self }
    }

    if (-not $ps1Files -or $ps1Files.Count -eq 0) {
        Write-Host "Khong tim thay file .ps1 nao." -ForegroundColor Yellow
        return
    }

    Write-Host "Tim thay $($ps1Files.Count) file .ps1. Bat dau dong goi..." -ForegroundColor Cyan

    foreach ($f in $ps1Files) {
        # Xac dinh icon tu dong: file cung ten .ico nam cung thu muc
        $autoIcon = [System.IO.Path]::ChangeExtension($f.FullName, ".ico")
        $effectiveIcon = $null

        if (Test-Path -LiteralPath $autoIcon) {
            $effectiveIcon = $autoIcon
            Write-Host " -> Phat hien icon cung ten: $effectiveIcon" -ForegroundColor DarkCyan
        }
        elseif ($IconFile) {
            $effectiveIcon = $IconFile
        }

        $outExe = Resolve-OutputPath -RootDir $root -OutputDir $OutputDir -Ps1Path $f.FullName

        Convert-One `
            -InputPs1Path $f.FullName `
            -OutputExePath $outExe `
            -NoConsole:$NoConsole `
            -IconFile $effectiveIcon
    }

    Write-Host "Hoan tat. Xem ket qua trong: $OutputDir" -ForegroundColor Green
    Write-Host "Nhat ky: $logPath" -ForegroundColor DarkGray
}
finally {
    Stop-Transcript | Out-Null
}
