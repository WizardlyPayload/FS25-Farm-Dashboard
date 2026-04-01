; Farm Dashboard — optional ImageMagick page + install hook (electron-builder NSIS include)
; Uses customPageAfterChangeDir (after folder selection, before files install) and customInstall (after app files).

!include nsDialogs.nsh

Var FarmDashInstallMagick
Var FarmDashMagickCheckbox

Function FarmDashImageMagickPage
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 88u "Optional component: ImageMagick converts DDS shop icons (e.g. icon_*.dds) for the dashboard's mod image scanner when a mod does not ship PNG previews.$\r$\n$\r$\nIf you leave this box checked, the installer will try to install ImageMagick using winget (and may show a UAC prompt). You can uncheck this if you already have ImageMagick or only use PNG/texconv."
  Pop $0
  ${NSD_CreateCheckbox} 0 96u 100% 14u "Install ImageMagick for DDS conversion (recommended)"
  Pop $FarmDashMagickCheckbox
  ${NSD_SetState} $FarmDashMagickCheckbox 1
  nsDialogs::Show
FunctionEnd

Function FarmDashImageMagickPageLeave
  ${NSD_GetState} $FarmDashMagickCheckbox $FarmDashInstallMagick
FunctionEnd

!macro customInit
  StrCpy $FarmDashInstallMagick "1"
!macroend

!macro customPageAfterChangeDir
  Page custom FarmDashImageMagickPage FarmDashImageMagickPageLeave
!macroend

!macro customInstall
  StrCmp $FarmDashInstallMagick "1" FarmDash_CheckMagickFile FarmDash_MagickDone
  FarmDash_CheckMagickFile:
    IfFileExists "$INSTDIR\resources\install-imagemagick.ps1" FarmDash_RunMagick FarmDash_MagickDone
  FarmDash_RunMagick:
    DetailPrint "Installing optional ImageMagick (mod image scanner / DDS)..."
    ExecWait 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\install-imagemagick.ps1"'
  FarmDash_MagickDone:
!macroend
