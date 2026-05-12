; ============================================================================
; wolf-fc.iss — Inno Setup script for the Windows installer.
;
; Build invocation (from MSYS2 UCRT64 via the Makefile):
;   iscc.exe /Q /DVersion=yy.mm.dd.SS /DBin=...wolf-fc.exe /DSdl2Dll=...SDL2.dll \
;            packaging/wolf-fc.iss
;
; What this installer does beyond the standard Inno Setup defaults:
;   * Steam auto-detect — registry probe + libraryfolders.vdf scan to find
;     Wolfenstein 3D's data dir, pre-filling the data-files wizard page.
;   * Custom data-dir wizard page with a soft warning when no VSWAP.WL6 is
;     present at the chosen path (install proceeds; game refuses to start
;     until data files arrive).
;   * Writes %USERPROFILE%\.wolf-fc\data_dir.txt so wolf-fc.exe's
;     data_path.resolve() picks up the user's choice on launch.
;   * On uninstall, prompts to delete only .WL6 files that live INSIDE the
;     install dir; anything elsewhere (Steam dir, user-chosen folder) is
;     left untouched.
;   * data_dir.txt is NOT removed on uninstall — a reinstall remembers the
;     previous choice.
; ============================================================================

#define MyAppName "Wolf-FC"
#define MyAppPublisher "Stephen Swensen"
#define MyAppURL "https://github.com/stephen-swensen/wolf-fc"
#define MyAppExeName "wolf-fc.exe"

; Build-time inputs arrive as environment variables (not /D defines),
; because /D values are C-string-parsed — backslashes would need doubling.
; GetEnv() returns the raw value, so UNC paths (\\wsl.localhost\...) and
; native paths with \U etc. pass through cleanly.
#define Version GetEnv("WOLFFC_VERSION")
#if Version == ""
  #undef Version
  #define Version "0.0.0.0"
#endif

#define Bin GetEnv("WOLFFC_BIN")
#if Bin == ""
  #undef Bin
  #define Bin "..\build\windows\wolf-fc.exe"
#endif

#define Sdl2Dll GetEnv("WOLFFC_SDL2_DLL")
#if Sdl2Dll == ""
  #undef Sdl2Dll
  #define Sdl2Dll "C:\msys64\ucrt64\bin\SDL2.dll"
#endif

