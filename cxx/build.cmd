@echo off
set MSYS2_PATH_TYPE=inherit
set ANDROID_NDK_HOME=D:/Apps/AndroidSdk/ndk/21.4.7075529
for /F %%i in (
    '"%PROGRAMFILES(x86)%/Microsoft Visual Studio/Installer/vswhere.exe" -nologo -latest -products * -property installationPath -requires Microsoft.VisualStudio.Workload.VCTools'
) do ( call %%i/VC/Auxiliary/Build/vcvarsall.bat x64 )
"D:\Apps\msys64\usr\bin\bash.exe" --login %~dp0build.sh