; Chess Library — Windows kurulum dosyası (Inno Setup 6)
;
; Derlemek için:
;   flutter build windows --release
;   ISCC.exe windows\installer\chess_library.iss
;
; Çıktı: windows\installer\output\Chess Library <sürüm> Kurulum.exe
;
; Kurulum, yönetici hakkı istemez: uygulama kullanıcının kendi
; klasörüne kurulur. Böylece kullanıcı UAC uyarısıyla karşılaşmaz.

#define AppName "Chess Library"
#define AppVersion "6.0.0"
#define AppPublisher "stranger-the-unknown"
#define AppExeName "ChessLibrary.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"
; Uygulamanın verisi bu klasörde: %APPDATA%\<yayıncı>\<ad>.
#define DataDir "{userappdata}\io.github.strangertheunknown\Chess Library"
#define DataParent "{userappdata}\io.github.strangertheunknown"

[Setup]
AppId={{7C3E1B24-9A5D-4F86-B0E7-2D9C4A1F6E38}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=output
OutputBaseFilename=Chess Library {#AppVersion} Kurulum
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Yönetici hakkı gerekmez; uygulama kullanıcı klasörüne kurulur.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; 64 bit uygulama.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\LICENSE
DisableProgramGroupPage=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Release klasörünün tamamı: exe, DLL'ler ve data klasörü.
; Bunlardan biri eksik olursa uygulama açılmaz.
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; \
    Flags: ignoreversion recursesubdirs createallsubdirs
; Lisans ve atıf belgeleri kurulumla birlikte gitsin.
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\ASSETS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\COPYRIGHT.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "{cm:LaunchProgram,{#AppName}}"; \
    Flags: nowait postinstall skipifsilent

[CustomMessages]
turkish.RemoveData=Kayıtlı oyunların, listelerin ve ayarların da silinsin mi?%n%nHayır dersen veriler bilgisayarda kalır ve uygulamayı yeniden kurunca geri gelir.
english.RemoveData=Also delete your saved games, lists and settings?%n%nIf you answer No, the data stays on this computer and comes back when you install the app again.

[Code]
// Kullanıcı verisi kaldırma sırasında soruluyor.
//
// Uygulamanın verisi kurulum klasörünün içinde değil,
// %APPDATA% altında duruyor; kaldırma işlemi oraya dokunmadığı için
// uygulama silinip yeniden kurulunca eski listeler ve ayarlar geri
// geliyordu. Soruluyor çünkü yeni sürüme geçmek için önce kaldıran bir
// kullanıcının kitaplığını habersiz silmek olmaz.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  DataDir := ExpandConstant('{#DataDir}');
  if not DirExists(DataDir) then Exit;
  if SuppressibleMsgBox(CustomMessage('RemoveData'), mbConfirmation,
      MB_YESNO, IDYES) = IDYES then
  begin
    DelTree(DataDir, True, True, True);
    // Yayıncı klasörü yalnızca boşsa gidiyor.
    RemoveDir(ExpandConstant('{#DataParent}'));
  end;
end;
