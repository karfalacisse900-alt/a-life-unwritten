@echo off
set "GODOT_EXE=%~dp0..\Godot-4.7.2-standard\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 was not found beside the project folder.
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%~dp0"
