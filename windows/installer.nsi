; Instalador de BennuGD2 Media Player (por usuario, sin permisos de administrador).
; Se compila con:  makensis /DSRC=<carpeta con el paquete de Windows> /DVERSION=1.2.0 /DOUT=<instalador.exe> installer.nsi
Unicode true
!include "MUI2.nsh"

Name "BennuGD2 Media Player"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\BennuGD2 Media Player"
InstallDirRegKey HKCU "Software\BennuGD2MediaPlayer" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "BennuGD2 Media Player"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "BennuGD2 Media Player installer"
VIAddVersionKey "LegalCopyright" "MIT"

!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApp
!define MUI_FINISHPAGE_RUN_TEXT "Run BennuGD2 Media Player"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${SRC}\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Spanish"

Function LaunchApp
  Exec '"$SYSDIR\wscript.exe" "$INSTDIR\launch.vbs"'
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SRC}\*.*"
  File "launch.vbs"
  File "mediaplayer.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\BennuGD2 Media Player"
  CreateShortcut "$SMPROGRAMS\BennuGD2 Media Player\BennuGD2 Media Player.lnk" "$SYSDIR\wscript.exe" '"$INSTDIR\launch.vbs"' "$INSTDIR\mediaplayer.ico" 0 SW_SHOWNORMAL "" "BennuGD2 Media Player"
  CreateShortcut "$SMPROGRAMS\BennuGD2 Media Player\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\BennuGD2 Media Player.lnk" "$SYSDIR\wscript.exe" '"$INSTDIR\launch.vbs"' "$INSTDIR\mediaplayer.ico" 0 SW_SHOWNORMAL "" "BennuGD2 Media Player"
  WriteRegStr HKCU "Software\BennuGD2MediaPlayer" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "DisplayName" "BennuGD2 Media Player"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "DisplayIcon" "$INSTDIR\mediaplayer.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "Publisher" "Rufidj"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer" "NoModify" 1
SectionEnd

Section "Uninstall"
  ; los ajustes, listas y addons del usuario (%APPDATA%\bennugd2-media-player) no se borran
  RMDir /r "$INSTDIR"
  Delete "$DESKTOP\BennuGD2 Media Player.lnk"
  RMDir /r "$SMPROGRAMS\BennuGD2 Media Player"
  DeleteRegKey HKCU "Software\BennuGD2MediaPlayer"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BennuGD2MediaPlayer"
SectionEnd
