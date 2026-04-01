; Farm Dashboard — ImageMagick is installed automatically after app files (electron-builder NSIS include).

!macro customInstall
  IfFileExists "$INSTDIR\resources\install-imagemagick.ps1" FarmDash_RunMagick FarmDash_MagickDone
  FarmDash_RunMagick:
    DetailPrint "Installing ImageMagick (mod folder DDS to PNG thumbnails)..."
    ExecWait 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\resources\install-imagemagick.ps1"'
  FarmDash_MagickDone:
!macroend
