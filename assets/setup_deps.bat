@echo off
setlocal

reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" /v Installed >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ya_instalado

echo Instalando Visual C++ Redistributable...
powershell -Command "Start-Process '%~dp0vc_redist.x64.exe' -ArgumentList '/install /quiet /norestart' -Verb RunAs -Wait"
echo Instalacion completa.
goto :fin

:ya_instalado
echo VC++ ya instalado. OK.

:fin
endlocal
exit /b 0