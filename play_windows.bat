@echo off
rem Launches the already-built Cubyz from the project root, so that assets/ resolves.
rem Unlike run_windows.bat this does not rebuild and does not download a compiler.
rem
rem The release build reads settings.zig.zon, not debug_settings.zig.zon.

cd /D "%~dp0"

if not exist "zig-out\bin\Cubyz.exe" (
	echo Cubyz.exe not found. Build it first: run_windows.bat downloads Zig and builds,
	echo or with your own Zig 0.16.0:
	echo     zig build -Doptimize=ReleaseFast
	exit /b 1
)

zig-out\bin\Cubyz.exe %*
