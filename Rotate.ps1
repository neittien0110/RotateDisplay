param(
    # Nhận tham số dòng lệnh 0|1|2|3 ứng với 0°|90°|180°|270°
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet(-1, 0, 1, 2, 3)]
    [int]$Rotate = -1
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ====== Hằng số: màn hình cần áp dụng (SourceGdiName dạng \\.\DISPLAYx) ======
# Ví dụ: '\\.\DISPLAY4' hoặc '\\.\DISPLAY1'
$SUB_DISPLAY = '\\.\DISPLAY4'


$code = @"
using System;
using System.Runtime.InteropServices;

namespace WinDisp {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME   = 32;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
        public string dmDeviceName;

        public UInt16 dmSpecVersion;
        public UInt16 dmDriverVersion;
        public UInt16 dmSize;
        public UInt16 dmDriverExtra;
        public UInt32 dmFields;

        public Int32  dmPositionX;
        public Int32  dmPositionY;

        public UInt32 dmDisplayOrientation; // 0,1,2,3
        public UInt32 dmDisplayFixedOutput;

        public Int16  dmColor;
        public Int16  dmDuplex;
        public Int16  dmYResolution;
        public Int16  dmTTOption;
        public Int16  dmCollate;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)]
        public string dmFormName;

        public UInt16 dmLogPixels;
        public UInt32 dmBitsPerPel;
        public UInt32 dmPelsWidth;
        public UInt32 dmPelsHeight;
        public UInt32 dmDisplayFlags;
        public UInt32 dmDisplayFrequency;
        public UInt32 dmICMMethod;
        public UInt32 dmICMIntent;
        public UInt32 dmMediaType;
        public UInt32 dmDitherType;
        public UInt32 dmReserved1;
        public UInt32 dmReserved2;
        public UInt32 dmPanningWidth;
        public UInt32 dmPanningHeight;
    }

    public static class NativeMethods {
        public const int ENUM_CURRENT_SETTINGS = -1;

        // dmFields flags
        public const int DM_DISPLAYORIENTATION = 0x00000080;
        public const int DM_PELSWIDTH         = 0x00080000;
        public const int DM_PELSHEIGHT        = 0x00100000;

        // orientation values
        public const int DMDO_DEFAULT = 0;
        public const int DMDO_90      = 1;
        public const int DMDO_180     = 2;
        public const int DMDO_270     = 3;

        // ChangeDisplaySettingsEx flags
        public const uint CDS_UPDATEREGISTRY = 0x00000001;
        public const uint CDS_TEST          = 0x00000002;
        public const uint CDS_FULLSCREEN    = 0x00000004;
        public const uint CDS_GLOBAL        = 0x00000008;
        public const uint CDS_RESET         = 0x40000000;

        // Return codes
        public const int DISP_CHANGE_SUCCESSFUL = 0;
        public const int DISP_CHANGE_RESTART    = 1;
        public const int DISP_CHANGE_FAILED     = -1;

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        public static extern bool EnumDisplaySettings(
            string lpszDeviceName,
            int iModeNum,
            ref DEVMODE lpDevMode
        );

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        public static extern int ChangeDisplaySettingsEx(
            string lpszDeviceName,
            ref DEVMODE lpDevMode,
            IntPtr hwnd,
            uint dwflags,
            IntPtr lParam
        );
    }
}
"@

# Nạp kiểu (nếu chưa nạp trong session này)
if (-not ([System.Management.Automation.PSTypeName] 'WinDisp.DEVMODE').Type) {
    Add-Type -TypeDefinition $code -Language CSharp
}



