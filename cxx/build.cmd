set MSYS2_PATH_TYPE=inherit
call "D:\Apps\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
"D:\Apps\msys64\usr\bin\bash.exe" --login %~dp0build.sh