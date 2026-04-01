ImageMagick bundle (optional for maintainers)
=============================================

The installer normally installs ImageMagick automatically (winget, Chocolatey, or a download from imagemagick.org). You do not need to put anything here for a standard release.

To ship a fully offline installer, place ONE official Windows x64 ImageMagick installer .exe here before "npm run dist" (e.g. ImageMagick-*-Q16*-HDRI-x64-dll.exe). That copy is used first, before any network step.
