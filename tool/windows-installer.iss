#ifndef MyAppVersion
  #define MyAppVersion "1.2.1"
#endif

[Setup]
AppId={{F74A8D3D-7F5D-4DD5-A0CD-09B24CCB1372}
AppName=VN Stock Insight
AppVersion={#MyAppVersion}
AppPublisher=Nguyễn Giang Bảo
DefaultDirName={localappdata}\Programs\VN Stock Insight
DefaultGroupName=VN Stock Insight
UninstallDisplayIcon={app}\vn_stock_insight.exe
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=vn-stock-insight-v{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VN Stock Insight"; Filename: "{app}\vn_stock_insight.exe"
Name: "{autodesktop}\VN Stock Insight"; Filename: "{app}\vn_stock_insight.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vn_stock_insight.exe"; Description: "Launch VN Stock Insight"; Flags: postinstall nowait skipifsilent