[Setup]
; AppId uniquely identifies the product; NEVER change this across releases
; or Windows treats upgrades as separate installs.
AppId={{1c60f0bf-0c70-4b2e-a095-29241b5c9282}
AppName={#MyAppName}
AppVersion={#Version}
VersionInfoVersion={#Version}
AppVerName={#MyAppName} {#Version}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=wolf-fc-setup-{#Version}
SetupIconFile=icon\wolf-fc.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";   Description: "Create a &desktop shortcut";    GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startmenuicon"; Description: "Create a &Start Menu shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#Bin}";        DestDir: "{app}"; Flags: ignoreversion
Source: "{#Sdl2Dll}";    DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE";    DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md";  DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}";              Filename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{group}\Uninstall {#MyAppName}";    Filename: "{uninstallexe}";        Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}";        Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DataDirPage: TInputDirWizardPage;

// Read Steam's install path from the registry. Tries the WOW6432Node hive
// first (the typical 32-bit-on-64-bit-Windows layout) then the plain key.
function GetSteamInstall(): String;
begin
  Result := '';
  if not RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath', Result) then
    if not RegQueryStringValue(HKLM, 'SOFTWARE\Valve\Steam', 'InstallPath', Result) then
      Result := '';
end;

// Probe a Steam library root for Wolfenstein 3D's data folder.
function CheckLibrary(LibRoot: String): String;
var
  Candidate: String;
begin
  Result := '';
  Candidate := LibRoot + '\steamapps\common\Wolfenstein 3D\base';
  if FileExists(Candidate + '\VSWAP.WL6') then
    Result := Candidate;
end;

// Extract the quoted string that follows `Marker` on a single VDF line.
// E.g. for line `"path"   "D:\\SteamLibrary"` with Marker='"path"', returns
// the bytes between the second pair of double quotes. Empty result means
// no match. Pascal Script lacks PosEx, so we slice the tail with Copy and
// run Pos against successively shorter substrings.
function ExtractQuotedAfter(Line, Marker: String): String;
var
  P: Integer;
  Tail: String;
begin
  Result := '';
  P := Pos(Marker, Line);
  if P = 0 then Exit;
  Tail := Copy(Line, P + Length(Marker), Length(Line));
  P := Pos('"', Tail);
  if P = 0 then Exit;
  Tail := Copy(Tail, P + 1, Length(Tail));
  P := Pos('"', Tail);
  if P = 0 then Exit;
  Result := Copy(Tail, 1, P - 1);
end;

// Parse libraryfolders.vdf for additional Steam library paths. The VDF is
// indented key-value pairs; we scan for `"path"  "<value>"` and unescape
// the doubled backslashes Steam writes.
function ScanLibraryFolders(VdfPath: String): TArrayOfString;
var
  Lines: TArrayOfString;
  I: Integer;
  Path: String;
begin
  SetArrayLength(Result, 0);
  if not LoadStringsFromFile(VdfPath, Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Path := ExtractQuotedAfter(Lines[I], '"path"');
    if Path <> '' then
    begin
      StringChangeEx(Path, '\\', '\', True);
      SetArrayLength(Result, GetArrayLength(Result) + 1);
      Result[GetArrayLength(Result) - 1] := Path;
    end;
  end;
end;

// End-to-end Steam Wolf3D detection. Empty result = no Wolf3D found.
function DetectWolf3DDataDir(): String;
var
  Steam, Found: String;
  Libs: TArrayOfString;
  I: Integer;
begin
  Result := '';
  Steam := GetSteamInstall();
  if Steam = '' then Exit;

  Found := CheckLibrary(Steam);
  if Found <> '' then begin Result := Found; Exit; end;

  Libs := ScanLibraryFolders(Steam + '\steamapps\libraryfolders.vdf');
  for I := 0 to GetArrayLength(Libs) - 1 do
  begin
    Found := CheckLibrary(Libs[I]);
    if Found <> '' then begin Result := Found; Exit; end;
  end;
end;

// Read a previous install's data_dir.txt to default the wizard there.
function ReadPreviousDataDir(): String;
var
  HomeDir, Path: String;
  Lines: TArrayOfString;
begin
  Result := '';
  HomeDir := GetEnv('USERPROFILE');
  if HomeDir = '' then Exit;
  Path := HomeDir + '\.wolf-fc\data_dir.txt';
  if not LoadStringsFromFile(Path, Lines) then Exit;
  if GetArrayLength(Lines) = 0 then Exit;
  Result := Trim(Lines[0]);
  if (Result <> '') and not DirExists(Result) then
    Result := '';
end;

procedure InitializeWizard();
var
  Default: String;
begin
  DataDirPage := CreateInputDirPage(wpSelectDir,
    'Wolfenstein 3D Data Files',
    'Where are your .WL6 data files?',
    'Wolf-FC needs the original Wolfenstein 3D data files (VSWAP.WL6, MAPHEAD.WL6, etc.) ' +
      'from a legitimate Wolf3D install. Pick the folder containing them, or browse to one.' #13#10 #13#10 +
      'You can install Wolf-FC now and copy the data files later — the game will refuse to ' +
      'start until they''re in place.',
    False, '');
  DataDirPage.Add('Data files folder:');

  // Default search order: previous data_dir.txt → Steam auto-detect → {app}\data
  Default := ReadPreviousDataDir();
  if Default = '' then
    Default := DetectWolf3DDataDir();
  if Default = '' then
    Default := ExpandConstant('{app}\data');
  DataDirPage.Values[0] := Default;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Dir: String;
begin
  Result := True;
  if CurPageID = DataDirPage.ID then
  begin
    Dir := Trim(DataDirPage.Values[0]);
    if not FileExists(Dir + '\VSWAP.WL6') then
    begin
      Result := MsgBox(
        'No VSWAP.WL6 found in:' #13#10 + Dir + #13#10 #13#10 +
        'You can continue with the installation, but Wolf-FC won''t run until you copy ' +
        'the .WL6 files into that folder.' #13#10 #13#10 +
        'Continue anyway?',
        mbConfirmation, MB_YESNO) = IDYES;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  HomeDir, WolfFcDir, FilePath: String;
  Lines: TArrayOfString;
begin
  if CurStep <> ssPostInstall then Exit;
  HomeDir := GetEnv('USERPROFILE');
  if HomeDir = '' then Exit;
  WolfFcDir := HomeDir + '\.wolf-fc';
  if not DirExists(WolfFcDir) then
    ForceDirectories(WolfFcDir);
  FilePath := WolfFcDir + '\data_dir.txt';
  SetArrayLength(Lines, 1);
  Lines[0] := Trim(DataDirPage.Values[0]);
  if SaveStringsToFile(FilePath, Lines, False) then
    Log('Wrote ' + FilePath + ' -> ' + Lines[0])
  else
    Log('WARNING: failed to write ' + FilePath);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep <> usUninstall then Exit;
  DataDir := ExpandConstant('{app}\data');
  // Only ever prompt about data files that live INSIDE the install dir.
  // Anything the user pointed us at elsewhere (Steam, custom path) is
  // owned by them and we never touch it.
  if FileExists(DataDir + '\VSWAP.WL6') then
  begin
    if MsgBox(
      'Wolf-FC found .WL6 data files inside the install folder:' #13#10 +
      DataDir + #13#10 #13#10 +
      'Delete them too? Choose No to keep them in place.',
      mbConfirmation, MB_YESNO) = IDYES then
      DelTree(DataDir, True, True, True);
  end;
end;
