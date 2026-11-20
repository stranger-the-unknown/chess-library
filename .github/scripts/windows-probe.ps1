# CI: uygulamayı Windows'ta açar, ekran görüntüsü alır ve pencereyi
# WM_CLOSE ile kapatır (X düğmesiyle aynı yol: FlutterWindow -> Dart'a
# "kapatılsın mı" sorusu). linux-probe.sh'nin Windows karşılığı.
#
#   windows-probe.ps1 <uygulama> <ekran-görüntüsü.png>
#
# Başarı: uygulama 20 saniye açık kalıyor, "Chess Library" başlıklı bir
# pencere açıyor, veri klasörünü kuruyor ve kapatma isteğinden sonra
# 10 saniye içinde çıkıyor.
#
# Çıkış kodu: koşucuda süreç 0 ile değil 0xC0000409 ile bitiyor. Pencere
# kapandıktan sonra, motor sökülürken Windows'un ses oynatıcısı
# (Windows.Media.dll; just_audio_windows kullanıyor) erişim hatası veriyor.
# Yayımlanmış 10.5.0 paketi aynı koşucuda birebir aynı davranıyor (aynı
# modül, aynı konum); koşucuda ses aygıtı yok, gerçek bilgisayarda olup
# olmadığı bilinmiyor. Bu tek çöküş uyarı olarak geçiyor; olay günlüğünde
# başka bir modül görünürse ya da günlük okunamazsa deneme düşüyor.
param(
  [Parameter(Mandatory = $true)][string]$App,
  [Parameter(Mandatory = $true)][string]$Shot
)
$ErrorActionPreference = 'Stop'

$started = Get-Date
$proc = Start-Process -FilePath $App -PassThru
Start-Sleep -Seconds 20
$proc.Refresh()

if ($proc.HasExited) {
  Write-Host "UYGULAMA ERKEN KAPANDI (kod $($proc.ExitCode))"
  exit 1
}

# Ekran görüntüsü doğrulama için; alınamazsa deneme düşmüyor.
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
  Write-Host "ekran görüntüsü: $($bounds.Width)x$($bounds.Height)"
} catch {
  Write-Host "::warning::Ekran görüntüsü alınamadı: $_"
}

Write-Host "pencere: '$($proc.MainWindowTitle)' ($($proc.MainWindowHandle))"
if ($proc.MainWindowHandle -eq 0 -or $proc.MainWindowTitle -ne 'Chess Library') {
  Write-Host "PENCERE YOK"
  Stop-Process -Id $proc.Id -Force
  exit 1
}

$data = Join-Path $env:APPDATA 'io.github.strangertheunknown\Chess Library'
Get-ChildItem -Force $data -ErrorAction SilentlyContinue | Format-Table Name, Length
if (-not (Test-Path (Join-Path $data 'veri'))) {
  Write-Host "VERİ KLASÖRÜ YOK: $data\veri"
  Stop-Process -Id $proc.Id -Force
  exit 1
}

[void]$proc.CloseMainWindow()
if (-not $proc.WaitForExit(10000)) {
  Write-Host "KAPANMADI"
  Stop-Process -Id $proc.Id -Force
  exit 1
}
Write-Host ("kapatma isteğiyle kapandı (kod 0x{0:X8})" -f $proc.ExitCode)
if ($proc.ExitCode -eq 0) { exit 0 }

# Çöküş: Windows olay günlüğü hangi modülde olduğunu söylüyor.
Start-Sleep -Seconds 8
$events = @(Get-WinEvent -FilterHashtable @{
    LogName = 'Application'; ProviderName = 'Application Error'; StartTime = $started
  } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'ChessLibrary\.exe' })
$modules = @()
foreach ($event in $events) {
  Write-Host "--- $($event.TimeCreated)"
  Write-Host $event.Message
  if ($event.Message -match 'Faulting module name: ([^,\r\n]+)') { $modules += $Matches[1] }
}
$modules = @($modules | Sort-Object -Unique)
Write-Host "çöken modüller: $($modules -join ', ')"
$known = @('Windows.Media.dll', 'ucrtbase.dll')
$other = @($modules | Where-Object { $_ -notin $known })
if ($modules -contains 'Windows.Media.dll' -and $other.Count -eq 0) {
  Write-Host "::warning::Kapanışta bilinen çöküş (Windows.Media.dll, ses oynatıcısı sökülürken; 10.5.0 paketinde de aynı). Pencere kapandıktan sonra oluyor."
  exit 0
}
Write-Host "BEKLENMEYEN ÇIKIŞ KODU"
exit 1