function Set-DisplayRotation {
    [CmdletBinding()]
    param(
        # NewOrientation: 0=Landscape (0°), 1=Portrait (90°), 2=Landscape flipped (180°), 3=Portrait flipped (270°)
        [Parameter(Mandatory)]
        [ValidateSet(0, 1, 2, 3)]
        [int]$NewOrientation,

        # Tên thiết bị dạng \\.\DISPLAYx (ví dụ \\.\DISPLAY1, \\.\DISPLAY4)
        [Parameter(Mandatory)]
        [string]$DeviceName,

        # (Tuỳ chọn) chỉ test khả năng áp dụng mà không commit registry/reset
        [switch]$TestOnly
    )

    # --- B1: Lấy DEVMODE hiện tại ---
    $dm = New-Object WinDisp.DEVMODE
    $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinDisp.DEVMODE')

    $ok = [WinDisp.NativeMethods]::EnumDisplaySettings(
        $DeviceName,
        [WinDisp.NativeMethods]::ENUM_CURRENT_SETTINGS,
        [ref]$dm
    )
    if (-not $ok) {
        throw "EnumDisplaySettings thất bại cho '$DeviceName'."
    }

    $old = [int]$dm.dmDisplayOrientation
    $new = [int]$NewOrientation

    # --- B2: Xác định có cần swap width/height hay không ---
    # Quy tắc: nếu parity (chẵn/lẻ) khác nhau → swap (90/270 vs 0/180)
    $needsSwap = (($old % 2) -ne ($new % 2))
    if ($needsSwap) {
        $tmp = $dm.dmPelsWidth
        $dm.dmPelsWidth  = $dm.dmPelsHeight
        $dm.dmPelsHeight = $tmp

        # Thiết lập cờ cho tất cả trường thay đổi
        $dm.dmFields = [WinDisp.NativeMethods]::DM_DISPLAYORIENTATION -bor `
                       [WinDisp.NativeMethods]::DM_PELSWIDTH -bor `
                       [WinDisp.NativeMethods]::DM_PELSHEIGHT
    }
    else {
        $dm.dmFields = [WinDisp.NativeMethods]::DM_DISPLAYORIENTATION
    }

    # --- B3: Gán orientation mới ---
    $dm.dmDisplayOrientation = $new

    # --- B4: Gọi ChangeDisplaySettingsEx ---
    $flags = if ($TestOnly) {
        # Chỉ test (không ghi registry, không reset)
        [WinDisp.NativeMethods]::CDS_GLOBAL -bor [WinDisp.NativeMethods]::CDS_TEST
    }
    else {
        # Ghi registry + reset để driver áp dụng
        [WinDisp.NativeMethods]::CDS_UPDATEREGISTRY -bor [WinDisp.NativeMethods]::CDS_RESET
    }

    $ret = [WinDisp.NativeMethods]::ChangeDisplaySettingsEx(
        $DeviceName,
        [ref]$dm,
        [IntPtr]::Zero,
        $flags,
        [IntPtr]::Zero
    )

    if ($ret -ne [WinDisp.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
        # Một số driver thích hợp gọi RESET sau khi UPDATEREGISTRY, thử lại nếu không ở chế độ Test
        if (-not $TestOnly) {
            $ret2 = [WinDisp.NativeMethods]::ChangeDisplaySettingsEx(
                $DeviceName,
                [ref]$dm,
                [IntPtr]::Zero,
                [WinDisp.NativeMethods]::CDS_RESET,
                [IntPtr]::Zero
            )
            if ($ret2 -ne [WinDisp.NativeMethods]::DISP_CHANGE_SUCCESSFUL) {
                throw "ChangeDisplaySettingsEx thất bại (code=$ret, retry=$ret2) cho '$DeviceName'."
            }
        }
        else {
            throw "ChangeDisplaySettingsEx (TEST) trả về code=$ret cho '$DeviceName'."
        }
    }

    # --- B5: Trả về kết quả ---
    [PSCustomObject]@{
        Device        = $DeviceName
        Old           = $old
        New           = $new
        Swapped       = $needsSwap
        WidthApplied  = $dm.dmPelsWidth
        HeightApplied = $dm.dmPelsHeight
        ReturnCode    = $ret
        TestOnly      = [bool]$TestOnly
    }
}

# ===== Thực thi với SUB_DISPLAY =====
function SetRotation {
    try {
        $result = Set-DisplayRotation -NewOrientation $Rotate -DeviceName $SUB_DISPLAY

        $map = @{
            0 = '0* (DMDO_DEFAULT)'
            1 = '90* (DMDO_90)'
            2 = '180* (DMDO_180)'
            3 = '270* (DMDO_270)'
        }

      
        Write-Host ('Rotated {0} from {1} --> {2}' -f $result.Device, $map[$result.Old], $map[$result.New] ) -ForegroundColor Green
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

#----------------------------------------------------------------------
# Lấy thông tin của các màn hình
#----------------------------------------------------------------------

function Get-DisplayRotation {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms

    $screens = [System.Windows.Forms.Screen]::AllScreens

    $rows = foreach ($s in $screens) {
        $devFull  = $s.DeviceName                # \\.\DISPLAYx
        $devShort = $devFull.Replace('\\.\', '') # DISPLAYx

        # Chuẩn bị DEVMODE
        $dm = New-Object WinDisp.DEVMODE
        $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinDisp.DEVMODE')

        # Gọi API
        $ok = [WinDisp.NativeMethods]::EnumDisplaySettings(
            $devFull,
            [WinDisp.NativeMethods]::ENUM_CURRENT_SETTINGS,
            [ref]$dm
        )

        # Map orientation value -> degrees & text
        $deg = if ($ok) {
            $orientation = [int]$dm.dmDisplayOrientation            
            switch ($orientation) {
                0 { 0 }   # Landscape
                1 { 90 }  # Portrait
                2 { 180 } # Landscape flipped
                3 { 270 } # Portrait flipped
                default { -1 }
            }
        } else {
            # Fallback: nếu EnumDisplaySettings thất bại, suy từ khung hiển thị
            if ($s.Bounds.Width -ge $s.Bounds.Height) { 0 } else { 90 }
        }

        # Tọa độ khung hiển thị (desktop ảo) – hữu ích khi nhiều màn
        $bounds = $s.Bounds

        [PSCustomObject]@{
            'Thiet bi'         = $devShort
            'GDI Name' = $devFull
            'Primary'  = $s.Primary
            'Vung hien thi'    = "X=$($bounds.X), Y=$($bounds.Y), W=$($bounds.Width), H=$($bounds.Height)"
            'Goc xoay'   = $deg
            'Orientation'= $orientation
            'Resolution (px)'  = if ($ok) { '{0}x{1}' -f $dm.dmPelsWidth, $dm.dmPelsHeight } else { $null }
            'Tan so (Hz)'      = if ($ok -and $dm.dmDisplayFrequency) { [int]$dm.dmDisplayFrequency } else { $null }
        }
    }

    return $rows
}


Write-Host 'Danh sach man hinh, Orientation (theo khung) va goc xoay (QDC):' -ForegroundColor Cyan
$displays= Get-DisplayRotation
$displays | Format-Table -AutoSize

$SUB_DISPLAY_ORIENTATION = 0
foreach ($d in $displays) {
    $SUB_DISPLAY = $d.'GDI Name'
    $SUB_DISPLAY_ORIENTATION = $d.'Orientation'
    if (-not $d."Primary") {
        break
    }
}

Write-Host 'Secondary display:' $SUB_DISPLAY ' orientation ' $SUB_DISPLAY_ORIENTATION -ForegroundColor Blue


if ($Rotate -eq -1) {
    $Rotate = ($SUB_DISPLAY_ORIENTATION + 1) % 4
}
SetRotation
